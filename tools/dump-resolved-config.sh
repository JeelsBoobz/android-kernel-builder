#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# dump-resolved-config.sh - show resolved values for every symbol our
# fragments set. Data-driven: symbol list comes from the fragment files
# themselves (repo + generated .fragments), never hardcoded here.
#
# Usage: dump-resolved-config.sh --config <resolved .config>
#   [--fragment-dir <dir>]...   (repeatable; *.config files read)
set -euo pipefail

CFG=""; DIRS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --config) CFG="$2"; shift 2 ;;
    --fragment-dir) DIRS+=("$2"); shift 2 ;;
    *) echo "dump-resolved-config: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -f "${CFG:-}" ] || { echo "dump-resolved-config: --config not found" >&2; exit 2; }

SYMS=$(for d in "${DIRS[@]}"; do
  [ -d "$d" ] || continue
  grep -hoE '^#? ?CONFIG_[A-Za-z0-9_]+' "$d"/*.config 2>/dev/null || true
done | grep -oE 'CONFIG_[A-Za-z0-9_]+' | sort -u)
[ -n "$SYMS" ] || { echo "dump-resolved-config: no fragment symbols"; exit 0; }

echo "dump-resolved-config: using $CFG"
for s in $SYMS; do
  line=$(grep -E "^(# )?$s(=| is not set)" "$CFG" | head -1 || true)
  [ -n "$line" ] && echo "$line" || echo "$s (absent from resolved config)"
done
