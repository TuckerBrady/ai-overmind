#!/usr/bin/env bash
# tests/l4/test_proof.sh: Proof A, nonce first (CONTRACT 5.3, COL-3).
# Verify passes only against a nonce stored before the challenge went out,
# deletes it on use, and refuses replays and answers to another nonce.
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

cid=$(vec collective_id)
V=$(newhome verifier); D="$V/.claude/overmind/collective/$cid"
H1=$(newhome holder)
printf 'seed: %s\n' "$(vec seed)" > "$H1/.claude/overmind/genesis-seed"
printf 'derivation: v5\ngeneration: 1\nlowest-revealed: 100\n' > "$tmp/m"
mkdir -p "$H1/.claude/overmind/collective/$cid"; cp "$tmp/m" "$H1/.claude/overmind/collective/$cid/membership"
rec1 | HOME=$V "$B" "$GEN" accept "$cid" alpha >/dev/null

issue() { HOME=$V "$B" "$PROOF" issue "$cid" "$@"; }
verify() { HOME=$V "$B" "$PROOF" verify "$cid" "$@"; }
pend() { ls "$D/pending" 2>/dev/null | wc -l | tr -d ' '; }

t "verify with no stored nonce fails"
verify alpha "$(vec reveal_99)" "$(vec proof_99)" >/dev/null 2>&1 && fail "passed without a nonce" || pass

t "issue stores the nonce in private state before printing it"
out=$(issue alpha 99); n=$(printf '%s\n' "$out" | sed -n 's/^nonce: //p')
f=$(ls "$D"/pending/* 2>/dev/null | head -1)
[ ${#n} -eq 32 ] && [ -n "$f" ] && grep -q "^nonce: $n\$" "$f" && grep -q '^index: 99$' "$f" && pass || fail "pending: $(cat "$f" 2>/dev/null)"

t "the stored nonce exists before the holder answers (ordering)"
[ "$(pend)" = 1 ] && pass || fail "no pending nonce before answer"
ans=$(HOME=$H1 "$B" "$PROOF" answer "$cid" 99 "$n")
x=$(printf '%s\n' "$ans" | sed -n 's/^reveal: //p'); p=$(printf '%s\n' "$ans" | sed -n 's/^proof: //p')

t "the answer binds X_k to the nonce as hex text"
[ "$p" = "$(h "$x$n")" ] && [ "$x" = "$(vec reveal_99)" ] && pass || fail "answer: $ans"

t "a correct answer passes"
[ "$(verify alpha "$x" "$p")" = PASS ] && pass || fail "did not pass"
t "the nonce is deleted after use"
[ "$(pend)" = 0 ] && pass || fail "pending left: $(pend)"
t "a replay of the same answer fails"
verify alpha "$x" "$p" >/dev/null 2>&1 && fail "replay passed" || pass
t "the private record advanced to index 99"
grep -q "^alpha$(printf '\t')1$(printf '\t')99$(printf '\t')$x" "$D/accepted" && pass || fail "$(cat "$D/accepted")"

# Further rounds use a synthetic chain built here, accepted as peer gamma.
x98=$(h "$tmp-random-preimage");
# Make x98 hash to the accepted x99: replace alpha with a synthetic chain.
y97=$(h "synthetic-97"); y98=$(h "$y97"); y99=$(h "$y98"); y100=$(h "$y99")
printf 'gen: 1\nanchor: %s\nnext: %s\n' "$y100" "$(h next)" | HOME=$V "$B" "$GEN" accept "$cid" gamma >/dev/null

t "an answer to a different nonce fails, and still spends the stored one"
issue gamma 99 >/dev/null
other=$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')
verify gamma "$y99" "$(h "$y99$other")" >/dev/null 2>&1 && fail "passed" || { [ "$(pend)" = 0 ] && pass || fail "nonce not spent"; }
t "a reveal that does not hash to the accepted value fails"
out=$(issue gamma 99); n=$(printf '%s\n' "$out" | sed -n 's/^nonce: //p')
verify gamma "$(h bogus)" "$(h "$(h bogus)$n")" >/dev/null 2>&1 && fail "passed" || pass
t "the proof is not a function of the reveal alone (pre-v5 style salted hash fails)"
out=$(issue gamma 99); n=$(printf '%s\n' "$out" | sed -n 's/^nonce: //p')
verify gamma "$y99" "$(h "$y99$(vec genesis_id)")" >/dev/null 2>&1 && fail "passed" || pass
t "a correct answer on the synthetic chain passes; a second step down passes next round"
out=$(issue gamma 99); n=$(printf '%s\n' "$out" | sed -n 's/^nonce: //p')
r1=$(verify gamma "$y99" "$(h "$y99$n")")
out=$(issue gamma 98); n=$(printf '%s\n' "$out" | sed -n 's/^nonce: //p')
r2=$(verify gamma "$y98" "$(h "$y98$n")")
[ "$r1" = PASS ] && [ "$r2" = PASS ] && pass || fail "r1=$r1 r2=$r2"
t "issue refuses an index at or above the last accepted index"
issue gamma 98 >/dev/null 2>&1 && fail "issued 98 again" || pass

t "one round in flight per Collective"
issue gamma 97 >/dev/null
issue alpha 98 >/dev/null 2>&1 && fail "second round issued" || pass
t "a nonce issued for one peer cannot be spent by another"
verify alpha "$y97" "$(h "$y97$(sed -n 's/^nonce: //p' "$D"/pending/*)")" >/dev/null 2>&1 && fail "cross-peer pass" || pass
verify gamma "$y97" "$(h "${y97}0")" >/dev/null 2>&1   # spend it

t "issue prints nothing when the nonce cannot be stored"
V2=$(newhome readonly); mkdir -p "$V2/.claude/overmind/collective/$cid"
rec1 | HOME=$V2 "$B" "$GEN" accept "$cid" alpha >/dev/null
: > "$V2/.claude/overmind/collective/$cid/pending"   # a file where the dir must go
out=$(HOME=$V2 "$B" "$PROOF" issue "$cid" alpha 99 2>/dev/null); rc=$?
[ "$rc" -ne 0 ] && [ -z "$out" ] && pass || fail "rc=$rc out=$out"

t "the holder never reveals an index at or above its lowest revealed"
HOME=$H1 "$B" "$PROOF" answer "$cid" 99 "$(vec nonce)" >/dev/null 2>&1 && fail "re-revealed" || pass

finish
