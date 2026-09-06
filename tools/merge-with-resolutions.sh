#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# merge-with-resolutions.sh - deterministic human-recorded merge driver.
#
# Reusable end to end: full-history fetch, merge, recorded resolutions,
# static gates, push. New branch = new resolutions file + manual dir,
# same script ("on and on").
#
#   merge-with-resolutions.sh --upstream-url <url> --stable-url <url>
#     --dest <plain-https-repo-url> --lts <branch> --stable <branch>
#     --out <branch> --review <branch>
#     --resolutions <file> --manual-dir <dir>
#     [--promote] [--workdir <dir>]
#
# Auth: DEST_TOKEN env (never embedded in the remote URL, so it cannot
# leak via push output; sent only as an http extraheader).
#
# Resolutions file: lines "<path> = ours|theirs|manual" (# comments,
# blanks ignored). "ours"/"theirs" check out that side whole (verified
# byte-identical to the side tip afterwards). "manual" splices hunk
# replacements: <manual-dir>/<path> holds one replacement block per
# conflict hunk, in order, separated by a line "@@RESOLVED-HUNK@@"
# (empty block = delete both sides). Splicing (not whole-file copy) keeps
# git's own auto-merge for everything outside the hunks.
# Makefile takes --theirs (stable-only version bump, same as merge-stable).
#
# Exit 0 = gates passed, review pushed (stable pushed too iff --promote).
# Exit 1 = unresolvable (conflict without a recorded resolution, or gate
# failure); reason printed, nothing pushed. Exit 2 = usage/tooling error.
# Resulting SHA printed on stdout as "RESULT_SHA=<sha>" (logs on stderr).
set -euo pipefail

UPSTREAM_URL=""; STABLE_URL=""; DEST=""
LTS=""; STABLE=""; OUT=""; REVIEW=""
RESOL=""; MANDIR=""; PROMOTE="false"; WORKDIR="work-promote"
while [ $# -gt 0 ]; do
  case "$1" in
    --upstream-url) UPSTREAM_URL="$2"; shift 2 ;;
    --stable-url) STABLE_URL="$2"; shift 2 ;;
    --dest) DEST="$2"; shift 2 ;;
    --lts) LTS="$2"; shift 2 ;;
    --stable) STABLE="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --review) REVIEW="$2"; shift 2 ;;
    --resolutions) RESOL="$2"; shift 2 ;;
    --manual-dir) MANDIR="$2"; shift 2 ;;
    --promote) PROMOTE="true"; shift ;;
    --workdir) WORKDIR="$2"; shift 2 ;;
    *) echo "merge-with-resolutions: unknown arg: $1" >&2; exit 2 ;;
  esac
done
for v in UPSTREAM_URL STABLE_URL DEST LTS STABLE OUT REVIEW RESOL MANDIR; do
  [ -n "${!v}" ] || { echo "merge-with-resolutions: missing --$(echo "$v" | tr 'A-Z_' 'a-z-')" >&2; exit 2; }
done
[ -f "$RESOL" ] || { echo "merge-with-resolutions: no resolutions file: $RESOL" >&2; exit 2; }
[ -d "$MANDIR" ] || { echo "merge-with-resolutions: no manual dir: $MANDIR" >&2; exit 2; }
log() { echo "merge-with-resolutions: $*" >&2; }

rm -rf "$WORKDIR" && mkdir -p "$WORKDIR" && cd "$WORKDIR"
git init -q
git remote add upstream "$UPSTREAM_URL"
git remote add stable "$STABLE_URL"
git remote add dest "$DEST"

# Full history (merge-base needs it; shallow cannot merge).
git fetch --no-tags upstream "refs/heads/$LTS:refs/remotes/upstream/$LTS"
git fetch --no-tags stable "refs/heads/$STABLE:refs/remotes/stable/$STABLE"
LTS_TIP=$(git rev-parse "refs/remotes/upstream/$LTS")
STABLE_TIP=$(git rev-parse "refs/remotes/stable/$STABLE")
log "LTS $LTS=$LTS_TIP stable $STABLE=$STABLE_TIP"

