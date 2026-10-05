#!/usr/bin/env bash
# tests/l3/test_place.sh -- handoff.sh place and migrate (CONTRACT 4.2, 4.3, 7.2).
# RUBRIC L3.3 and L3.4.
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

s="$tmp/team/Nash - Developer"; mkdir -p "$s"
place() { bash "$PLACE" place "$s" "$1" 2>&1; }

t "no existing brief: the new one is placed"
brief "$tmp/n1" DISPATCH Nash AXM-1 "2026-10-05 09:00"; cp "$tmp/n1" "$tmp/expect1"
out=$(place "$tmp/n1")
case $out in "PLACED: "*) cmp -s "$tmp/expect1" "$s/HANDOFF.md" && [ ! -e "$tmp/n1" ] && pass || fail "content or source left" ;; *) fail "$out" ;; esac

t "an unstamped existing brief is renamed HANDOFF.superseded-*, never overwritten"
brief "$tmp/n2" SELF-HANDOFF Nash NONE "2026-10-05 10:00"
out=$(place "$tmp/n2")
sup=$(ls "$s" | grep '^HANDOFF\.superseded-[0-9]\{8\}-[0-9]\{4\}\.md$')
case $out in *"SUPERSEDED: HANDOFF.superseded-"*"PLACED: "*) ;; *) fail "output: $out" ;; esac
[ -n "$sup" ] && grep -q '^TYPE: DISPATCH' "$s/$sup" && grep -q '^TYPE: SELF-HANDOFF' "$s/HANDOFF.md" && pass || fail "superseded=$sup"

t "a second supersede in the same minute gets a distinct name"
brief "$tmp/n3" INFORMATIONAL Nash NONE "2026-10-05 11:00"
place "$tmp/n3" > /dev/null
n=$(ls "$s" | grep -c '^HANDOFF\.superseded-')
[ "$n" = 2 ] && pass || fail "$n superseded files"

t "a brief stamped ACTIVATED is replaced, not superseded"
brief "$s/HANDOFF.md" DISPATCH Nash AXM-2 "2026-10-05 12:00" "ACTIVATED: 2026-10-05 12:01 by Nash (session abcd1234)"
brief "$tmp/n4" DISPATCH Nash AXM-3 "2026-10-05 13:00"
out=$(place "$tmp/n4")
n=$(ls "$s" | grep -c '^HANDOFF\.superseded-')
case $out in *SUPERSEDED*) fail "superseded a stamped brief" ;; *) [ "$n" = 2 ] && grep -q '^MISSION: AXM-3' "$s/HANDOFF.md" && pass || fail "not replaced" ;; esac

t "a brief stamped CONSOLIDATED-INTO is replaced, not superseded"
brief "$s/HANDOFF.md" SELF-HANDOFF Nash NONE "2026-10-05 14:00" "CONSOLIDATED-INTO: OPS-030 (consolidated 20261005-1400) 2026-10-05 14:00"
brief "$tmp/n5" DISPATCH Nash AXM-4 "2026-10-05 15:00"
out=$(place "$tmp/n5")
case $out in *SUPERSEDED*) fail "superseded a consolidated brief" ;; *) grep -q '^MISSION: AXM-4' "$s/HANDOFF.md" && pass || fail "not replaced" ;; esac

t "a legacy bold-stamped brief counts as stamped"
printf '**TYPE:** DISPATCH\n**SEAT:** Nash\n**ACTIVATED:** 2026-10-01 by Nash\n' > "$s/HANDOFF.md"
brief "$tmp/n6" DISPATCH Nash AXM-5 "2026-10-05 16:00"
out=$(place "$tmp/n6")
case $out in *SUPERSEDED*) fail "superseded a stamped legacy brief" ;; *) pass ;; esac

