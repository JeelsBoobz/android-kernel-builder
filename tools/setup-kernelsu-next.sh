#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# setup-kernelsu-next.sh - integrate the pershoot/KernelSU-Next driver.
#
# Run with cwd = repo-sync root (the dir containing common/):
#   setup-kernelsu-next.sh [--repo pershoot/KernelSU-Next] [--ref <tag|commit>]
#
# Full clone, .git preserved: kernel/setup.sh needs git stash/pull,
# origin/HEAD and describe --tags, so no --depth and no worktree export.
# Pre-cloning the fork also skips the installer's hardcoded upstream clone
# URL. Empty --ref = latest tag (installer default).
#
# On success the driver is symlinked as common/drivers/kernelsu with
# Makefile/Kconfig hooks, and .fragments/kernelsu.config is written for
# apply-fragments.sh (kept out of fragments/ on purpose: the symbol must
# never be enabled without the driver source present).
set -euo pipefail

REPO="pershoot/KernelSU-Next"; REF=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --ref) REF="$2"; shift 2 ;;
    *) echo "setup-kernelsu-next: unknown arg: $1" >&2; exit 2 ;;
  esac
done

NAME="KernelSU-Next"
[ -d "$NAME" ] || git clone "https://github.com/$REPO" "$NAME"

if [ -n "$REF" ]; then
  bash "$NAME/kernel/setup.sh" "$REF"
else
  bash "$NAME/kernel/setup.sh"
fi

# KSU bakes its version from git (rev-list --count + describe --tags), but
# the Kleaf sandbox strips .git (Bazel excludes **/.*), so every Kleaf build
# would bake KSU_VERSION=1 / tag v0.0.1 -- outside any range the manager app
# accepts. Compute from the runner-side full clone and bake into the
# fallback assignments (same 30000+ formula as Kbuild). build.sh is
# unaffected (real .git present, fallback lines unused).
KSU_COUNT=$(git -C "$NAME" rev-list --count HEAD)
KSU_TAG=$(git -C "$NAME" describe --tags --abbrev=0)
KSU_SHA=$(git -C "$NAME" rev-parse --short HEAD)
KSU_VERSION=$((30000 + KSU_COUNT))
echo "setup-kernelsu-next: source at $KSU_SHA ($KSU_TAG, versionCode $KSU_VERSION)"
# Resolved identity for release notes (TAG SHA requested-REF versionCode;
# empty REF = latest tag). Written into the repo-sync root; the workflow
# uploads it. versionCode is what the manager APK must match.
printf '%s %s %s %s\n' "$KSU_TAG" "$KSU_SHA" "${REF:-}" "$KSU_VERSION" > .ksu-version
KSU_KBUILD=common/drivers/kernelsu/Kbuild
sed -i "s/^KSU_VERSION_FALLBACK := .*/KSU_VERSION_FALLBACK := $KSU_VERSION/" "$KSU_KBUILD"
sed -i "s/^KSU_VERSION_TAG_FALLBACK := .*/KSU_VERSION_TAG_FALLBACK := $KSU_TAG/" "$KSU_KBUILD"
# The sandbox can never have .git (stripped by design), so the warnings
# below stay as upstream wrote them -- values are baked, behavior preserved.
# Verified: if upstream rewords the fallback lines, fail fast here rather
# than silently shipping version 1/v0.0.1.
grep -q "^KSU_VERSION_FALLBACK := $KSU_VERSION$" "$KSU_KBUILD" && \
grep -q "^KSU_VERSION_TAG_FALLBACK := $KSU_TAG$" "$KSU_KBUILD" || \
  { echo "setup-kernelsu-next: version bake verification FAILED" >&2; exit 2; }
echo "setup-kernelsu-next: baked version fallback $KSU_VERSION / $KSU_TAG"

mkdir -p .fragments
cat > .fragments/kernelsu.config <<'EOF'
# KernelSU-Next integrated driver (written by setup-kernelsu-next.sh; only
# exists when the KSU step ran, so source and symbol always agree).
# KSU depends on KPROBES && EXT4_FS (drivers/kernelsu/Kconfig).
CONFIG_KSU=y
CONFIG_KPROBES=y
CONFIG_EXT4_FS=y
EOF
echo "setup-kernelsu-next: driver linked, fragment written"

# WK static.patch port (SuSFS linkage): dev-susfs selinux_hide.c carries
# static forward-decls of security_*_with_policy() with GLOBAL definitions
# below; SuSFS's kernel patch calls them from selinuxfs.c/hooks.c, which
# needs external linkage -- otherwise vmlinux fails with undefined symbols
# on trees whose SELinux predates the API (e.g. 6.12.92). Flip the three
# decls to global iff the static block is present (proves expected
# layout); anything else fails closed. Attribution:
# WildKernels/GKI_KernelSU_SUSFS .github/actions/kernelsu/patches/static.patch.
SEHIDE="$NAME/kernel/feature/selinux_hide.c"
if grep -q "^static int security_context_to_sid_with_policy" "$SEHIDE" 2>/dev/null; then
  sed -i \
    -e 's/^static int security_context_to_sid_with_policy/int security_context_to_sid_with_policy/' \
    -e 's/^static int security_sid_to_context_with_policy/int security_sid_to_context_with_policy/' \
    -e 's/^static void security_compute_av_user_with_policy/void security_compute_av_user_with_policy/' \
    "$SEHIDE"
  grep -q "^static \(int\|void\) security_\(context_to_sid\|sid_to_context\|compute_av_user\)_with_policy" "$SEHIDE" && \
    { echo "setup-kernelsu-next: selinux_hide linkage patch incomplete" >&2; exit 2; }
  grep -q "^int security_context_to_sid_with_policy" "$SEHIDE" || \
    { echo "setup-kernelsu-next: selinux_hide linkage patch missing" >&2; exit 2; }
  echo "setup-kernelsu-next: selinux_hide with_policy linkage set global (SuSFS)"
else
  echo "setup-kernelsu-next: no static with_policy block (plain ref or old KSU); linkage untouched"
fi
