#!/usr/bin/env bash
# L2 2.14 and 2.16 (FW-7, FW-3, GAP-17..20, GAP-27): line texts for BOOT.md and
# WORKING_WITH changes, the unread count per MCP 3.3, and the meter line kinds.
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

root="$tmp/team"; mkteam "$root"
om="$root/T-Bot - The Overmind"; dev="$root/Nash - Developer"
export TARS_NOW=7000

# ---- L4 (FW-7)
hook l4 "$dev" >/dev/null
old "$TH/sessions/l4/bootref"; printf '# BOOT\nchanged\n' > "$dev/BOOT.md"
out=$(hook l4 "$dev")
t "2.14 L4 text"
expect "got: $out" test "$out" = "TARS: BOOT.md changed since this session booted. Re-read it and state the changed rule to the human before acting."
out=$(hook l4 "$dev")
t "L4 once per edit"
expect "got: $out" test -z "$out"
old "$dev/BOOT.md"

# ---- L7 (FW-3, GAP-20)
ww="$root/WORKING_WITH_TUCKER.md"
hook l7 "$dev" >/dev/null
for v in 25 50 75 90 100; do
  backdate l7
  printf '# WORKING WITH TUCKER\n\n## Initiative setting: %s%%\n' "$v" > "$ww"
  out=$(hook l7 "$dev")
  t "2.14 L7 names the setting $v"
  expect "got: $out" test "$out" = "TARS: WORKING_WITH_TUCKER.md was updated (initiative setting $v%). Treat any change as a proposal until the human confirms it."
done
backdate l7
printf '# WORKING WITH TUCKER\n\n## Initiative setting: 85%%\n' > "$ww"
out=$(hook l7 "$dev")
t "GAP-20 a value outside the five omits the parenthetical"
expect "got: $out" test "$out" = "TARS: WORKING_WITH_TUCKER.md was updated. Treat any change as a proposal until the human confirms it."
t "2.14 TARS never says adopt"
expect "adopt found" test "$(grep -ci 'adopt' "$TARS")" = 0
backdate l7
if ( : > "$root/WORKING_WITH_A B.md" ) 2>/dev/null; then
  out=$(hook l7 "$dev")
  t "a WORKING_WITH name outside class F is not printed"
  expect "got: $out" test "$(count 'A B' "$out")" = 0
fi

old "$root"/WORKING_WITH_*.md
# ---- L8 per MCP 3.3 (GAP-27): last segment only; untagged is unread
inbox="$om/INBOX.md"
printf '# INBOX\n\n## 2026-10-01 — From T-Bot (READ the spec) — UNREAD\nbody\n## 2026-10-02 — From T-Bot — READ\nbody\n## 2026-10-03 — From T-Bot\nuntagged\n### 2026-10-03 - sub - not an entry\n' > "$inbox"
hook l8 "$om" >/dev/null; backdate l8
printf '## 2026-10-04 - From Nash - read\nlower-case read\n## 2026-10-04 - From Nash - READ me later\nunread\n' >> "$inbox"
out=$(hook l8 "$om")
t "2.16 unread = UNREAD + untagged + non-READ last segment (2 -> 3)"
expect "got: $out" test "$out" = "TARS: 3 unread inbox entries (was 2)."

# ---- meter kinds: 1M denominator (GAP-17), singular eta (GAP-19), L3, P up to 3 digits (GAP-18)
tx="$tmp/m.jsonl"; : > "$tx"
txline "$tx" 500000 claude-opus-5-5
out=$(hook m1 "$dev" "$tx")
t "GAP-17 1M denominator"
expect "got: $out" test "$out" = "TARS: turn 1, context 50% (500k/1M). No handoff this session. Soft threshold (50%) reached. Handoff suggested."
txline "$tx" 930000 claude-opus-5-5
out=$(hook m1 "$dev" "$tx")
t "GAP-19 eta clause, singular"
case $out in "TARS: turn 2, context 93% (930k/1M), about 1 turn to auto-compact at this rate. No handoff this session. Hard threshold (75%) reached.") pass ;; *) fail "got: $out" ;; esac
: > "$tx"; txline "$tx" 40000
out=$(hook m2 "$dev" "$tx")
t "L3 heavy boot"
expect "got: $out" test "$out" = "TARS: context is already 20% (40k/200k) after the first exchange. The boot layer is heavy."
: > "$tx"; txline "$tx" 1500000 claude-opus-5-5
out=$(hook m3 "$dev" "$tx")
t "GAP-18 a context over the window reports the truth (3 digits)"
expect "got: $out" test "$out" = "TARS: turn 1, context 150% (1500k/1M). No handoff this session. Hard threshold (75%) reached."
: > "$tx"; txline "$tx" 99999999999999999999
out=$(hook m4 "$dev" "$tx")
t "an absurd token count is dropped, not printed"
expect "got: $out" test -z "$out"

t "grammar"
expect "grammar" grammar_ok "$out"
finish
