#!/usr/bin/env bash
# tests/l4/test_proof.sh: Proof A, nonce first (CONTRACT 5.3 as replaced by
# A-23; COL-3, FW-26, N1). Verify passes only against a nonce stored before
# the challenge went out, spends it on a pass, and refuses replays and
# answers to another nonce. Keys are generated at test time.
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

V=$(newhome verifier) || exit 1
P=$(newhome peer) || exit 1
VD=$(sdir "$V")
HOME=$V "$B" "$STATE" pin "$CID" Peer "$(pubof "$P")" "$(fp "$(pubof "$P")")" >/dev/null

issue() { HOME=$V "$B" "$PROOF" issue "$CID" Verifier Peer; }
answer() { HOME=$P "$B" "$PROOF" answer "$CID" Verifier Peer "$1" > "$2"; }
verify() { HOME=$V "$B" "$PROOF" verify "$CID" Peer "$1"; }
npend() { ls "$VD/pending" 2>/dev/null | wc -l | tr -d ' '; }

t "verify with no stored nonce fails"
answer "$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')" "$tmp/s0"
verify "$tmp/s0" >/dev/null 2>&1 && fail "passed without a nonce" || pass

t "issue stores the nonce in private state before printing it"
out=$(issue); n=${out##* nonce }
[ ${#n} -eq 32 ] && grep -q "^nonce: $n\$" "$VD/pending/peer" && grep -q '^verifier: verifier$' "$VD/pending/peer" && pass || fail "out=$out"
t "the stored nonce exists before the peer answers (ordering)"
[ "$(npend)" = 1 ] && pass || fail "no pending nonce before answer"
answer "$n" "$tmp/s1"
t "the answer is an SSH signature in the Collective namespace"
grep -q 'BEGIN SSH SIGNATURE' "$tmp/s1" && pass || fail "$(head -1 "$tmp/s1")"
t "a correct answer passes"
[ "$(verify "$tmp/s1")" = PASS ] && pass || fail "did not pass"
t "the nonce is deleted after the pass"
[ "$(npend)" = 0 ] && pass || fail "pending left"
t "a replay of the same answer fails"
verify "$tmp/s1" >/dev/null 2>&1 && fail "replay passed" || pass

t "an answer to a different nonce fails"
out=$(issue); n=${out##* nonce }
answer "$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')" "$tmp/s2"
verify "$tmp/s2" >/dev/null 2>&1 && fail "passed" || pass
t "a garbage signature file fails and leaves the nonce"
printf 'not a signature\n' > "$tmp/junk"
verify "$tmp/junk" >/dev/null 2>&1 && fail "passed" || { [ "$(npend)" = 1 ] && pass || fail "nonce spent"; }

t "one round in flight per Collective"
HOME=$V "$B" "$STATE" pin "$CID" Other "$(pubof "$V")" "$(fp "$(pubof "$V")")" >/dev/null
HOME=$V "$B" "$PROOF" issue "$CID" Verifier Other >/dev/null 2>&1 && fail "second round issued" || pass
answer "$n" "$tmp/s3"; verify "$tmp/s3" >/dev/null

t "two verifies racing on one nonce: exactly one passes (mv claim, N1)"
out=$(issue); n=${out##* nonce }; answer "$n" "$tmp/s4"
( verify "$tmp/s4" > "$tmp/r1" 2>/dev/null ) & ( verify "$tmp/s4" > "$tmp/r2" 2>/dev/null ) & wait
[ "$(cat "$tmp/r1" "$tmp/r2" | grep -c PASS)" = 1 ] && pass || fail "passes: $(cat "$tmp/r1" "$tmp/r2" | grep -c PASS)"

t "issue prints nothing when the nonce cannot be stored"
V2=$(newhome readonly) || exit 1
HOME=$V2 "$B" "$STATE" pin "$CID" Peer "$(pubof "$P")" "$(fp "$(pubof "$P")")" >/dev/null
: > "$(sdir "$V2")/pending"   # a file where the dir must go
out=$(HOME=$V2 "$B" "$PROOF" issue "$CID" Verifier Peer 2>/dev/null); rc=$?
[ "$rc" -ne 0 ] && [ -z "$out" ] && pass || fail "rc=$rc out=$out"

t "a path-like collective-id is refused"
HOME=$V "$B" "$PROOF" issue "../x" Verifier Peer >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && pass || fail "rc=$rc"

finish
