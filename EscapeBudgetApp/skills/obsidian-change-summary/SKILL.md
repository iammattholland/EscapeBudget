---
name: obsidian-change-summary
description: Append a Git-based change summary (commits, file list, diff stats) to an Obsidian note for a project. Use when the user wants Codex to write or update an Obsidian project log/changelog/release notes from recent repo changes, or to sync a summary of changes into a specific Obsidian markdown file.
---

# Obsidian Change Summary

## Workflow

1. Confirm the target Obsidian note path (absolute path to a `.md` file).
2. Decide the change range:
   - Prefer “since last sync” (tracked in a local state file).
   - Otherwise use a base ref like `origin/main` (merge-base to `HEAD`).
3. Generate a compact markdown entry:
   - Date/time, repo, branch, `HEAD` short SHA
   - Commits (one-line subjects)
   - Changed files (name-status)
   - Diff stat (optional)
4. Append the entry to the note and update the state file.

## Setup (one time per repo)

Create a config file in the repo:

- `.codex/obsidian-change-summary.json` (recommended), or
- `.obsidian-change-summary.json`

Example:

```json
{
  "obsidian_note_path": "/absolute/path/to/YourVault/Projects/EscapeBudget.md",
  "project_name": "EscapeBudget",
  "base_ref": "origin/main",
  "include_diffstat": true,
  "max_commits": 20,
  "max_files": 50
}
```

Alternative: set `OBSIDIAN_NOTE_PATH` in your shell environment.

## Run

From the repo root:

```bash
/usr/bin/python3 skills/obsidian-change-summary/scripts/append_change_summary.py
```

Useful options:

- `--note /absolute/path/to/note.md` override note path
- `--base origin/main` override base ref
- `--since <sha>` override the starting commit
- `--dry-run` print entry without writing
- `--no-state` do not read/write state (always use base/since)

## Notes

- State is stored at `.codex/obsidian-change-summary.state.json` (tracks last synced `HEAD` SHA).
- If there are no commits in range but there are uncommitted changes, include a “Working tree” section from `git status --porcelain` and a file list.
- Keep entries short; do not paste full diffs into Obsidian.