OLD=""; OLD_REVIEW=""
git fetch dest "refs/heads/$OUT:refs/remotes/dest/$OUT" 2>/dev/null && OLD=$(git rev-parse "refs/remotes/dest/$OUT") || true
git fetch dest "refs/heads/$REVIEW:refs/remotes/dest/$REVIEW" 2>/dev/null && OLD_REVIEW=$(git rev-parse "refs/remotes/dest/$REVIEW") || true

# NO-OP: OUT already contains both inputs.
if [ -n "$OLD" ] && git merge-base --is-ancestor "$LTS_TIP" "$OLD" 2>/dev/null \
    && git merge-base --is-ancestor "$STABLE_TIP" "$OLD" 2>/dev/null; then
  log "$OUT ($OLD) already contains both tips; nothing to do"
  echo "RESULT_SHA=$OLD"
  exit 0
fi

push_ref() { # $1 sha $2 ref $3 old-or-empty
  local sha=$1 ref=$2 old=$3 lease auth
  if [ -z "${DEST_TOKEN:-}" ]; then log "FAIL: DEST_TOKEN unset (push needs it)"; exit 2; fi
  if [ -n "$old" ]; then lease="--force-with-lease=refs/heads/$ref:$old"
  else lease="--force-with-lease=refs/heads/$ref:"; fi
  auth=$(printf 'x-access-token:%s' "$DEST_TOKEN" | base64 -w0)
  # shellcheck disable=SC2086
  git -c "http.https://github.com/.extraheader=AUTHORIZATION: basic $auth" \
    push $lease dest "$sha:refs/heads/$ref"
}

GITID=(-c user.name=kernel-mirror -c user.email=kernel-mirror@users.noreply.github.com)
git "${GITID[@]}" checkout -q "$LTS_TIP"
if git "${GITID[@]}" merge --no-ff --no-edit \
    -m "Merge $STABLE ($STABLE_TIP) into $LTS ($LTS_TIP)" "$STABLE_TIP" 2>/dev/null; then
  log "merged clean (no resolutions needed)"
else
  log "conflicts; applying recorded resolutions from $RESOL"
  git diff --name-only --diff-filter=U > /tmp/mwr_conflicted.txt
  # Deterministic pre-pass: root Makefile version bump takes stable side.
  if grep -qx "Makefile" /tmp/mwr_conflicted.txt 2>/dev/null; then
    log "pre-pass: Makefile takes --theirs"
    git checkout --theirs -- Makefile
    git add Makefile
  fi
  # Validate resolutions file modes up front (paths checked per file below).
  if grep -vE '^[[:space:]]*(#|$)' "$RESOL" | grep -vE '=[[:space:]]*(ours|theirs|manual)[[:space:]]*(#|$)' | grep -q .; then
    log "bad resolution lines:"; grep -vE '^[[:space:]]*(#|$)' "$RESOL" | grep -vE '=[[:space:]]*(ours|theirs|manual)[[:space:]]*(#|$)'; exit 2
  fi
  lookup() { # $1 file -> mode (last match wins) or empty
    awk -F= -v f="$1" '{sub(/#.*/,""); if (NF>=2) {g=$1; gsub(/[[:space:]]/,"",g); if (g==f) {m=$2; gsub(/[[:space:]]/,"",m); print m}}}' "$RESOL" | tail -1
  }
  UNLISTED=""
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ "$f" = "Makefile" ] && continue
    mode=$(lookup "$f")
    if [ -z "$mode" ]; then UNLISTED="$UNLISTED $f"; continue; fi
    case "$mode" in
      ours)
        git checkout --ours -- "$f"
        git diff --quiet "$LTS_TIP" -- "$f" || { log "FAIL: $f ours-checkout != LTS tip"; exit 1; } ;;
      theirs)
        git checkout --theirs -- "$f"
        git diff --quiet "$STABLE_TIP" -- "$f" || { log "FAIL: $f theirs-checkout != stable tip"; exit 1; } ;;
      manual)
        [ -f "$MANDIR/$f" ] || { log "manual resolution missing content: $MANDIR/$f"; exit 2; }
        python3 - "$f" "$MANDIR/$f" <<'PYEOF' || exit 2
