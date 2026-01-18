#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v rg >/dev/null 2>&1; then
  echo "ripgrep (rg) is required. Install it (e.g. brew install ripgrep)." >&2
  exit 1
fi

echo "Scanning for common secret patterns…"

PATTERNS=(
  # Generic
  "(?i)api[_-]?key\\s*[:=]"
  "(?i)secret\\s*[:=]"
  "(?i)token\\s*[:=]"
  "(?i)bearer\\s+[a-z0-9\\-\\._~\\+\\/]+=*"

  # Apple / iOS
  "-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----"
  "(?i)AuthKey_[A-Z0-9]{10}\\.p8"

  # Common vendors
  "sk-[A-Za-z0-9]{20,}"          # OpenAI
  "AIza[0-9A-Za-z\\-_]{35}"      # Google API key
  "AKIA[0-9A-Z]{16}"             # AWS access key id
)

FAIL=0
for pattern in "${PATTERNS[@]}"; do
  if rg -n --hidden --no-ignore-vcs --glob '!.git/**' --glob '!DerivedData/**' --glob '!.build/**' --glob '!Pods/**' --glob '!Carthage/**' --glob '!*.xcuserstate' --glob '!*.pbxuser' --glob '!*.mode1v3' --glob '!*.mode2v3' --glob '!*.perspectivev3' "$pattern" .; then
    echo
    echo "Potential secret matches found for pattern: $pattern" >&2
    echo "Please audit results and remove/rotate secrets if needed." >&2
    FAIL=1
  fi
done

if [[ "$FAIL" -eq 0 ]]; then
  echo "No matches found."
else
  exit 2
fi

