#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any


def _run_git(args: list[str], cwd: Path) -> str:
    proc = subprocess.run(
        ["git", *args],
        cwd=str(cwd),
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} failed: {proc.stderr.strip()}")
    return proc.stdout


def _repo_root(cwd: Path) -> Path:
    out = _run_git(["rev-parse", "--show-toplevel"], cwd=cwd).strip()
    return Path(out)


def _head_sha(cwd: Path) -> str:
    return _run_git(["rev-parse", "HEAD"], cwd=cwd).strip()


def _short_sha(sha: str) -> str:
    return sha[:7]


def _branch_name(cwd: Path) -> str:
    return _run_git(["rev-parse", "--abbrev-ref", "HEAD"], cwd=cwd).strip()


def _repo_name(repo_root: Path) -> str:
    return repo_root.name


def _merge_base(cwd: Path, base_ref: str) -> str:
    return _run_git(["merge-base", base_ref, "HEAD"], cwd=cwd).strip()

def _git_log_oneline(cwd: Path, start_sha: str, end_sha: str) -> list[str]:
    out = _run_git(
        ["log", "--no-decorate", "--format=%h %s", f"{start_sha}..{end_sha}"],
        cwd=cwd,
    )
    lines = [ln.strip() for ln in out.splitlines() if ln.strip()]
    return lines


def _git_name_status(cwd: Path, start_sha: str, end_sha: str) -> list[str]:
    out = _run_git(["diff", "--name-status", f"{start_sha}..{end_sha}"], cwd=cwd)
    result: list[str] = []
    for raw in out.splitlines():
        line = raw.rstrip()
        if not line:
            continue
        parts = line.split("\t")
        status = parts[0].strip()
        paths = [p.strip() for p in parts[1:] if p.strip()]
        if status.startswith("R") and len(paths) >= 2:
            result.append(f"{status} {paths[0]} -> {paths[1]}")
        elif status.startswith("C") and len(paths) >= 2:
            result.append(f"{status} {paths[0]} -> {paths[1]}")
        elif paths:
            result.append(f"{status} {paths[0]}")
        else:
            result.append(status)
    return result


def _git_shortstat(cwd: Path, start_sha: str, end_sha: str) -> str:
    return _run_git(["diff", "--shortstat", f"{start_sha}..{end_sha}"], cwd=cwd).strip()


def _git_status_porcelain(cwd: Path) -> list[str]:
    out = _run_git(["status", "--porcelain"], cwd=cwd)
    return [ln.rstrip() for ln in out.splitlines() if ln.strip()]


