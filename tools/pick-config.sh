#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# pick-config.sh - print the resolved .config for this build, deterministically.
#
# Usage: pick-config.sh [--kind build_sh|kleaf]   (cwd = repo-sync root)
#
# find order is not deterministic, so: gather all candidates, sort, then
# prefer the known output path for the build era (build.sh -> out/,
# Kleaf -> bazel-bin/common). Falls back to the first sorted candidate.
# Used by verify-susfs.sh and the AK3 pack step so kernel.config in the zip
# is the config baked into the shipped Image, not a stale intermediate.
set -euo pipefail

KIND=""
[ "${1:-}" = "--kind" ] && KIND="${2:-}"
CANDS=$(find out bazel-bin/common -maxdepth 6 -name ".config" 2>/dev/null | sort || true)
[ -n "$CANDS" ] || { echo "pick-config: no .config found" >&2; exit 2; }
case "$KIND" in
  kleaf) PREF="bazel-bin/common" ;;
  build_sh) PREF="^out/" ;;
  *) PREF="" ;;
esac
if [ -n "$PREF" ]; then
  HIT=$(grep -E "$PREF" <<<"$CANDS" | head -1 || true)
  [ -n "$HIT" ] && { echo "$HIT"; exit 0; }
fi
head -1 <<<"$CANDS"
