#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# setup-susfs.sh - integrate simonpunk/susfs4ksu kernel patches (SuSFS).
#
# Run with cwd = repo-sync root (the dir containing common/), AFTER the
# KernelSU-Next step:
#   setup-susfs.sh --our-branch android14-6.1-stable [--ref <commit>]
#
# SuSFS hides root (mount spoofing, KSU traces, fake overlays) and
# complements NoMount (NoMount redirects paths, SuSFS hides the lie).
# Two-sided integration:
#   KSU side    - already carried by pershoot/KernelSU-Next@dev-susfs, so
#                 NO 10_enable patch is applied here (same as WildKernels:
#                 dev-susfs tip straight from pershoot). Verified below by
#                 grepping KSU_SUSFS in the linked driver Kconfig.
#   kernel side - simonpunk/susfs4ksu per-version branch: fs/susfs.c plus
#                 include/linux/susfs*.h are byte-identical across versions;
#                 only 50_add_susfs_in_<gki-version>.patch differs (hunk
#                 context tracking upstream drift, +1 selinux file on
#                 6.6/6.12). Applied with git apply in common/.
# No upstream branch exists for 6.18 -> clean skip (exit 0, no fragment),
# so that tree builds KSU-only. Writes .fragments/susfs.config for
# apply-fragments.sh (kept out of fragments/ on purpose: the symbol must
# never be enabled without the patched source present).
set -euo pipefail

REPO="simonpunk/susfs4ksu"; REF=""; OUR_BRANCH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --ref) REF="$2"; shift 2 ;;
    --our-branch) OUR_BRANCH="$2"; shift 2 ;;
    *) echo "setup-susfs: unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Our -stable branch -> simonpunk gki branch. -lts accepted the same way
# (suffix ignored); anything unmapped (6.18+) skips cleanly.
case "$OUR_BRANCH" in
  android12-5.10-*) GKI_VER="gki-android12-5.10" ;;
  android13-5.10-*) GKI_VER="gki-android13-5.10" ;;
  android13-5.15-*) GKI_VER="gki-android13-5.15" ;;
  android14-5.15-*) GKI_VER="gki-android14-5.15" ;;
  android14-6.1-*)  GKI_VER="gki-android14-6.1" ;;
  android15-6.6-*)  GKI_VER="gki-android15-6.6" ;;
  android16-6.12-*) GKI_VER="gki-android16-6.12" ;;
  *)
    echo "setup-susfs: no upstream branch for '$OUR_BRANCH' (6.18+); skipping, KSU-only build"
    exit 0 ;;
esac

# KSU side must already carry SUSFS hooks (dev-susfs / next-susfs). A plain
# KSU build has no KSU_SUSFS symbol, so fail fast with the fix instead of
# shipping a kernel where the fragment enables nothing.
if ! grep -q "KSU_SUSFS" common/drivers/kernelsu/Kconfig 2>/dev/null; then
  echo "setup-susfs: KSU driver lacks SUSFS hooks; dispatch with ksu_ref 'dev-susfs' (KSU side)" >&2
  exit 2
fi

NAME="susfs4ksu"
if [ ! -d "$NAME" ]; then
  git clone "https://gitlab.com/${REPO}.git" "$NAME"
fi
git -C "$NAME" fetch origin "$GKI_VER" 2>/dev/null || \
  git -C "$NAME" fetch origin 2>/dev/null || true
if [ -n "$REF" ]; then
  git -C "$NAME" checkout -q "$REF" || \
    { echo "setup-susfs: cannot checkout ref '$REF'" >&2; exit 2; }
else
  git -C "$NAME" checkout -q "origin/$GKI_VER" 2>/dev/null || \
  git -C "$NAME" checkout -q "$GKI_VER" || \
    { echo "setup-susfs: cannot checkout branch '$GKI_VER'" >&2; exit 2; }
fi
SUSFS_SHA=$(git -C "$NAME" rev-parse --short HEAD)
echo "setup-susfs: source at $SUSFS_SHA ($GKI_VER)"

# Idempotent: file copies + git apply are re-runnable; skip the patch when
# its content is already in the tree (fresh runners never hit this).
cp -v "$NAME/kernel_patches/fs/susfs.c" common/fs/susfs.c
cp -v "$NAME/kernel_patches/include/linux/susfs.h" common/include/linux/susfs.h
cp -v "$NAME/kernel_patches/include/linux/susfs_def.h" common/include/linux/susfs_def.h
PATCH="$NAME/kernel_patches/50_add_susfs_in_${GKI_VER}.patch"
[ -f "$PATCH" ] || { echo "setup-susfs: missing $PATCH" >&2; exit 2; }
if git -C common apply --check -p1 "../$PATCH" 2>/dev/null; then
  git -C common apply -p1 "../$PATCH"
  echo "setup-susfs: applied 50_add_susfs_in_${GKI_VER}.patch"
elif [ -f common/fs/susfs.c ] && grep -q "susfs" common/fs/Makefile; then
  echo "setup-susfs: patch already applied, skipping"
else
  echo "setup-susfs: patch does not apply cleanly and tree looks unpatched" >&2
  git -C common apply --check -p1 "../$PATCH" || true
  exit 2
fi
printf '%s %s\n' "$GKI_VER" "$SUSFS_SHA" > .susfs-version

mkdir -p .fragments
cat > .fragments/susfs.config <<'EOF'
# SuSFS root hiding (written by setup-susfs.sh; only exists when the susfs
# step ran, so patched source and symbol always agree). KSU side hooks come
# from KernelSU-Next@dev-susfs; sub-options keep upstream defaults.
CONFIG_KSU_SUSFS=y
EOF
echo "setup-susfs: kernel patched, fragment written"
