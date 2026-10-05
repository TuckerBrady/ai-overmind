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

t "usage errors exit 2"
bash "$PLACE" frobnicate > /dev/null 2>&1; [ $? -eq 2 ] && pass || fail "rc"

finish
