#!/usr/bin/env bash
# L2 2.9, 2.10, 2.7 (TARS-11, TARS-12, TARS-16, TARS-9; GAP-15, GAP-26):
# board scan reads only the Active section's Status column; state pruning keys
# on the turns file; the seat is pinned on turn 1; gh absent is said once.
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

root="$tmp/team"; mkteam "$root"
om="$root/T-Bot - The Overmind"; dev="$root/Nash - Developer"

board() { # rows for the Active table, one "status|priority" per argument
  {
    printf '# MISSION BOARD\n\n## How this board works\n\n| Prefix | Status |\n|---|---|\n| AXM- | ACTIVE |\n\n## Active\n\n'
    printf '| ID | Mission | Owner | Status | Priority | Blocker |\n|----|----|----|----|----|----|\n'
    local i=0 a
    for a in "$@"; do i=$(( i + 1 )); printf '| AXM-%s | m%s | T-Bot | %s | %s | |\n' "$i" "$i" "${a%%|*}" "${a#*|}"; done
    printf '\n## Archive\n\n| ID | Mission | Status | Completed |\n|---|---|---|---|\n| AXM-90 | old | ACTIVE | x |\n| AXM-91 | old | QUEUED | x |\n'
  } > "$root/MISSION_BOARD.md"
}
cue_at() { TARS_NOW=$2 hook "$1" "$om"; }

# ---- count: titles with status words, an INCOMPLETE row, Archive rows
board 'ACTIVE|STANDARD' 'REVIEW / BLOCKED|LOW' 'COMPLETE|CRITICAL' 'INCOMPLETE|P0'
sed -i.bak 's/| m3 |/| ACTIVE BLOCKED QUEUED words in a title |/' "$root/MISSION_BOARD.md" && rm -f "$root/MISSION_BOARD.md.bak"
cue_at b1 1000 >/dev/null
out=$(cue_at b1 1300)
t "2.9 Active section, Status column only: exactly 2 in flight"
expect "got: $out" test "$out" = "TARS (cue): mission watch due: 2 in flight, highest priority STANDARD. Run the watch rules and report only what you find."

# ---- priority map and cadence
board 'ACTIVE|P0'
cue_at b2 2000 >/dev/null
o1=$(cue_at b2 2059); o2=$(cue_at b2 2061)
t "2.9 a P0 row: no cue before 60 s"
expect "got: $o1" test -z "$o1"
t "2.9 a P0 row: cadence 60, tier CRITICAL"
expect "got: $o2" test "$(count 'highest priority CRITICAL' "$o2")" = 1
board 'QUEUED|HIGH'
cue_at b3 3000 >/dev/null; o=$(cue_at b3 3060)
t "2.9 HIGH maps to CRITICAL"
expect "got: $o" test "$(count 'highest priority CRITICAL' "$o")" = 1
board 'BLOCKED|MEDIUM'
cue_at b4 4000 >/dev/null; o1=$(cue_at b4 4299); o2=$(cue_at b4 4300)
t "2.9 MEDIUM maps to STANDARD, cadence 300"
expect "got: $o1 / $o2" test -z "$o1" -a "$(count 'highest priority STANDARD' "$o2")" = 1
board 'PENDING|whatever'
cue_at b5 5000 >/dev/null; o1=$(cue_at b5 8599); o2=$(cue_at b5 8600)
t "2.9 legacy PENDING counts; unknown priority is LOW, cadence 3600"
expect "got: $o1 / $o2" test -z "$o1" -a "$(count '1 in flight, highest priority LOW' "$o2")" = 1

# ---- state: the turns file is the pruning key (GAP-15)
hook st1 "$dev" >/dev/null
old "$TH/sessions/st1/turns" "$TH/sessions/st1"
hook st1 "$dev" >/dev/null
t "2.10 each turn advances the pruning key (\$st/turns)"
: > "$tmp/ref2001"; touch -t 200101010000 "$tmp/ref2001"
expect "turns not refreshed" test "$TH/sessions/st1/turns" -nt "$tmp/ref2001"
mkdir -p "$TH/sessions/gone"; : > "$TH/sessions/gone/turns"; old "$TH/sessions/gone/turns"
old "$TH/sessions/st1"                    # dir mtime old, turns fresh: an active session
hook st2 "$dev" >/dev/null                # a first turn prunes
t "2.10 a session whose last turn is over 7 days old is pruned"
expect "still there" test ! -d "$TH/sessions/gone"
t "2.10 an active session with an old directory mtime is kept (TARS-12)"
expect "pruned" test -d "$TH/sessions/st1"

# ---- seat pinned on turn 1 (TARS-16)
mkdir -p "$tmp/elsewhere"
hook pin "$dev" >/dev/null; backdate pin
printf 'TYPE: DISPATCH\nSEAT: Nash\nMISSION: AXM-1\nWRITTEN: 2026-10-04 12:00\nDISPATCHED BY: T-Bot\n' > "$dev/HANDOFF.md"
out=$(hook pin "$tmp/elsewhere")
t "2.10 the seat is pinned after turn 1 even when cwd changes"
expect "got: $out" test "$out" = "TARS: a new brief was written to your HANDOFF.md."
hook pin2 "$om" >/dev/null; backdate pin2
printf 'MISSION: OPS-5\n' > "$dev/mission-complete-OPS-5.md"
out=$(hook pin2 "$tmp/elsewhere")
t "2.10 the Overmind role is pinned too"
expect "got: $out" test "$out" = "TARS: Nash - Developer wrote mission-complete for OPS-5."

# ---- gh absent: one unavailable line across 3 turns
root2="$tmp/team2"; mkteam "$root2" acme/venue
mkshims "$tmp/shim"; export SHIMLOG="$tmp/shim.log"
all=""
for n in 0 1 2; do all+=$(HOOKPATH="$tmp/shim" TARS_COLLECTIVE_SYNC=1 TARS_NOW=$(( 9000 + n * 400 )) hook nogh "$root2/T-Bot - The Overmind")$'\n'; done
t "2.7 gh absent: the unavailable line appears exactly once across 3 turns"
expect "got: $all" test "$(count 'TARS: Collective feed unavailable: gh not installed.' "$all")" = 1

t "grammar"
expect "grammar" grammar_ok "$all"
finish
