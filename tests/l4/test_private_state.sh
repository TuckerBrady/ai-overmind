#!/usr/bin/env bash
# tests/l4/test_private_state.sh: private state is authoritative (CONTRACT
# 5.5, A-23, A-24 N4; COL-4, COL-8). Under a temporary HOME, pins, ack and
# allowed_signers are written only under ~/.claude/overmind/collective/, the
# binder is never written, and a tampered SEATS.md or shared ledger is
# reported, not adopted.
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

V=$(newhome me) || exit 1
P=$(newhome peer) || exit 1
D=$(sdir "$V")
binder="$tmp/binder"; mkdir -p "$binder/posts" "$binder/ledgers"
row() { printf '| %s | %s | %s |\n' "$1" "$(fp "$2")" "$(cut -d' ' -f1,2 "$2")"; }
{ printf '# SEATS\n\n## Keys\n\n| Overmind | Fingerprint | Public key |\n|---|---|---|\n'
  row Peer "$(pubof "$P")"; row Me "$(pubof "$V")"; } > "$binder/SEATS.md"
sha=$(printf c1 | git hash-object --stdin); sha2=$(printf c2 | git hash-object --stdin)
printf '# LEDGER — me\n\n**format:** 2\n**acked-commit:** %s\n' "$sha" > "$binder/ledgers/me.md"
snap() { find "$binder" -type f -exec cat {} + | git hash-object --stdin; }
before=$(snap)

( cd "$binder" &&
  HOME=$V "$B" "$STATE" pin "$CID" Peer "$(pubof "$P")" "$(fp "$(pubof "$P")")" >/dev/null &&
  HOME=$V "$B" "$STATE" pin-self "$CID" Me >/dev/null &&
  HOME=$V "$B" "$STATE" ack "$CID" "$sha" &&
  HOME=$V "$B" "$PROOF" issue "$CID" Me Peer >/dev/null &&
  HOME=$V "$B" "$STATE" event "$CID" "a test event" )

t "pins, allowed_signers and ack exist under ~/.claude/overmind/collective/<cid>/"
[ -f "$D/pins/peer.pub" ] && [ -f "$D/allowed_signers" ] && [ -f "$D/ack" ] && pass || fail "missing: $(ls "$D")"
t "every file written is under ~/.claude/overmind/collective/"
stray=$(find "$V" -type f | grep -v "^$V/.claude/overmind/collective/")
[ -z "$stray" ] && pass || fail "$stray"
t "the binder was not written"
[ "$(snap)" = "$before" ] && pass || fail "binder changed"
t "allowed_signers names each pin by normalized label, git and Collective namespaces only"
grep -q "^peer namespaces=\"git,ai-overmind-collective\" ssh-ed25519 " "$D/allowed_signers" && [ "$(wc -l < "$D/allowed_signers" | tr -d ' ')" = 2 ] && pass || fail "$(cat "$D/allowed_signers")"
t "ack-get returns the private ack"
[ "$(HOME=$V "$B" "$STATE" ack-get "$CID")" = "$sha" ] && pass || fail "mismatch"

