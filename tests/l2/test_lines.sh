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
# ---- L8 unread count per amendment A-8 (replaces 3.3 / GAP-27). Each header
# of fixtures/inbox_a8.txt is classified alone: a session starts on an empty
# inbox, the header is written, and the next turn reports growth only if the
# entry is unread.
inbox="$om/INBOX.md"
k=0 unread=0 total=0
while IFS= read -r l || [ -n "$l" ]; do
  l=${l%"$cr"}
  case $l in ''|'#'*) continue ;; esac
  want=${l%%"$tab"*}; h=${l#*"$tab"}
  k=$(( k + 1 )); total=$(( total + 1 ))
  : > "$inbox"
  hook "a8_$k" "$om" >/dev/null; backdate "a8_$k"
  printf '# INBOX\n\n%s\nbody\n### 2026-10-03 - READ - a sub-heading is not an entry\n' "$h" > "$inbox"
  out=$(hook "a8_$k" "$om")
  got=READ; [ "$out" = "TARS: 1 unread inbox entries (was 0)." ] && got=UNREAD
  [ "$got" = UNREAD ] && unread=$(( unread + 1 ))
  t "A-8 $want: $h"
  expect "classified $got (output: $out)" test "$got" = "$want"
done < "$here/fixtures/inbox_a8.txt"

# the whole fixture as one inbox, then growth by two
{ printf '# INBOX\n\n'; while IFS= read -r l || [ -n "$l" ]; do l=${l%"$cr"}; case $l in ''|'#'*) continue ;; esac; printf '%s\nbody\n' "${l#*"$tab"}"; done < "$here/fixtures/inbox_a8.txt"; } > "$inbox"
hook l8 "$om" >/dev/null; backdate l8
printf '## 2026-10-06 — From Nash — UNREAD — new\n## 2026-10-06 — From Nash — READ-ONLY\n## 2026-10-06 — From Nash — READ\n' >> "$inbox"
out=$(hook l8 "$om")
t "A-8 whole fixture: $unread unread of $total, then +2"
expect "got: $out" test "$out" = "TARS: $(( unread + 2 )) unread inbox entries (was $unread)."

# ---- the shared A-8 fixture from L5 (mcp/testdata/inbox-rule/Sam - QA/INBOX.md
# at b61c7f8, copied byte for byte). Line 1 holds the oracle count; bodies say
# unread: or processed:. TARS must count exactly that many, fence included.
shared="$here/fixtures/inbox-rule-INBOX.md"
exp=""; IFS= read -r l1 < "$shared"; l1=${l1%"$cr"}
case $l1 in '<!-- expected unread: '*' -->') exp=${l1#'<!-- expected unread: '}; exp=${exp%' -->'} ;; esac
bodies=0
while IFS= read -r l || [ -n "$l" ]; do case $l in unread:*) bodies=$(( bodies + 1 )) ;; esac; done < "$shared"
t "shared fixture: oracle on line 1 is 10 and matches its unread: bodies"
expect "oracle=$exp bodies=$bodies" test "$exp" = 10 -a "$bodies" = 10
: > "$inbox"
hook shared1 "$om" >/dev/null; backdate shared1
cp "$shared" "$inbox"
out=$(hook shared1 "$om")
t "A-8 shared fixture: TARS counts exactly $exp unread"
expect "got: $out" test "$out" = "TARS: $exp unread inbox entries (was 0)."
# the same file with CRLF line endings (a Windows checkout)
: > "$inbox"
hook shared2 "$om" >/dev/null; backdate shared2
while IFS= read -r l || [ -n "$l" ]; do printf '%s\r\n' "${l%"$cr"}"; done < "$shared" > "$inbox"
out=$(hook shared2 "$om")
t "A-8 shared fixture with CRLF: still $exp"
expect "got: $out" test "$out" = "TARS: $exp unread inbox entries (was 0)."

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
