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
# No upstream branch exists for 6.18 -> KSU-only build with a suppression
# fragment (KSU_SUSFS defaults y on dev-susfs; must be forced off or the
# driver includes missing headers). Writes .fragments/susfs.config for
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

# KSU-only fallback: force the whole KSU_SUSFS family off. Load-bearing,
# not cosmetic -- dev-susfs's KSU_SUSFS defaults to y, and with =y the
# driver #includes <linux/susfs*.h>, which do not exist without the
# kernel-side patch. Forcing off keeps the driver on its plain-dev code
# paths (all susfs refs are #ifdef-guarded).
write_suppression() { # $1 reason
  mkdir -p .fragments
  cat > .fragments/susfs.config <<'EOF'
# No SuSFS on this tree: force the whole KSU_SUSFS family off so dev-susfs
# builds its plain-dev paths.
# CONFIG_KSU_SUSFS is not set
EOF
  echo "setup-susfs: $1; wrote KSU_SUSFS suppression, KSU-only build"
}

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
    # No upstream branch for 6.18+: KSU-only build (suppression written
    # below; see write_suppression rationale).
    write_suppression "no upstream branch for '$OUR_BRANCH' (6.18+)"
    exit 0 ;;
esac

# 6.6-only suppression: simonpunk's 6.6 patch needs the new SELinux API and
# targets newer 6.6 than any published GKI (latest android15-6.6 = pre-API),
# with no green precedent anywhere (WK ships 6.6 susfs-free too). 6.12 goes
# through the normal path below: its patch's with_policy calls resolve via
# the KSU driver's global definitions (see the linkage port in
# setup-kernelsu-next.sh), so no tree API is required. Re-enable 6.6 when a
# green precedent exists.
case "$GKI_VER" in
  gki-android15-6.6)
    write_suppression "6.6 patch needs newer SELinux API than published GKI provides; gated pending green precedent"
    exit 0 ;;
esac

# KSU side with SUSFS hooks (dev-susfs / next-susfs) gets the kernel patch.
# A plain KSU build (e.g. 6.18 pinned to dev via a ksu_ref branch:ref map)
# has no KSU_SUSFS symbol at all -- clean skip with NO fragment, since even
# a suppression would reference a symbol that does not exist there.
if ! grep -q "KSU_SUSFS" common/drivers/kernelsu/Kconfig 2>/dev/null; then
  echo "setup-susfs: KSU driver has no SUSFS hooks (plain ref); skipping, KSU-only build"
  exit 0
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

# Idempotent: file copies + patch are re-runnable; skip the patch when
# its content is already in the tree (fresh runners never hit this).
cp -v "$NAME/kernel_patches/fs/susfs.c" common/fs/susfs.c
cp -v "$NAME/kernel_patches/include/linux/susfs.h" common/include/linux/susfs.h
cp -v "$NAME/kernel_patches/include/linux/susfs_def.h" common/include/linux/susfs_def.h
PATCH="$NAME/kernel_patches/50_add_susfs_in_${GKI_VER}.patch"
[ -f "$PATCH" ] || { echo "setup-susfs: missing $PATCH" >&2; exit 2; }
if grep -q "susfs_is_current_ksu_domain" common/fs/namespace.c 2>/dev/null; then
  echo "setup-susfs: patch already applied, skipping"
