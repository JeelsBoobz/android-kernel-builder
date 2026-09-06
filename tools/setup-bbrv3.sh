#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# setup-bbrv3.sh - integrate WildKernels BBRv3 TCP backports.
#
# Run with cwd = repo-sync root (the dir containing common/):
#   setup-bbrv3.sh --our-branch android14-6.1-stable [--ref <commit>]
#
# BBRv3 is a separate congestion algorithm (new tcp_bbr3.c + tcp_plb.c;
# BBRv1 untouched), dormant until selected (default CC stays CUBIC), so
# this is the safest source-patch class we carry. Still default-off,
# version-gated, fail-closed like the rest.
#
# Patch sources: vendored in patches/bbrv3/ (see NOTICE: GPL-2.0-only
# third-party diffs, pinned by our own commits -- no clone, no network at
# build time). Filenames mirror upstream (method: WildKernels bbrv3 action).
#   5.10 sysctl pair + 5.15<=43 cwnd helper - applied conditionally exactly
#     like upstream (grep/sublevel gates); no-ops on our tips, kept for
#     fidelity. 6.12/6.18 have no proven patch (WK ships 6.12 disabled) and
#   clean-skip with NO fragment.
# Writes .fragments/bbrv3.config (CONFIG_TCP_CONG_BBR3=y) for
# apply-fragments.sh (kept out of fragments/ on purpose: the symbol must
# never be enabled without the patched source present).
set -euo pipefail

PATCH_DIR=""; OUR_BRANCH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --patch-dir) PATCH_DIR="$2"; shift 2 ;;
    --our-branch) OUR_BRANCH="$2"; shift 2 ;;
    *) echo "setup-bbrv3: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$PATCH_DIR" ] || { echo "setup-bbrv3: missing --patch-dir" >&2; exit 2; }
[ -d "$PATCH_DIR" ] || { echo "setup-bbrv3: no such patch dir: $PATCH_DIR" >&2; exit 2; }

# Our -stable branch -> vendored backport file. -lts accepted the same way.
case "$OUR_BRANCH" in
  android12-5.10-*|android13-5.10-*)
    PATCH="0001-net-tcp-backport-BBRv3-to-android12-5.10.patch" ;;
  android13-5.15-*) PATCH="0001-net-tcp-backport-BBRv3-to-android13-5.15.patch" ;;
  android14-5.15-*) PATCH="0001-net-tcp-backport-BBRv3-to-android14-5.15.patch" ;;
  android14-6.1-*)  PATCH="0001-net-tcp-backport-BBRv3-to-android14-6.1.patch" ;;
  android15-6.6-*)  PATCH="0001-net-tcp-backport-BBRv3-to-android15-6.6.patch" ;;
  *)
    echo "setup-bbrv3: no proven backport for '$OUR_BRANCH' (6.12+/unknown); skipping, no fragment"
    exit 0 ;;
esac

PATCH_FILE="$PATCH_DIR/$PATCH"
[ -f "$PATCH_FILE" ] || { echo "setup-bbrv3: missing $PATCH_FILE" >&2; exit 2; }

SUBLEVEL=$(grep -E "^SUBLEVEL" common/Makefile | awk '{print $3}')
echo "setup-bbrv3: sublevel $SUBLEVEL, vendored $PATCH"

patch -p1 --fuzz=3 --directory=common < "$PATCH_FILE"

# 5.10 sysctl prerequisites (upstream Eric Dumazet pair), exactly as WK
# gates them: only when the tree lacks proc_dou8vec_minmax.
case "$OUR_BRANCH" in
  android12-5.10-*|android13-5.10-*)
    if ! grep -qF 'int proc_dou8vec_minmax(' common/include/linux/sysctl.h 2>/dev/null; then
      for sp in sysctl_add_proc_dou8vec_minmax.patch sysctl_fix_data-races_in_proc_dou8vec_minmax.patch; do
        patch -p1 --fuzz=3 --directory=common < "$PATCH_DIR/$sp" || \
          { echo "setup-bbrv3: sysctl patch failed: $sp" >&2; exit 2; }
      done
      echo "setup-bbrv3: applied sysctl prerequisites"
    else
      echo "setup-bbrv3: tree has proc_dou8vec_minmax, sysctl prerequisites skipped"
    fi ;;
esac
# 5.15<=43 cwnd helpers (WK gate; never fires on our tips, kept verbatim).
case "$OUR_BRANCH" in
  android13-5.15-*|android14-5.15-*)
    if [ "$SUBLEVEL" -le 43 ]; then
      patch -p1 --fuzz=3 --directory=common \
        < "$PATCH_DIR/0002-net-tcp-add-tcp_snd_cwnd-and-tcp_snd_cwnd_set-helper-functions.patch" || \
        { echo "setup-bbrv3: 0002 helper failed" >&2; exit 2; }
    fi ;;
esac

# Fail closed: no .rej, and the three load-bearing markers per tree.
if find common/net common/include -name '*.rej' 2>/dev/null | grep -q .; then
  echo "setup-bbrv3: patch left .rej files:" >&2
  find common/net common/include -name '*.rej' >&2
  exit 2
fi
[ -f common/net/ipv4/tcp_bbr3.c ] || { echo "setup-bbrv3: marker FAILED (tcp_bbr3.c)" >&2; exit 2; }
grep -q "config TCP_CONG_BBR3" common/net/ipv4/Kconfig || { echo "setup-bbrv3: marker FAILED (Kconfig)" >&2; exit 2; }
grep -q "tcp_bbr3.o" common/net/ipv4/Makefile || { echo "setup-bbrv3: marker FAILED (Makefile)" >&2; exit 2; }
printf '%s\n' "$PATCH" > .bbrv3-version
echo "setup-bbrv3: backport applied, markers present"

mkdir -p .fragments
cat > .fragments/bbrv3.config <<'EOF'
# BBRv3 congestion control (written by setup-bbrv3.sh; only exists when the
# backport step ran, so patched source and symbol always agree). Separate
# algorithm alongside BBRv1 (untouched); default CC stays CUBIC; dormant
# until selected per-connection.
CONFIG_TCP_CONG_BBR3=y
EOF
echo "setup-bbrv3: fragment written"
