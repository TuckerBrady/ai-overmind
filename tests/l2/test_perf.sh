#!/usr/bin/env bash
# L2 2.11 (TARS-13, GAP-16): on a quiet turn (transcript present, not the first
# turn, inside the 300 s Collective cadence) TARS runs at most 2 external
# commands on bash >= 5 (the meter's tail and grep), 3 on bash < 5 (date).
# Counted by logging PATH shims; TARS_NOW is left unset so the clock is real.
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

root="$tmp/team"; mkteam "$root" acme/venue
om="$root/T-Bot - The Overmind"; dev="$root/Nash - Developer"
printf '# B\n\n## Active\n\n| ID | Mission | Status | Priority |\n|---|---|---|---|\n| AXM-9 | x | ACTIVE | LOW |\n' > "$root/MISSION_BOARD.md"
printf '## 2026-10-01 - From T-Bot - UNREAD\n' > "$om/INBOX.md"
mkdir -p "$root/_claims"; printf '100 T-Bot\n' > "$root/_claims/OPS-30.perf1"
mkshims "$tmp/shim"; mkgh "$tmp/shim"
export FAKEGH="$tmp/gh"; mkdir -p "$FAKEGH"
printf 'TuckerBrady\n' > "$FAKEGH/user_out"
printf '%040d\tx\talice\ttrue\n' 1 > "$FAKEGH/commits"
export SHIMLOG="$tmp/shim.log" HOOKPATH="$tmp/shim" TARS_COLLECTIVE_SYNC=1
unset TARS_NOW
tx="$tmp/t.jsonl"; txline "$tx" 30000

limit=2; [ "${BASH_VERSINFO[0]}" -lt 5 ] && limit=3

for seat in "$om" "$dev"; do
  sid=perf1; [ "$seat" = "$dev" ] && sid=perf2
  hook "$sid" "$seat" "$tx" >/dev/null       # turn 1 (first; seeds the Collective)
  txline "$tx" 31000
  : > "$SHIMLOG"
  out=$(hook "$sid" "$seat" "$tx")           # turn 2: quiet
  n=0 cmds=""
  while IFS= read -r l; do n=$(( n + 1 )); cmds+="$l "; done < "$SHIMLOG"
  t "2.11 quiet turn (${seat##*/}): external commands <= $limit"
  expect "n=$n: $cmds" test "$n" -le "$limit"
  t "2.11 the shims saw the meter's tail and grep (the count is real)"
  case " $cmds" in *" tail "*) case " $cmds" in *" grep "*) pass ;; *) fail "saw: $cmds" ;; esac ;; *) fail "saw: $cmds" ;; esac
  t "2.11 quiet turn (${seat##*/}) prints nothing"
  expect "got: $out" test -z "$out"
done

finish
