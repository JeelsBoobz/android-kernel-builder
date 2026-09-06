#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# check-added-symbols.sh - added-symbol resolution gate for kernel merges.
#
# Lesson encoded: git merges text, not semantics. A clean merge can combine
# individually-consistent sides into an incoherent tree (observed: stable's
# timer_delete*/timer_shutdown* uses merged onto an LTS that reverted those
# very renames -- full-size files, zero markers, broken compile). Marker and
# size gates cannot see this class; only use<->declaration consistency can.
#
#   check-added-symbols.sh --repo <dir> --base <sha> [--head <sha>]
#     [--allowlist <file>]
#
# For every C function call the merge ADDED (base...head, .c/.h lines starting
# with +), resolve the symbol or fail closed:
#   pass: declared/defined in a header (single prebuilt index), or defined
#     in-tree (.c definition index), or defined+used in the same file, or in
#     the allowlist (asm/linker magic with no C declaration).
#   skip: C keywords, definition-shaped lines (defs need no decls).
# Exit 0 = all resolve. Exit 1 = unresolved symbols listed file:line:symbol
# (wire to quarantine, never to silent promotion).
set -euo pipefail

REPO=""; BASE=""; HEAD="HEAD"; ALLOW=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --base) BASE="$2"; shift 2 ;;
    --head) HEAD="$2"; shift 2 ;;
    --allowlist) ALLOW="$2"; shift 2 ;;
    *) echo "check-added-symbols: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$REPO" ] && [ -n "$BASE" ] || { echo "check-added-symbols: need --repo and --base" >&2; exit 2; }
log() { echo "check-added-symbols: $*" >&2; }

cd "$REPO"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Added C lines introduced by the merge (base...head, + lines, .c/.h only).
git diff "$BASE" "$HEAD" -- '*.c' '*.h' | grep -E '^\+\+\+ ' | sed 's|^\+\+\+ b/||' > "$TMP/files.txt" || true
git diff "$BASE" "$HEAD" -- '*.c' '*.h' | grep -E '^\+[^+]' | sed 's/^+//' > "$TMP/added.txt" || true
log "$(wc -l < "$TMP/added.txt") added C lines"

# Prebuilt indexes, one sweep each (keeps per-symbol checks instant).
# decls: names followed by ( in headers (prototypes, static inlines, macros).
grep -rh --include='*.h' -o -E '[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(' . 2>/dev/null \
  | tr -d ' \t(' | sort -u > "$TMP/decls.txt" || true
# defs: definition-shaped beginnings in .c files (type ... name (), no trailing ;).
grep -rh --include='*.c' -E -o '^[[:space:]]*(static[[:space:]]+)?(struct[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]\*]*|union[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]\*]*|enum[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*|void|int|long|char|short|bool|u8|u16|u32|u64|s8|s16|s32|s64|size_t|ssize_t|unsigned|const)[[:space:]][a-zA-Z0-9_[:space:]\*]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(' . 2>/dev/null \
  | grep -o -E '[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\($' | tr -d ' \t(' | sort -u > "$TMP/defs.txt" || true
cat "$TMP/decls.txt" "$TMP/defs.txt" | sort -u > "$TMP/index.txt"
log "index: $(wc -l < "$TMP/index.txt") declared/defined names"

# Candidate calls per added line, with originating file:line. Needs the diff
# with file context: re-walk per file.
: > "$TMP/cands.txt"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  git diff "$BASE" "$HEAD" -- "$f" | grep -E '^\+[^+]' | sed 's/^+//' | cat -n \
  | while IFS= read -r ln; do
      n="${ln%%$'\t'*}"; line="${ln#*$'\t'}"
      # definition-shaped lines:defs need no decls, but a one-line body
      # after { can still hide calls -- scan only past the first brace.
      code="$line"
      if printf '%s' "$line" | grep -qE '^[[:space:]]*(static[[:space:]]+)?(struct[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]*]*|union[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]*]*|enum[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*|void|int|long|char|short|bool|u8|u16|u32|u64|s8|s16|s32|s64|size_t|ssize_t|unsigned|const)([[:space:]*]|$)|^[[:space:]]*#'; then
        case "$line" in *'{'*) code="${line#*\{}";; *) continue;; esac
      fi
      for sym in $(printf '%s' "$code" | grep -o -E '[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(' | tr -d ' \t(' || true); do
        case "$sym" in
          if|for|while|switch|return|sizeof|typeof|alignof|_Static_assert) continue ;;
        esac
        printf '%s\t%s\t%s\n' "$f" "$n" "$sym" >> "$TMP/cands.txt"
      done
    done
done < "$TMP/files.txt"
log "$(wc -l < "$TMP/cands.txt") candidate call sites"

FAIL=0
while IFS=$'\t' read -r f n sym; do
  [ -n "$f" ] || continue
  if grep -qxF "$sym" "$TMP/index.txt" 2>/dev/null; then continue; fi
  # same-file def+use (static helpers): 2+ occurrences of name( in the file
  if [ "$(git cat-file -p "$HEAD:$f" 2>/dev/null | grep -c -E "(^|[^a-zA-Z0-9_>])$sym[[:space:]]*\\(" || true)" -ge 2 ]; then continue; fi
  if [ -n "$ALLOW" ] && [ -f "$ALLOW" ] && grep -qxF "$sym" "$ALLOW" 2>/dev/null; then continue; fi
  echo "UNRESOLVED $f:$n: $sym"
  FAIL=1
done < <(sort -u "$TMP/cands.txt")
if [ "$FAIL" -ne 0 ]; then log "FAIL: added calls without in-tree declaration (see UNRESOLVED above)"; exit 1; fi
log "OK: all merge-added calls resolve"