else
  # Drift fakes, method: WildKernels susfs-patches action (sublevel-gated
  # sed pre-edits so the 50_ context matches, then GNU patch which tolerates
  # residual offsets via fuzz). simonpunk's patch base is NEWER GKI than our
  # -lts tips (e.g. ours still carry trace/hooks/blk.h which the patch
  # context lacks), so without these the hunk fails (namespace.c:32).
  # Dropped includes are restored post-patch (restore_include below) -- the
  # patch must not see them, but the compiler must.
  SUBLEVEL=$(grep -E "^SUBLEVEL" common/Makefile | awk '{print $3}')
  echo "setup-susfs: sublevel $SUBLEVEL, applying drift fakes for $GKI_VER"
  (
  cd common
  case "$GKI_VER" in
    gki-android12-5.10)
      [ "$SUBLEVEL" -le 43 ] && perl -i -pe 's/(int|size_t)\s+this_len\s*=\s*min_t\s*\(\s*\1\s*,/size_t this_len = min_t(size_t,/' fs/proc/base.c || true
      if [ "$SUBLEVEL" -le 117 ]; then
        perl -0777 -i -pe 's{(if \(inode\) \{\n)\t\t/\*\n(\t\t \*[^\n]*\n)+\t\t \*/\n}{$1}g; s{^[[:space:]]*u32 mask = mark->mask & IN_ALL_EVENTS;\n}{}m' fs/notify/fdinfo.c
        perl -i -pe 's/\bmask,\s*mark->ignored_mask/inotify_mark_user_mask(mark)/g' fs/notify/fdinfo.c
        perl -i -pe 's/ignored_mask:%x/ignored_mask:0/g' fs/notify/fdinfo.c
        python3 -c 'import re;c=open("fs/notify/fdinfo.c").read();c=re.sub(r"^static void inotify_fdinfo\(struct seq_file \*m, struct fsnotify_mark \*mark\)$",lambda m:"static inline u32 inotify_mark_user_mask(struct fsnotify_mark *mark)\n{\n\treturn mark->mask & IN_ALL_EVENTS;\n}\n\n"+m.group(0),c,count=1,flags=re.MULTILINE);open("fs/notify/fdinfo.c","w").write(c)'
      fi ;;
    gki-android13-5.10)
      if [ "$SUBLEVEL" -le 107 ]; then
        perl -0777 -i -pe 's{(if \(inode\) \{\n)\t\t/\*\n(\t\t \*[^\n]*\n)+\t\t \*/\n}{$1}g; s{^[[:space:]]*u32 mask = mark->mask & IN_ALL_EVENTS;\n}{}m' fs/notify/fdinfo.c
        perl -i -pe 's/\bmask,\s*mark->ignored_mask/inotify_mark_user_mask(mark)/g' fs/notify/fdinfo.c
        perl -i -pe 's/ignored_mask:%x/ignored_mask:0/g' fs/notify/fdinfo.c
        python3 -c 'import re;c=open("fs/notify/fdinfo.c").read();c=re.sub(r"^static void inotify_fdinfo\(struct seq_file \*m, struct fsnotify_mark \*mark\)$",lambda m:"static inline u32 inotify_mark_user_mask(struct fsnotify_mark *mark)\n{\n\treturn mark->mask & IN_ALL_EVENTS;\n}\n\n"+m.group(0),c,count=1,flags=re.MULTILINE);open("fs/notify/fdinfo.c","w").write(c)'
      fi ;;
    gki-android13-5.15|gki-android14-5.15)
      if [ "$SUBLEVEL" -le 41 ]; then
        sed -i '/^#include <linux\/shmem_fs.h>$/a #include <linux/mnt_idmapping.h>' fs/namespace.c
        sed -i '/^#include <linux\/compat.h>$/a #include <linux/mnt_idmapping.h>' fs/open.c
        perl -0777 -i -pe 's{(if \(inode\) \{\n)\t\t/\*\n(\t\t \*[^\n]*\n)+\t\t \*/\n}{$1}g; s{^[[:space:]]*u32 mask = mark->mask & IN_ALL_EVENTS;\n}{}m' fs/notify/fdinfo.c
        perl -i -pe 's/\bmask,\s*mark->ignored_mask/inotify_mark_user_mask(mark)/g' fs/notify/fdinfo.c
        perl -i -pe 's/ignored_mask:%x/ignored_mask:0/g' fs/notify/fdinfo.c
        python3 -c 'import re;c=open("fs/notify/fdinfo.c").read();c=re.sub(r"^static void inotify_fdinfo\(struct seq_file \*m, struct fsnotify_mark \*mark\)$",lambda m:"static inline u32 inotify_mark_user_mask(struct fsnotify_mark *mark)\n{\n\treturn mark->mask & IN_ALL_EVENTS;\n}\n\n"+m.group(0),c,count=1,flags=re.MULTILINE);open("fs/notify/fdinfo.c","w").write(c)'
      fi
      [ "$SUBLEVEL" -ge 197 ] && sed -i '/^#include <trace\/hooks\/blk.h>$/d' fs/namespace.c || true
      [ "$SUBLEVEL" -ge 197 ] && sed -i '/^#include <trace\/hooks\/mm.h>$/d' fs/proc/task_mmu.c || true ;;
    gki-android14-6.1)
      [ "$SUBLEVEL" -le 25 ] && sed -i '/^#include <trace\/events\/oom.h>$/a #include <trace/hooks/sched.h>' fs/proc/base.c || true
      [ "$SUBLEVEL" -le 141 ] && sed -i '/^#include <linux\/cpufreq_times.h>$/a #include <linux/dma-buf.h>' fs/proc/base.c || true
      [ "$SUBLEVEL" -ge 157 ] && sed -i '/^#include <trace\/hooks\/blk.h>$/d' fs/namespace.c || true ;;
    gki-android15-6.6)
      # NOTE: the __fold_filemap_fixup_entry stub (WK, sub<=30 + SPL 2024-07)
      # is intentionally not ported: unreachable on our trees (6.6-lts >> 30).
      [ "$SUBLEVEL" -le 92 ] && sed -i '/^#include <linux\/cpufreq_times.h>$/a #include <linux/dma-buf.h>' fs/proc/base.c || true
      [ "$SUBLEVEL" -le 57 ] && sed -i '/^#include <linux\/sched\/sysctl.h>$/a #include <linux/zswap.h>' mm/memory.c || true ;;
    gki-android16-6.12)
      [ "$SUBLEVEL" -ge 58 ] && sed -i '/^#include <linux\/dma-buf.h>$/d' fs/exec.c || true
      [ "$SUBLEVEL" -ge 69 ] && sed -i 's/vma_data_pages/vma_pages/g' fs/proc/task_mmu.c || true ;;
  esac
  )
  patch -p1 --fuzz=3 --directory=common < "$PATCH"
  # Restore vendor-hook includes the drift fakes dropped above. simonpunk's
  # base is newer GKI where Google removed these lines, but our -lts tips
  # still carry AND need them: trace/hooks/blk.h declares
  # trace_android_vh_do_new_mount_fc (namespace.c fails without it), and
  # linux/dma-buf.h declares susfs's exec helpers. Re-add is idempotent
  # (grep-guarded) and skipped if the header itself is gone in-tree.
  restore_include() { # $1 file $2 anchor-line $3 include-line $4 header-path
    grep -qF "$3" "common/$1" 2>/dev/null && return 0
    if [ ! -f "common/$4" ]; then
      echo "setup-susfs: WARN header gone in-tree, skip restore: $4" >&2; return 0
    fi
    # Line-number addressing (single address: valid for `a`) + fixed-string
    # anchor match (no regex metachar pitfalls, first match only).
    n=$(grep -n -m1 -F -e "$2" "common/$1" | cut -d: -f1)
    if [ -z "$n" ]; then
      echo "setup-susfs: WARN anchor gone, skip restore: $2 in $1" >&2; return 0
    fi
    sed -i "${n}a $3" "common/$1"
  }
  case "$GKI_VER" in
    gki-android13-5.15|gki-android14-5.15)
      restore_include fs/namespace.c '#include "internal.h"' '#include <trace/hooks/blk.h>' include/trace/hooks/blk.h
      restore_include fs/proc/task_mmu.c '#include <linux/pkeys.h>' '#include <trace/hooks/mm.h>' include/trace/hooks/mm.h ;;
    gki-android14-6.1)
      restore_include fs/namespace.c '#include "internal.h"' '#include <trace/hooks/blk.h>' include/trace/hooks/blk.h ;;
    gki-android16-6.12)
      restore_include fs/exec.c '#include <linux/ksm.h>' '#include <linux/dma-buf.h>' include/linux/dma-buf.h ;;
  esac
  # Fail closed: GNU patch tolerates drift, so verify it did not half-apply.
  if find common/fs common/mm common/kernel common/drivers common/security common/include -name '*.rej' 2>/dev/null | grep -q .; then
    echo "setup-susfs: patch left .rej files:" >&2
    find common/fs common/mm common/kernel common/drivers common/security common/include -name '*.rej' >&2
    exit 2
  fi
  # Per-file marker check: every file the 50_ patch touches must contain a
  # susfs token afterwards (verified: true for all 23/24 files on every
  # simonpunk per-version branch). Catches fuzz misplaces and half-applies
  # that exit 0 with no .rej. File list derived from the patch itself, so
  # 6.6/6.12's extra selinux file is covered without hardcoding.
  MISSING=""
  while IFS= read -r f; do
    grep -qi "susfs" "common/$f" 2>/dev/null || MISSING="$MISSING $f"
  done < <(grep -E '^diff --git ' "$PATCH" | awk '{print $4}' | sed 's|^b/||')
  if [ -n "$MISSING" ]; then
    echo "setup-susfs: post-patch marker check FAILED, no susfs token in:$MISSING" >&2
    exit 2
  fi
  echo "setup-susfs: applied 50_add_susfs_in_${GKI_VER}.patch (all file markers present)"
fi
printf '%s %s %s\n' "$GKI_VER" "$SUSFS_SHA" "${REF:-}" > .susfs-version

mkdir -p .fragments
cat > .fragments/susfs.config <<'EOF'
# SuSFS root hiding (written by setup-susfs.sh; only exists when the susfs
# step ran, so patched source and symbol always agree). KSU side hooks come
# from KernelSU-Next@dev-susfs. All sub-features explicitly on (upstream
# defaults are y, none deprecated; explicit so a future default flip cannot
# silently neuter hiding).
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
EOF
echo "setup-susfs: kernel patched, fragment written"
