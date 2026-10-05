#!/usr/bin/env bash
# tests/lint/bash32.sh: static bash 3.2 check over every *.sh in the repo
# (CONTRACT 0.4 and 2.8, TEST_STRATEGY 4). The constructs live in
# bash32.patterns, so this script never matches itself (GAP-10).
# Whole-line comments and trailing " # ..." comments are not checked.
# Prints file:line: construct for each hit. The real 3.2 run is the macOS job.
set -u
here=$(cd "$(dirname "$0")" && pwd)
repo=${here%/tests/lint}
cr=$'\r' tab=$'\t'
pats="$here/bash32.patterns"
ok=0 no=0 files=0

names=() res=() allows=()
while IFS= read -r l || [ -n "$l" ]; do
  l=${l%"$cr"}
  case $l in ''|'#'*) continue ;; esac
  n=${l%%"$tab"*}; rest=${l#*"$tab"}
  re=${rest%%"$tab"*}; al=""
  [ "$re" != "$rest" ] && al=${rest#*"$tab"}
  names+=("$n"); res+=("$re"); allows+=("$al")
done < "$pats"
if [ "${#names[@]}" -lt 12 ]; then echo "FAIL ${0##*/} (pattern file unreadable: ${#names[@]} patterns)"; exit 1; fi

list="${TMPDIR:-/tmp}/bash32.$$"
trap 'rm -f "$list" "$list.c"' EXIT
find "$repo" -name '*.sh' -type f ! -path '*/.git/*' | LC_ALL=C sort > "$list"
while IFS= read -r f; do
  files=$(( files + 1 ))
  # strip CR, whole-line comments and trailing comments; keep line numbers
  n=0
  while IFS= read -r l || [ -n "$l" ]; do
    n=$(( n + 1 ))
    l=${l%"$cr"}
    case $l in [[:space:]]*'#'*|'#'*) t=${l#"${l%%[![:space:]]*}"}; case $t in '#'*) l="" ;; esac ;; esac
    case $l in *' #'*) l=${l%% #*} ;; esac
    printf '%s\t%s\n' "$n" "$l"
  done < "$f" > "$list.c"
  bad=0 i=0
  while [ $i -lt "${#names[@]}" ]; do
    hits=$(cut -f2- "$list.c" | LC_ALL=C grep -nE -- "${res[i]}")
    if [ -n "$hits" ]; then
      while IFS= read -r h; do
        ln=${h%%:*}; body=${h#*:}
        if [ -n "${allows[i]}" ] && printf '%s\n' "$body" | LC_ALL=C grep -qE -- "${allows[i]}"; then continue; fi
        echo "${f#"$repo"/}:$ln: ${names[i]}"; bad=1
      done <<< "$hits"
    fi
    i=$(( i + 1 ))
  done
  if [ $bad -eq 0 ]; then ok=$(( ok + 1 )); else no=$(( no + 1 )); fi
done < "$list"

if [ "$files" -eq 0 ]; then echo "FAIL ${0##*/} (no *.sh files found)"; exit 1; fi
if [ "$no" -eq 0 ]; then echo "PASS ${0##*/} ($files cases)"; else echo "FAIL ${0##*/} ($no of $files)"; fi
[ "$no" -eq 0 ]
