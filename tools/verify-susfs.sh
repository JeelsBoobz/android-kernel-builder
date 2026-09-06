#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# verify-susfs.sh - end-of-build SuSFS check. Run with cwd = repo-sync root.
#
# Reads the fragment setup-susfs.sh actually wrote: CONFIG_KSU_SUSFS=y
# expected in the compiled .config means SuSFS is in the image; a
# suppression (gated tree) expects it absent. Fails the build on mismatch.
set -euo pipefail

KIND=""
[ "${1:-}" = "--kind" ] && KIND="${2:-}"
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

FRAG=".fragments/susfs.config"
if [ ! -f "$FRAG" ]; then
  echo "verify-susfs: no susfs fragment (plain KSU ref); nothing to check"
  exit 0
fi

if grep -q "^CONFIG_KSU_SUSFS=y" "$FRAG"; then EXPECT=on; else EXPECT=off; fi
echo "verify-susfs: expected SuSFS=$EXPECT"

CFG=$("$HERE/pick-config.sh" --kind "$KIND" 2>/dev/null || true)
[ -n "$CFG" ] || { echo "verify-susfs: no .config found" >&2; exit 2; }
echo "verify-susfs: using $CFG"

if [ "$EXPECT" = "on" ]; then
  grep -q "^CONFIG_KSU_SUSFS=y" "$CFG" || { echo "verify-susfs: FAIL - CONFIG_KSU_SUSFS=y missing from compiled config" >&2; exit 1; }
  for sym in CONFIG_KSU_SUSFS_SUS_PATH CONFIG_KSU_SUSFS_SUS_MOUNT CONFIG_KSU_SUSFS_SUS_KSTAT CONFIG_KSU_SUSFS_SPOOF_UNAME CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG CONFIG_KSU_SUSFS_OPEN_REDIRECT CONFIG_KSU_SUSFS_SUS_MAP; do
    grep -q "^$sym=y" "$CFG" || echo "verify-susfs: WARN $sym not set"
  done
  echo "verify-susfs: PASS - SuSFS compiled in"
else
  grep -q "^CONFIG_KSU_SUSFS=y" "$CFG" && { echo "verify-susfs: FAIL - SuSFS unexpectedly compiled in on gated tree" >&2; exit 1; }
  echo "verify-susfs: PASS - SuSFS correctly absent"
fi
