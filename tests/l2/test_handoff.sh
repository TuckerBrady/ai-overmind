#!/usr/bin/env bash
# L2 2.6 (TARS-6, TARS-7, GAP-23, GAP-24): "Handoff written this session" comes
# only from this session's own transcript; the new-brief line (L6) fires once
# for a brief someone else wrote, never for a self-handoff or this session's own.
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

root="$tmp/team"; mkteam "$root"
dev="$root/Nash - Developer"
export TARS_NOW=5000
L6="TARS: a new brief was written to your HANDOFF.md."
wdev=$(jpath "$dev")

# tool_use records, shaped like Claude Code's transcript
tu_write() { printf '{"isSidechain":%s,"type":"assistant","message":{"model":"claude-opus-4-1","content":[{"type":"tool_use","id":"toolu_1","name":"%s","input":{"file_path":"%s\\\\%s","content":"TYPE: SELF-HANDOFF"}}]}}\n' "$1" "$2" "$wdev" "$3"; }
tu_bash() { printf '{"isSidechain":false,"type":"assistant","message":{"model":"claude-opus-4-1","content":[{"type":"tool_use","id":"toolu_2","name":"Bash","input":{"command":"bash \\"${CLAUDE_PLUGIN_ROOT}/skills/go/handoff.sh\\" place \\"%s\\" /tmp/new.md","description":"place"}}]}}\n' "$wdev"; }
brief() { printf 'TYPE: %s\nSEAT: Nash\nMISSION: AXM-1\nWRITTEN: 2026-10-04 12:00\n%s\n## Next Steps\n' "$1" "${2:-}" > "$dev/HANDOFF.md"; }

# run SID PCT: one turn with the transcript at PCT% of a 200k window
run() { txline "$tmp/$1.jsonl" $(( $2 * 2000 )); hook "$1" "$dev" "$tmp/$1.jsonl"; }

# ---- another session's unstamped brief
: > "$tmp/a.jsonl"; run a 10 >/dev/null; backdate a
brief DISPATCH 'DISPATCHED BY: T-Bot'
out=$(run a 60)
t "2.6 a brief written by another session is not 'written this session'"
case $out in *"No handoff this session."*) pass ;; *) fail "got: $out" ;; esac
t "2.6 a dispatched brief gives exactly one L6"
expect "got: $out" test "$(count "$L6" "$out")" = 1
out=$(run a 66)
t "2.6 the L6 line does not repeat"
expect "got: $out" test "$(count "$L6" "$out")" = 0

# ---- SELF-HANDOFF from elsewhere: no L6
: > "$tmp/b.jsonl"; run b 10 >/dev/null; backdate b
brief SELF-HANDOFF
out=$(run b 60)
t "2.6 a SELF-HANDOFF gives no L6"
expect "got: $out" test "$(count "$L6" "$out")" = 0
backdate b
printf '**TYPE:** SELF-HANDOFF\n**SEAT:** Nash\n' > "$dev/HANDOFF.md"
out=$(run b 66)
t "2.6 a legacy bold SELF-HANDOFF header gives no L6"
expect "got: $out" test "$(count "$L6" "$out")" = 0
backdate b
brief DISPATCH 'ACTIVATED: 2026-10-04 12:05 by Nash (session abcd1234)'
out=$(run b 71)
t "a stamped brief is not new"
expect "got: $out" test "$(count "$L6" "$out")" = 0

# ---- this session wrote it with Write
: > "$tmp/c.jsonl"; run c 10 >/dev/null; backdate c
tu_write false Write HANDOFF.md >> "$tmp/c.jsonl"
brief DISPATCH
out=$(run c 60)
t "2.6 a Write to HANDOFF.md in this transcript is 'written this session'"
case $out in *"Handoff written this session."*) pass ;; *) fail "got: $out" ;; esac
t "2.6 this session's own handoff gives no L6"
expect "got: $out" test "$(count "$L6" "$out")" = 0

# ---- written with Edit counts too
: > "$tmp/c2.jsonl"; tu_write false Edit HANDOFF.md >> "$tmp/c2.jsonl"
out=$(run c2 60)
t "2.6 an Edit to HANDOFF.md counts"
case $out in *"Handoff written this session."*) pass ;; *) fail "got: $out" ;; esac

# ---- placed with handoff.sh place (GAP-23)
: > "$tmp/d.jsonl"; run d 10 >/dev/null; backdate d
tu_bash >> "$tmp/d.jsonl"
brief DISPATCH
out=$(run d 60)
t "GAP-23 a Bash handoff.sh place counts as written this session"
case $out in *"Handoff written this session."*) pass ;; *) fail "got: $out" ;; esac
t "GAP-23 and suppresses L6"
expect "got: $out" test "$(count "$L6" "$out")" = 0

# ---- a write older than the 256 KB tail stays written (GAP-24)
pad=$(printf '%01000d' 0)
i=0; while [ $i -lt 300 ]; do printf '{"type":"user","pad":"%s"}\n' "$pad"; i=$(( i + 1 )); done >> "$tmp/d.jsonl"
out=$(run d 66)
t "GAP-24 a handoff write older than the tail stays 'written'"
case $out in *"Handoff written this session."*) pass ;; *) fail "got: $out" ;; esac

# ---- things that are not this session's write
: > "$tmp/e.jsonl"
tu_write false Read HANDOFF.md >> "$tmp/e.jsonl"
tu_write true Write HANDOFF.md >> "$tmp/e.jsonl"
tu_write false Write NOTHANDOFF.md >> "$tmp/e.jsonl"
printf '{"isSidechain":false,"type":"user","message":{"content":"\\"name\\":\\"Write\\",\\"input\\":{\\"file_path\\":\\"x/HANDOFF.md\\""}}\n' >> "$tmp/e.jsonl"
out=$(run e 60)
t "2.6 a Read, a sidechain Write, another file, or quoted text are not a handoff write"
case $out in *"No handoff this session."*) pass ;; *) fail "got: $out" ;; esac

# ---- no transcript: turn-count fallback says no handoff
: > "$tmp/f.marker"
all=""; for n in 1 2; do all+=$(TARS_SOFT=2 hook f "$dev")$'\n'; done
t "GAP-24 with no transcript the status is 'No handoff this session'"
expect "got: $all" test "$(count 'TARS: turn 2. No handoff this session. Soft threshold (2) reached. Handoff suggested.' "$all")" = 1

t "grammar"
expect "grammar" grammar_ok "$out
$all"

finish