t "a body line mentioning 'Stamp ACTIVATED:' does not count as a stamp"
brief "$s/HANDOFF.md" DISPATCH Nash AXM-6 "2026-10-05 17:00" "Stamp ACTIVATED: [time] under the header."
brief "$tmp/n7" DISPATCH Nash AXM-7 "2026-10-05 18:00"
out=$(place "$tmp/n7")
case $out in *SUPERSEDED*) pass ;; *) fail "an unclaimed brief was overwritten" ;; esac

t "place refuses a missing new file (exit 2) and leaves the brief alone"
before=$(cat "$s/HANDOFF.md")
bash "$PLACE" place "$s" "$tmp/nope" > /dev/null 2>&1; rc=$?
[ $rc -eq 2 ] && [ "$(cat "$s/HANDOFF.md")" = "$before" ] && pass || fail "rc=$rc"

# ---------------------------------------------------------------- migrate
m="$tmp/team/Vaughn - QA"; mkdir -p "$m/.auto-memory"
t "migrate with no brief anywhere prints NONE"
out=$(bash "$PLACE" migrate "$m" 2>&1); [ "$out" = NONE ] && pass || fail "$out"

t "a legacy-only brief moves to the canonical path, leaving HANDOFF.migrated-<ts>.md"
brief "$m/.auto-memory/HANDOFF.md" SELF-HANDOFF Vaughn NONE "2026-10-05 09:00"
out=$(bash "$PLACE" migrate "$m" 2>&1)
mig=$(ls "$m/.auto-memory" | grep '^HANDOFF\.migrated-[0-9]\{8\}-[0-9]\{4\}\.md$')
case $out in *"MIGRATED: .auto-memory/HANDOFF.migrated-"*) ;; *) fail "output: $out" ;; esac
[ -f "$m/HANDOFF.md" ] && [ ! -e "$m/.auto-memory/HANDOFF.md" ] && [ -n "$mig" ] && cmp -s "$m/HANDOFF.md" "$m/.auto-memory/$mig" && pass || fail "files: $(ls -a "$m" "$m/.auto-memory" | tr '\n' ' ')"

t "identical copies in both places: canonical wins, nothing moves"
cp "$m/HANDOFF.md" "$m/.auto-memory/HANDOFF.md"
out=$(bash "$PLACE" migrate "$m" 2>&1)
case $out in "CURRENT: "*) [ -f "$m/.auto-memory/HANDOFF.md" ] && pass || fail "legacy moved" ;; *) fail "$out" ;; esac

t "an older legacy copy never displaces a newer canonical brief"
brief "$m/.auto-memory/HANDOFF.md" SELF-HANDOFF Vaughn NONE "2026-09-01 09:00"
out=$(bash "$PLACE" migrate "$m" 2>&1)
case $out in "CURRENT: "*) grep -q '^WRITTEN: 2026-10-05' "$m/HANDOFF.md" && pass || fail "canonical changed" ;; *) fail "$out" ;; esac

t "a newer legacy brief migrates, and an untaken canonical brief is superseded, not lost"
brief "$m/.auto-memory/HANDOFF.md" SELF-HANDOFF Vaughn NONE "2026-10-06 09:00"
out=$(bash "$PLACE" migrate "$m" 2>&1)
sup=$(ls "$m" | grep -c '^HANDOFF\.superseded-')
case $out in *"SUPERSEDED: "*"MIGRATED: "*) grep -q '^WRITTEN: 2026-10-06' "$m/HANDOFF.md" && [ "$sup" = 1 ] && pass || fail "state wrong" ;; *) fail "$out" ;; esac

t "A-26: migrate asks when the copies differ and one can't be dated"
a="$tmp/team/Ask"; mkdir -p "$a/.auto-memory"
brief "$a/HANDOFF.md" SELF-HANDOFF Ask NONE "2026-10-05 09:00"
printf 'TYPE: SELF-HANDOFF\nSEAT: Ask\nnotes without a date\n' > "$a/.auto-memory/HANDOFF.md"
out=$(bash "$PLACE" migrate "$a" 2>&1)
case $out in "ASK: "*"CANONICAL: $a/HANDOFF.md"*"LEGACY: $a/.auto-memory/HANDOFF.md"*) [ -f "$a/.auto-memory/HANDOFF.md" ] && grep -q '^WRITTEN: 2026-10-05 09:00' "$a/HANDOFF.md" && pass || fail "something moved" ;; *) fail "$out" ;; esac

