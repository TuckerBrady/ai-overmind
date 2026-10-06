#!/usr/bin/env bash
# tests/rel/test_proof_claim.sh -- A-32: a stale .claim.<peer>.<pid> left by a
# killed `proof.sh verify` no longer blocks `proof.sh issue`. A claim blocks
# only while its PID is alive and it is under 10 minutes old.
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
ID="$repo/skills/assimilate/identity.sh"
STATE="$repo/skills/collective/state.sh"
CID=00112233445566778899aabbccddeeff

if ! command -v ssh-keygen >/dev/null 2>&1; then echo "  ssh-keygen missing"; fail "needs ssh-keygen"; finish; exit 1; fi
newhome() { local h="$tmp/home-$1"; mkdir -p "$h"; HOME=$h "$B" "$ID" mint >/dev/null || return 1; printf '%s' "$h"; }
fp() { local o; o=$(ssh-keygen -lf "$1"); o=${o#* }; printf '%s' "${o%% *}"; }
V=$(newhome verifier) || { fail "mint"; finish; exit 1; }
P=$(newhome peer) || { fail "mint"; finish; exit 1; }
pub="$P/.claude/overmind/collective/id_ed25519.pub"
HOME=$V "$B" "$STATE" pin "$CID" Peer "$pub" "$(fp "$pub")" >/dev/null
pend="$V/.claude/overmind/collective/$CID/pending"
issue() { HOME=$V "$B" "$PROOF" issue "$CID" Verifier Peer 2>&1; }
clear_pending() { rm -f "$pend"/* "$pend"/.claim.* 2>/dev/null; }
mkdir -p "$pend"

# A PID that has exited.
sh -c 'exit 0' & dead=$!; wait "$dead"

t "A-32: a claim whose PID is dead does not block issue, and is cleared"
clear_pending; : > "$pend/.claim.peer.$dead"
out=$(issue); rc=$?
[ $rc -eq 0 ] && [ ! -e "$pend/.claim.peer.$dead" ] && pass || fail "rc=$rc out=$out"

t "A-32: a claim older than 10 minutes does not block issue, even with a live PID"
clear_pending; : > "$pend/.claim.peer.$$"; touch -t 200001010000 "$pend/.claim.peer.$$"
out=$(issue); rc=$?
[ $rc -eq 0 ] && pass || fail "rc=$rc out=$out"

t "A-32: a claim with a non-numeric PID does not block issue"
clear_pending; : > "$pend/.claim.peer.x1"
out=$(issue); rc=$?
[ $rc -eq 0 ] && pass || fail "rc=$rc out=$out"

t "A-32: a fresh claim by a live PID still blocks issue (one round at a time)"
clear_pending; : > "$pend/.claim.peer.$$"
out=$(issue); rc=$?
[ $rc -ne 0 ] && [ -e "$pend/.claim.peer.$$" ] && pass || fail "rc=$rc out=$out"

t "A-32: an issued nonce awaiting verify still blocks a second issue"
clear_pending; issue > /dev/null
out=$(issue); rc=$?
[ $rc -ne 0 ] && pass || fail "second round issued: $out"

t "A-32: verify stamps its claim when it takes it, so the claim's age starts then"
grep -q 'touch "\$claim"' "$PROOF" && pass || fail "no stamp in verify"

finish