t "SEATS.md matching the pins is not a difference"
HOME=$V "$B" "$STATE" check-seats "$CID" "$binder/SEATS.md" >/dev/null && pass || fail "reported"
t "a tampered SEATS.md key is reported"
X=$(newhome intruder) || exit 1
{ printf '## Keys\n\n| Overmind | Fingerprint | Public key |\n|---|---|---|\n'; row Peer "$(pubof "$X")"; row Me "$(pubof "$V")"; } > "$tmp/SEATS.tampered.md"
cp "$D/pins/peer.pub" "$tmp/pin.before"
out=$(HOME=$V "$B" "$STATE" check-seats "$CID" "$tmp/SEATS.tampered.md"); rc=$?
[ "$rc" -eq 1 ] && case $out in "DIFFERS Peer:"*"Not adopted."*) true ;; *) false ;; esac && pass || fail "rc=$rc out=$out"
t "and not adopted: the pin is unchanged"
cmp -s "$D/pins/peer.pub" "$tmp/pin.before" && pass || fail "pin changed"
t "a lookalike row is reported"
{ printf '## Keys\n\n| Overmind | Fingerprint | Public key |\n|---|---|---|\n'; row "PEER" "$(pubof "$P")"; row Me "$(pubof "$V")"; } > "$tmp/SEATS.look.md"
out=$(HOME=$V "$B" "$STATE" check-seats "$CID" "$tmp/SEATS.look.md"); rc=$?
[ "$rc" -eq 1 ] && case $out in *"LOOKALIKE PEER"*) true ;; *) false ;; esac && pass || fail "rc=$rc out=$out"
t "a row removed from SEATS.md is reported missing"
grep -v '^| Peer' "$binder/SEATS.md" > "$tmp/SEATS.gone.md"
out=$(HOME=$V "$B" "$STATE" check-seats "$CID" "$tmp/SEATS.gone.md"); rc=$?
[ "$rc" -eq 1 ] && case $out in *"MISSING Peer"*) true ;; *) false ;; esac && pass || fail "rc=$rc out=$out"
t "a row never pinned is reported, not adopted"
{ cat "$binder/SEATS.md"; row Mallory "$(pubof "$X")"; } > "$tmp/SEATS.plus.md"
out=$(HOME=$V "$B" "$STATE" check-seats "$CID" "$tmp/SEATS.plus.md")
case $out in *"UNPINNED Mallory"*) [ ! -f "$D/pins/mallory.pub" ] && pass || fail "adopted" ;; *) fail "out=$out" ;; esac

t "a shared ledger edited by a peer is reported, and the private ack stands"
printf '**acked-commit:** %s\n' "$sha2" > "$tmp/ledger.edited.md"
out=$(HOME=$V "$B" "$STATE" check-ledger "$CID" "$tmp/ledger.edited.md"); rc=$?
[ "$rc" -eq 1 ] && [ "$(HOME=$V "$B" "$STATE" ack-get "$CID")" = "$sha" ] && pass || fail "rc=$rc out=$out"
t "the matching shared ledger is not a difference"
HOME=$V "$B" "$STATE" check-ledger "$CID" "$binder/ledgers/me.md" >/dev/null && pass || fail "reported"
t "differences are recorded in the private event log"
grep -q 'not adopted' "$D/events" && pass || fail "no event"

# N4: seed the ack from the last own-ledger commit signed by this Overmind's own key.
g="$tmp/g"; mkdir -p "$g/ledgers"
gitc() { git -C "$g" -c user.name=t -c user.email=t@example.invalid -c core.autocrlf=false "$@"; }
gitc init -q
printf 'a\n' > "$g/ledgers/me.md"; gitc add -A
gitc -c gpg.format=ssh -c user.signingkey="$(keyof "$V")" -c commit.gpgsign=true commit -q -m "own, signed"; own=$(gitc rev-parse HEAD)
printf 'b\n' > "$g/ledgers/me.md"; gitc add -A
gitc -c gpg.format=ssh -c user.signingkey="$(keyof "$P")" -c commit.gpgsign=true commit -q -m "edited by a pinned peer"
printf 'c\n' > "$g/ledgers/me.md"; gitc add -A; gitc -c commit.gpgsign=false commit -q -m "unsigned edit"
t "seed-ack takes the last own-ledger commit signed by this Overmind's own pinned key"
out=$(HOME=$V "$B" "$STATE" seed-ack "$CID" "$g" Me ledgers/me.md) && [ "$(HOME=$V "$B" "$STATE" ack-get "$CID")" = "$own" ] && pass || fail "out=$out"
t "with no such commit, seed-ack refuses and leaves the ack alone"
printf 'z\n' > "$g/ledgers/other.md"; gitc add -A; gitc -c commit.gpgsign=false commit -q -m other
HOME=$V "$B" "$STATE" ack "$CID" "$sha" 2>/dev/null
HOME=$V "$B" "$STATE" seed-ack "$CID" "$g" Me ledgers/other.md >/dev/null; rc=$?
[ "$rc" -eq 1 ] && [ "$(HOME=$V "$B" "$STATE" ack-get "$CID")" = "$sha" ] && pass || fail "rc=$rc"

t "a malformed ack is refused"
HOME=$V "$B" "$STATE" ack "$CID" "not-a-sha" >/dev/null 2>&1 && fail "accepted" || pass
t "a path-like collective-id is refused"
HOME=$V "$B" "$STATE" ack "../../x" "$sha" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && [ ! -e "$V/.claude/overmind/x" ] && pass || fail "rc=$rc"

finish
