#!/usr/bin/env bash
# tests/l4/test_private_state.sh: private state is authoritative (CONTRACT
# 5.5; COL-4, COL-8). Under a temporary HOME, accepted and ack are written
# only under ~/.claude/overmind/collective/<cid>/, the binder is never
# written, and a tampered SEATS.md or shared ledger is reported, not adopted.
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

cid=$(vec collective_id)
V=$(newhome verifier); D="$V/.claude/overmind/collective/$cid"
binder="$tmp/binder"; mkdir -p "$binder/posts" "$binder/ledgers"
a1=$(vec anchor_1)
cat > "$binder/SEATS.md" <<EOF
# SEATS

## Genesis chain record

| Overmind | Genesis ID | Generation | Last accepted index | Last accepted value | Accepted |
|----------|------------|------------|---------------------|---------------------|----------|
| alpha | $(vec genesis_id) | 1 | 100 | \`$a1\` | 2026-10-05 |
EOF
sha=$(h c1 | cut -c1-40); sha2=$(h c2 | cut -c1-40)
printf '# LEDGER — me\n\n**format:** 2\n**acked-commit:** %s\n' "$sha" > "$binder/ledgers/me.md"
snap() { find "$binder" -type f -exec cat {} + | { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi; }; }
before=$(snap)

( cd "$binder" && rec1 | HOME=$V "$B" "$GEN" accept "$cid" alpha >/dev/null
  HOME=$V "$B" "$STATE" ack "$cid" "$sha"
  HOME=$V "$B" "$PROOF" issue "$cid" alpha 99 >/dev/null
  HOME=$V "$B" "$STATE" event "$cid" "a test event" )

t "accepted and ack exist under ~/.claude/overmind/collective/<cid>/"
[ -f "$D/accepted" ] && [ -f "$D/ack" ] && pass || fail "missing: $(ls "$D")"
t "every file written is under that directory"
stray=$(find "$V" -type f | grep -v "^$D/")
[ -z "$stray" ] && pass || fail "$stray"
t "the binder was not written"
[ "$(snap)" = "$before" ] && [ -z "$(find "$binder" -newer "$D/ack" -type f)" ] && pass || fail "binder changed"
t "ack-get returns the private ack"
[ "$(HOME=$V "$B" "$STATE" ack-get "$cid")" = "$sha" ] && pass || fail "mismatch"

t "SEATS.md matching the private state is not a difference"
HOME=$V "$B" "$STATE" check-seats "$cid" "$binder/SEATS.md" >/dev/null && pass || fail "reported a difference"

t "a tampered SEATS.md value is reported"
cp "$D/accepted" "$tmp/acc.before"
sed "s/$a1/$(h forged)/" "$binder/SEATS.md" > "$tmp/SEATS.tampered.md"
out=$(HOME=$V "$B" "$STATE" check-seats "$cid" "$tmp/SEATS.tampered.md"); rc=$?
[ "$rc" -eq 1 ] && case $out in "DIFFERS alpha:"*"Not adopted."*) true ;; *) false ;; esac && pass || fail "rc=$rc out=$out"
t "and not adopted: the private record is unchanged"
cmp -s "$D/accepted" "$tmp/acc.before" && pass || fail "accepted changed"
t "a tampered index is reported too"
sed 's/| 1 | 100 |/| 1 | 7 |/' "$binder/SEATS.md" > "$tmp/SEATS.idx.md"
HOME=$V "$B" "$STATE" check-seats "$cid" "$tmp/SEATS.idx.md" >/dev/null && fail "not reported" || pass
t "a row removed from SEATS.md is reported missing"
grep -v '^| alpha' "$binder/SEATS.md" > "$tmp/SEATS.gone.md"
out=$(HOME=$V "$B" "$STATE" check-seats "$cid" "$tmp/SEATS.gone.md"); rc=$?
[ "$rc" -eq 1 ] && case $out in *"MISSING alpha"*) true ;; *) false ;; esac && pass || fail "rc=$rc out=$out"
t "a row this Overmind never accepted is reported, not adopted"
printf '| mallory | x | 1 | 100 | %s | 2026-10-05 |\n' "$(h m)" >> "$tmp/SEATS.extra.md"
cat "$binder/SEATS.md" "$tmp/SEATS.extra.md" > "$tmp/SEATS.plus.md"
out=$(HOME=$V "$B" "$STATE" check-seats "$cid" "$tmp/SEATS.plus.md")
case $out in *"UNTRACKED mallory"*) ! grep -q mallory "$D/accepted" && pass || fail "adopted" ;; *) fail "out=$out" ;; esac

t "a shared ledger edited by a peer is reported, and the private ack stands"
printf '# LEDGER — me\n\n**format:** 2\n**acked-commit:** %s\n' "$sha2" > "$tmp/ledger.edited.md"
out=$(HOME=$V "$B" "$STATE" check-ledger "$cid" "$tmp/ledger.edited.md"); rc=$?
[ "$rc" -eq 1 ] && [ "$(HOME=$V "$B" "$STATE" ack-get "$cid")" = "$sha" ] && pass || fail "rc=$rc out=$out"
t "the matching shared ledger is not a difference"
HOME=$V "$B" "$STATE" check-ledger "$cid" "$binder/ledgers/me.md" >/dev/null && pass || fail "reported"

t "differences are recorded in the private event log"
grep -q 'not adopted' "$D/events" && pass || fail "no event"

t "a malformed ack is refused"
HOME=$V "$B" "$STATE" ack "$cid" "not-a-sha" >/dev/null 2>&1 && fail "accepted" || pass
t "a path-like collective-id is refused"
HOME=$V "$B" "$STATE" ack "../../x" "$sha" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && [ ! -e "$V/.claude/overmind/x" ] && pass || fail "rc=$rc"

finish