def _ensure_parent_dir(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def _read_json(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}


def _write_json(path: Path, data: dict[str, Any]) -> None:
    _ensure_parent_dir(path)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


@dataclass(frozen=True)
class Config:
    obsidian_note_path: str | None
    project_name: str | None
    base_ref: str
    include_diffstat: bool
    max_commits: int
    max_files: int


def _load_config(repo_root: Path) -> Config:
    config_paths = [
        repo_root / ".codex" / "obsidian-change-summary.json",
        repo_root / ".obsidian-change-summary.json",
    ]
    raw: dict[str, Any] = {}
    for p in config_paths:
        if p.exists():
            raw = _read_json(p)
            break

    return Config(
        obsidian_note_path=raw.get("obsidian_note_path"),
        project_name=raw.get("project_name"),
        base_ref=str(raw.get("base_ref") or "origin/main"),
        include_diffstat=bool(raw.get("include_diffstat", True)),
        max_commits=int(raw.get("max_commits", 20)),
        max_files=int(raw.get("max_files", 50)),
    )


def _state_path(repo_root: Path) -> Path:
    return repo_root / ".codex" / "obsidian-change-summary.state.json"


def _load_last_sha(repo_root: Path) -> str | None:
    raw = _read_json(_state_path(repo_root))
    sha = raw.get("last_sha")
    if isinstance(sha, str) and sha.strip():
        return sha.strip()
    return None


def _write_last_sha(repo_root: Path, sha: str) -> None:
    _write_json(_state_path(repo_root), {"last_sha": sha})


def _format_entry(
    *,
    when: datetime,
    repo_root: Path,
    project_name: str | None,
    branch: str,
    start_sha: str,
    end_sha: str,
    commits: list[str],
    files: list[str],
    diffstat: str | None,
    working_tree: list[str] | None,
    max_commits: int,
    max_files: int,
) -> str:
    title_project = project_name or _repo_name(repo_root)
    ts = when.strftime("%Y-%m-%d %H:%M")
    lines: list[str] = []

    lines.append(f"## {ts} — {title_project} ({branch})")
    lines.append("")
    lines.append(f"- Repo: {_repo_name(repo_root)}")
    lines.append(f"- Range: {_short_sha(start_sha)}..{_short_sha(end_sha)}")
    lines.append("")

    if commits:
        lines.append("### Commits")
        shown = commits[: max(0, max_commits)]
        for c in shown:
            lines.append(f"- {c}")
        if max_commits >= 0 and len(commits) > max_commits:
            lines.append(f"- …and {len(commits) - max_commits} more")
        lines.append("")

    if files:
        lines.append("### Files")
        shown = files[: max(0, max_files)]
        for f in shown:
            lines.append(f"- {f}")
        if max_files >= 0 and len(files) > max_files:
            lines.append(f"- …and {len(files) - max_files} more")
        lines.append("")

    if diffstat:
        lines.append("### Stats")
        lines.append("```")
        lines.append(diffstat)
        lines.append("```")
        lines.append("")

    if working_tree:
        lines.append("### Working tree (uncommitted)")
        for wt in working_tree:
            lines.append(f"- {wt}")
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def _append_to_note(note_path: Path, entry: str) -> None:
    _ensure_parent_dir(note_path)
    if note_path.exists():
        existing = note_path.read_text(encoding="utf-8")
        sep = "" if existing.endswith("\n") else "\n"
        note_path.write_text(existing + sep + entry, encoding="utf-8")
    else:
        note_path.write_text(entry, encoding="utf-8")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="Append a Git change summary to an Obsidian note."
    )
    parser.add_argument("--note", help="Absolute path to Obsidian .md note")
    parser.add_argument("--base", help="Base ref used to compute merge-base (default: origin/main)")
    parser.add_argument("--since", help="Start commit SHA (overrides state/base)")
    parser.add_argument("--dry-run", action="store_true", help="Print entry without writing")
    parser.add_argument("--no-state", action="store_true", help="Do not read/write the state file")
    parser.add_argument("--no-diffstat", action="store_true", help="Do not include diffstat section")
    args = parser.parse_args(argv)

    cwd = Path.cwd()
    repo_root = _repo_root(cwd)
    cfg = _load_config(repo_root)

    note = args.note or cfg.obsidian_note_path or os.environ.get("OBSIDIAN_NOTE_PATH")
    if not note and not args.dry_run:
        print(
            "Missing Obsidian note path. Set it in .codex/obsidian-change-summary.json "
            "as obsidian_note_path, or pass --note, or set OBSIDIAN_NOTE_PATH.",
            file=sys.stderr,
        )
        return 2

    end_sha = _head_sha(repo_root)

    start_sha: str | None = None
    if args.since:
        start_sha = args.since
    elif not args.no_state:
        start_sha = _load_last_sha(repo_root)

    base_ref = args.base or cfg.base_ref
    if not start_sha:
        start_sha = _merge_base(repo_root, base_ref)

    commits = _git_log_oneline(repo_root, start_sha, end_sha)
    files = _git_name_status(repo_root, start_sha, end_sha)

    include_diffstat = cfg.include_diffstat and not args.no_diffstat
    diffstat = _git_shortstat(repo_root, start_sha, end_sha) if include_diffstat else None
    if diffstat is not None and not diffstat:
        diffstat = None

    working_tree = None
    if not commits and not files:
        wt = _git_status_porcelain(repo_root)
        if wt:
            working_tree = wt

    if not commits and not files and not working_tree:
        print("No changes detected (no commits, no diff, clean working tree).")
        if not args.no_state and not args.dry_run:
            _write_last_sha(repo_root, end_sha)
        return 0

    entry = _format_entry(
        when=datetime.now(),
        repo_root=repo_root,
        project_name=cfg.project_name,
        branch=_branch_name(repo_root),
        start_sha=start_sha,
        end_sha=end_sha,
        commits=commits,
        files=files,
        diffstat=diffstat,
        working_tree=working_tree,
        max_commits=cfg.max_commits,
        max_files=cfg.max_files,
    )

    if args.dry_run or not note:
        sys.stdout.write(entry)
    else:
        _append_to_note(Path(note).expanduser(), entry)
        if not args.no_state:
            _write_last_sha(repo_root, end_sha)
        print(f"Appended change summary to: {note}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
