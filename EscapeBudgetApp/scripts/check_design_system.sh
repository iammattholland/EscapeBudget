#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${ROOT_DIR}/EscapeBudget"

fail=0

echo "Checking for direct font usage..."
if rg -n "\.font\(\." "${SRC_DIR}" | rg -v "DesignSystem.swift" >/tmp/designsystem_fonts.txt; then
  echo "Found direct .font(...) usage outside DesignSystem.swift:"
  cat /tmp/designsystem_fonts.txt
  fail=1
fi

echo "Checking for raw horizontal padding..."
if rg -n "\.padding\(\.horizontal\)" "${SRC_DIR}" >/tmp/designsystem_padding.txt; then
  echo "Found .padding(.horizontal) without tokens:"
  cat /tmp/designsystem_padding.txt
  fail=1
fi

echo "Checking for raw system font sizes..."
if rg -n "\.system\(size:" "${SRC_DIR}" | rg -v "DesignSystem.swift" >/tmp/designsystem_system_fonts.txt; then
  echo "Found .system(size:) outside DesignSystem.swift:"
  cat /tmp/designsystem_system_fonts.txt
  fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  echo "Design system check failed."
  exit 1
fi

echo "Design system check passed."
