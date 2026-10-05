#!/usr/bin/env bash
# L2 2.5 and 2.13 (TARS-8): a mission-complete event and a watch-cue window are
# claimed with mkdir; across concurrent Overmind sessions exactly one prints.
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

root="$tmp/team"; mkteam "$root"
om="$root/T-Bot - The Overmind"; dev="$root/Nash - Developer"
export TARS_NOW=3000

for s in 1 2 3 4 5; do hook "ov$s" "$om" >/dev/null; backdate "ov$s"; done
printf 'MISSION: AXM-1\nRESULT: PASS\n' > "$dev/mission-complete-AXM-1.md"
for s in 1 2 3 4 5; do hook "ov$s" "$om" > "$tmp/out$s" & done
wait
all=""; for s in 1 2 3 4 5; do all+=$(cat "$tmp/out$s")$'\n'; done
t "2.5 five concurrent sessions, one mission-complete-AXM-1.md: exactly one L5"
expect "got: $all" test "$(count 'wrote mission-complete' "$all")" = 1
t "2.13 the ID comes from the filename"
expect "got: $all" test "$(count 'TARS: Nash - Developer wrote mission-complete for AXM-1.' "$all")" = 1

for s in 1 2 3 4 5; do backdate "ov$s"; done
printf 'Result for OPS-77 and AXM-2\n' > "$dev/mission-complete.md"
for s in 1 2 3 4 5; do hook "ov$s" "$om" > "$tmp/out$s" & done
wait
all=""; for s in 1 2 3 4 5; do all+=$(cat "$tmp/out$s")$'\n'; done
t "2.13 legacy mission-complete.md: one line, ID from the content"
expect "got: $all" test "$(count 'TARS: Nash - Developer wrote mission-complete for OPS-77.' "$all")" = 1

# ---- watch cue: one per cadence window across sessions
printf '# B\n\n## Active\n\n| ID | Mission | Status | Priority |\n|---|---|---|---|\n| AXM-9 | x | ACTIVE | STANDARD |\n' > "$root/MISSION_BOARD.md"
for s in 1 2 3 4 5; do TARS_NOW=3100 hook "w$s" "$om" >/dev/null; done
for s in 1 2 3 4 5; do TARS_NOW=3400 hook "w$s" "$om" > "$tmp/out$s" & done
wait
all=""; for s in 1 2 3 4 5; do all+=$(cat "$tmp/out$s")$'\n'; done
t "2.5 five concurrent sessions, one watch window: exactly one C1"
expect "got: $all" test "$(count 'TARS (cue): mission watch due: 1 in flight, highest priority STANDARD.' "$all")" = 1
for s in 1 2 3 4 5; do TARS_NOW=3800 hook "w$s" "$om" > "$tmp/out$s" & done
wait
all2=""; for s in 1 2 3 4 5; do all2+=$(cat "$tmp/out$s")$'\n'; done
t "2.5 the next window gets exactly one C1"
expect "got: $all2" test "$(count 'mission watch due' "$all2")" = 1

t "grammar"
expect "grammar" grammar_ok "$all$all2"

# ---- claim dirs older than 7 days are pruned on a session's first turn
mkdir -p "$TH/claims/mc.old.old"; old "$TH/claims/mc.old.old"
hook fresh1 "$om" >/dev/null
t "2.5 claim dirs older than 7 days are pruned"
expect "still there" test ! -d "$TH/claims/mc.old.old"
t "2.5 recent claims are kept"
set -- "$TH"/claims/cue.*
expect "cue claims gone" test -d "$1"

finish