t "A-26: a HANDOFF.md that is a folder is refused, by place and by migrate"
d="$tmp/team/Dir"; mkdir -p "$d/HANDOFF.md"
brief "$tmp/nd" DISPATCH Dir AXM-1 "2026-10-05 09:00"
out=$(bash "$PLACE" place "$d" "$tmp/nd" 2>&1); rc=$?
out2=$(bash "$PLACE" migrate "$d" 2>&1); rc2=$?
case "$out|$out2" in "REFUSED: HANDOFF.md is a folder|REFUSED: HANDOFF.md is a folder") [ $rc -eq 2 ] && [ $rc2 -eq 2 ] && pass || fail "rc $rc/$rc2" ;; *) fail "$out | $out2" ;; esac

t "A-26: a HANDOFF.md that is a symlink is refused"
l="$tmp/team/Link"; mkdir -p "$l"; printf 'elsewhere\n' > "$tmp/target.md"
if ln -s "$tmp/target.md" "$l/HANDOFF.md" 2>/dev/null && [ -L "$l/HANDOFF.md" ]; then
  brief "$tmp/nl" DISPATCH Link AXM-1 "2026-10-05 09:00"
  out=$(bash "$PLACE" place "$l" "$tmp/nl" 2>&1); rc=$?
  [ $rc -eq 2 ] && grep -q '^elsewhere' "$tmp/target.md" && case $out in "REFUSED: HANDOFF.md is a symlink"*) true ;; *) false ;; esac && pass || fail "$out"
else
  echo "  (symlinks unavailable on this filesystem: case not reachable)"; pass
fi

race() { # N -> number of briefs lost when N placements race on one seat
  local n=$1 r="$tmp/race.$1.$RANDOM" i got
  mkdir -p "$r/seat"
  i=1; while [ $i -le "$n" ]; do brief "$r/new.$i" DISPATCH Seat "AXM-$i" "2026-10-05 09:00"; i=$((i+1)); done
  i=1; while [ $i -le "$n" ]; do bash "$PLACE" place "$r/seat" "$r/new.$i" > /dev/null 2>&1 & i=$((i+1)); done
  wait
  got=$(cat "$r/seat"/HANDOFF*.md 2>/dev/null | grep -c '^MISSION: AXM-')
  echo $((n - got))
}
t "A-26: 20 two-way races lose no brief"
lost=0; k=0
while [ $k -lt 20 ]; do lost=$((lost + $(race 2))); k=$((k+1)); done
[ $lost -eq 0 ] && pass || fail "$lost briefs lost"
t "A-26: a 10-way race loses no brief, and leaves no lock behind"
lost=$(race 10)
[ "$lost" -eq 0 ] && [ -z "$(ls -d "$tmp"/race.10.*/seat/.handoff.lock 2>/dev/null)" ] && pass || fail "$lost briefs lost"

t "a stale lock (over 30 s old) is broken, not waited on forever"
st="$tmp/team/Stale"; mkdir -p "$st/.handoff.lock"; echo 1000 > "$st/.handoff.lock/at"
brief "$tmp/ns" DISPATCH Stale AXM-1 "2026-10-05 09:00"
out=$(bash "$PLACE" place "$st" "$tmp/ns" 2>&1)
case $out in "PLACED: "*) pass ;; *) fail "$out" ;; esac

t "usage errors exit 2"
bash "$PLACE" frobnicate > /dev/null 2>&1; [ $? -eq 2 ] && pass || fail "rc"

finish
