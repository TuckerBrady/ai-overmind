#!/usr/bin/env bash
# tests/l3/test_alloc.sh -- dispatch's alloc-id.sh (CONTRACT 4.4, AMENDMENTS GAP-39).
# RUBRIC L3.5.
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

team="$tmp/team"; mkteam "$team"
# Board max: OPS-041 active, OPS-057 archived. A stray _ids claim sits above both.
mkdir -p "$team/_ids/OPS-060" "$team/_ids/AXM-500"

t "10 parallel allocations: 10 distinct IDs, each above the board's and _ids' max"
for i in 1 2 3 4 5 6 7 8 9 10; do
  ( bash "$ALLOC" "$team" OPS > "$tmp/id.$i" 2>&1; echo $? > "$tmp/rc.$i" ) &
done
wait
ids=""; bad=0
for i in 1 2 3 4 5 6 7 8 9 10; do
  [ "$(cat "$tmp/rc.$i")" = 0 ] || bad=$((bad+1))
  id=$(cat "$tmp/id.$i"); ids="$ids$id
"
  case $id in OPS-[0-9][0-9][0-9]) n=${id#OPS-}; [ $((10#$n)) -gt 60 ] || bad=$((bad+1)) ;; *) bad=$((bad+1)) ;; esac
done
distinct=$(printf '%s' "$ids" | sort -u | grep -c .)
[ $bad -eq 0 ] && [ "$distinct" = 10 ] && pass || fail "bad=$bad distinct=$distinct: $(printf '%s' "$ids" | tr '\n' ' ')"

t "every allocated ID is claimed under _ids/"
miss=0; for id in $ids; do [ -d "$team/_ids/$id" ] || miss=$((miss+1)); done
[ $miss -eq 0 ] && pass || fail "$miss unclaimed"

t "the archive's max counts: a fresh team with only an archived OPS-057 gets OPS-058"
t2="$tmp/t2"; mkteam "$t2"; rm -rf "$t2/_ids"
grep -v '^| OPS-041 ' "$t2/MISSION_BOARD.md" > "$t2/b" && mv "$t2/b" "$t2/MISSION_BOARD.md"
out=$(bash "$ALLOC" "$t2" OPS); [ "$out" = OPS-058 ] && pass || fail "got $out"

t "other prefixes and rows outside Active/Archive don't count"
out=$(bash "$ALLOC" "$t2" AXM); [ "$out" = AXM-048 ] && pass || fail "got $out"

t "a team with no board starts at 001"
mkdir -p "$tmp/empty"; out=$(bash "$ALLOC" "$tmp/empty" QA); [ "$out" = QA-001 ] && pass || fail "got $out"

t "a bad prefix exits 2"
acc=""
for p in ops O TOOLONG "AX-1" ""; do
  bash "$ALLOC" "$t2" "$p" > /dev/null 2>&1; [ $? -eq 2 ] || acc="$acc '$p'"
done
[ -z "$acc" ] && pass || fail "accepted:$acc"

t "a missing team root exits 2"
bash "$ALLOC" "$tmp/nowhere" OPS > /dev/null 2>&1; [ $? -eq 2 ] && pass || fail "rc"

finish