import sys
work, man = sys.argv[1], sys.argv[2]
lines = open(work).read().splitlines()
blocks = open(man).read().split("@@RESOLVED-HUNK@@")
reps = [b.strip("\n") for b in blocks]
# split work file into text/conflict segments (default merge style:
# <<<<<<< ... ======= ... >>>>>>>, no base block)
out, i, nconf = [], 0, 0
while i < len(lines):
    if lines[i].startswith("<<<<<<<"):
        j = next(k for k in range(i, len(lines)) if lines[k].startswith(">>>>>>>"))
        nconf += 1
        if nconf > len(reps):
            print(f"manual {man}: more conflict hunks than replacement blocks", file=sys.stderr); sys.exit(2)
        rep = reps[nconf - 1]
        if rep: out.extend(rep.splitlines())
        i = j + 1
    else:
        out.append(lines[i]); i += 1
if nconf != len(reps):
    print(f"manual {man}: {nconf} hunks vs {len(reps)} replacement blocks", file=sys.stderr); sys.exit(2)
open(work, "w").write("\n".join(out) + "\n")
PYEOF
        ;;
    esac
    git add -- "$f"
    log "resolved $f <- $mode"
  done < /tmp/mwr_conflicted.txt
  if [ -n "$UNLISTED" ]; then
    log "FAIL: conflicts without recorded resolution:$UNLISTED"
    log "add '<path> = ours|theirs|manual' lines to $RESOL and re-run"
    exit 1
  fi
  # Gates (deterministic subset of audit-stable-review; the human IS the
  # reviewer here, so no AI confirm and no Android-surface rule — that rule
  # exists to keep AI away from binder, and this path is human-resolved).
  if git diff --name-only --diff-filter=U | grep -q .; then
    log "FAIL: unmerged paths remain"; git diff --name-only --diff-filter=U >&2; exit 1
  fi
  if grep -rIn --exclude-dir=.git -E '^(<{7}|={7}|>{7}|\.\.\.\[truncated\]\.\.\.)' . 2>/dev/null | grep -q .; then
    log "FAIL: markers escaped"; grep -rIn --exclude-dir=.git -E '^(<{7}|={7}|>{7}|\.\.\.\[truncated\]\.\.\.)' . >&2 | head; exit 1
  fi
  git add -A
  git diff --cached --check || { log "FAIL: whitespace errors"; exit 1; }
  # Size floor per conflicted file: >=70% of max(LTS,stable) lines.
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    L=$(git cat-file -p "$LTS_TIP:$f" 2>/dev/null | wc -l); S=$(git cat-file -p "$STABLE_TIP:$f" 2>/dev/null | wc -l)
    R=$(git cat-file -p ":$f" 2>/dev/null | wc -l)
    M=$(( L > S ? L : S ))
    if [ "$M" -gt 0 ] && [ "$(( R * 10 ))" -lt "$(( M * 7 ))" ]; then
      log "FAIL: $f size collapse $R vs LTS $L / stable $S (<70%)"; exit 1
    fi
  done < /tmp/mwr_conflicted.txt
  # ABI tripwire: stable never touches android/abi_*.
  if git diff --cached --name-only | grep -q "^android/abi_"; then
    log "FAIL: android/abi_* changed"; exit 1
  fi
  git "${GITID[@]}" commit --no-edit
  # Provenance trailer (keeps the auto Conflicts: list audit parses).
  git "${GITID[@]}" commit --amend --no-edit -m "$(git log -1 --format=%B)" -m "Resolutions-from: $RESOL"
  log "resolved commit: $(git rev-parse HEAD)"
fi
MERGED=$(git rev-parse HEAD)
push_ref "$MERGED" "$REVIEW" "$OLD_REVIEW"
log "pushed $REVIEW=$MERGED"
if [ "$PROMOTE" = "true" ]; then
  push_ref "$MERGED" "$OUT" "$OLD"
  log "promoted $OUT=$MERGED"
fi
echo "RESULT_SHA=$MERGED"
