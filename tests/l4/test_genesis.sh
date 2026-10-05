#!/usr/bin/env bash
# tests/l4/test_genesis.sh: Genesis commitments (CONTRACT 5.4, 5.10; COL-1,
# COL-15; GAP-35). First the section 7.10 vectors published in
# reference/collective.md, byte for byte, against both genesis.sh/proof.sh and
# this file's own sha256 loop. Then renewal, reuse and legacy cases.
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

seed=$(vec seed); cid=$(vec collective_id); nonce=$(vec nonce)

t "vectors are published"
for k in seed collective_id membership_seed base_1 anchor_1 next_1 record_1_sha256 genesis_id anchor_2 next_2 nonce reveal_99 proof_99 legacy_anchor legacy_reveal_99 legacy_proof_99; do
  [ -n "$(vec "$k")" ] || fail "vector $k missing"
done
[ "$no" -eq 0 ] && pass

# --- independent recomputation (this file's h/hn, not skills/collective/lib.sh)
t "vector: membership seed = sha256(seed:cid)"
[ "$(h "$seed:$cid")" = "$(vec membership_seed)" ] && pass || fail "mismatch"
t "vector: base_1 = sha256(M:1)"
[ "$(h "$(vec membership_seed):1")" = "$(vec base_1)" ] && pass || fail "mismatch"
t "vector: X_99 = base_1 hashed 99 times"
x99=$(hn "$(vec base_1)" 99)
[ "$x99" = "$(vec reveal_99)" ] && pass || fail "got $x99"
t "vector: anchor_1 = X_100"
[ "$(h "$x99")" = "$(vec anchor_1)" ] && pass || fail "mismatch"
t "vector: next_1 = sha256(anchor_2)"
[ "$(h "$(vec anchor_2)")" = "$(vec next_1)" ] && pass || fail "mismatch"
t "vector: record_1 hash and Genesis ID"
r=$(rec1 | { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi; }); r=${r%% *}
[ "$r" = "$(vec record_1_sha256)" ] && [ "${r:0:16}" = "$(vec genesis_id)" ] && pass || fail "got $r"
t "vector: published record-1 block equals the record built from the vectors"
blk=$(tr -d '\r' < "$repo/reference/collective.md" | sed -n '/^```record-1$/,/^```$/p' | sed '1d;$d')
[ "$blk" = "$(rec1)" ] && pass || fail "record-1 block differs"
t "vector: proof_99 = sha256(X_99 + nonce), hex text, no separator"
[ "$(h "$(vec reveal_99)$nonce")" = "$(vec proof_99)" ] && pass || fail "mismatch"
t "vector: legacy chain"
lx99=$(hn "$(h "AI-OVERMIND-GENESIS-CHAIN-V2|$(vec legacy_collective_id)|1|$(vec legacy_nonce)")" 99)
[ "$lx99" = "$(vec legacy_reveal_99)" ] && [ "$(h "$lx99")" = "$(vec legacy_anchor)" ] &&
  [ "$(h "$lx99$nonce")" = "$(vec legacy_proof_99)" ] && pass || fail "legacy vectors do not recompute"

# --- the scripts produce the same bytes
H1=$(newhome holder)
printf 'seed: %s\n' "$seed" > "$H1/.claude/overmind/genesis-seed"
t "genesis.sh anchor prints record-1 byte for byte"
HOME=$H1 "$B" "$GEN" anchor "$cid" > "$tmp/r1.out"
rec1 > "$tmp/r1.want"
cmp -s "$tmp/r1.out" "$tmp/r1.want" && pass || fail "$(od -c "$tmp/r1.out" | head -3)"
t "genesis.sh id prints the published Genesis ID"
[ "$(HOME=$H1 "$B" "$GEN" id < "$tmp/r1.out")" = "$(vec genesis_id)" ] && pass || fail "mismatch"
t "genesis.sh anchor <cid> 2 prints the generation-2 record (anchor_2, next_2)"
HOME=$H1 "$B" "$GEN" anchor "$cid" 2 > "$tmp/r2.out"
rec2 > "$tmp/r2.want"
cmp -s "$tmp/r2.out" "$tmp/r2.want" && pass || fail "record 2 differs"
t "proof.sh answer reproduces reveal_99 and proof_99"
out=$(HOME=$H1 "$B" "$PROOF" answer "$cid" 99 "$nonce")
[ "$out" = "$(printf 'reveal: %s\nindex: 99\nproof: %s' "$(vec reveal_99)" "$(vec proof_99)")" ] && pass || fail "got: $out"
t "a spent step is never revealed twice"
HOME=$H1 "$B" "$PROOF" answer "$cid" 99 "$nonce" >/dev/null 2>&1 && fail "re-revealed index 99" || pass

t "mint refuses to replace an existing seed"
out=$(HOME=$H1 "$B" "$GEN" mint)
grep -q "^seed: $seed\$" "$H1/.claude/overmind/genesis-seed" && [ "$out" = "already minted" ] && pass || fail "seed changed"
t "mint writes 64 hex to ~/.claude/overmind/genesis-seed and keeps a legacy nonce line"
H2=$(newhome minter); printf 'nonce: old phrase\n' > "$H2/.claude/overmind/genesis-seed"
HOME=$H2 "$B" "$GEN" mint >/dev/null
s2=$(sed -n 's/^seed: //p' "$H2/.claude/overmind/genesis-seed")
[ ${#s2} -eq 64 ] && grep -q '^nonce: old phrase$' "$H2/.claude/overmind/genesis-seed" && pass || fail "bad seed file"

# --- verifier side: renewal against the stored commitment
V=$(newhome verifier)
t "first anchor accepted (trust on first use)"
rec1 | HOME=$V "$B" "$GEN" accept "$cid" alpha >/dev/null && pass || fail "accept failed"
t "a second first-anchor for the same peer is refused"
rec2 | HOME=$V "$B" "$GEN" accept "$cid" alpha >/dev/null 2>&1 && fail "re-anchored" || pass
t "renewal with a forged gen-2 anchor fails"
printf 'gen: 2\nanchor: %s\nnext: %s\n' "$(h attacker)" "$(vec next_2)" |
  HOME=$V "$B" "$GEN" verify-renewal "$cid" alpha >/dev/null 2>&1 && fail "forged anchor accepted" || pass
t "renewal with a matching next passes"
out=$(rec2 | HOME=$V "$B" "$GEN" verify-renewal "$cid" alpha) && [ "$out" = PASS ] && pass || fail "got $out"
t "the private record moved to generation 2, index 100"
grep -q "^alpha$(printf '\t')2$(printf '\t')100$(printf '\t')$(vec anchor_2)$(printf '\t')$(vec next_2)$(printf '\t')committed\$" \
  "$V/.claude/overmind/collective/$cid/accepted" && pass || fail "$(cat "$V/.claude/overmind/collective/$cid/accepted")"
t "a reused gen-2 record fails"
rec2 | HOME=$V "$B" "$GEN" verify-renewal "$cid" alpha >/dev/null 2>&1 && fail "replay accepted" || pass
t "a generation-skipping record fails"
printf 'gen: 4\nanchor: %s\nnext: %s\n' "$(vec anchor_2)" "$(vec next_2)" |
  HOME=$V "$B" "$GEN" verify-renewal "$cid" alpha >/dev/null 2>&1 && fail "skip accepted" || pass

# COL-1: a passing reveal does not authorize an attacker's next anchor.
V2=$(newhome verifier2)
rec1 | HOME=$V2 "$B" "$GEN" accept "$cid" alpha >/dev/null
iss=$(HOME=$V2 "$B" "$PROOF" issue "$cid" alpha 99); n2=$(printf '%s\n' "$iss" | sed -n 's/^nonce: //p')
HOME=$V2 "$B" "$PROOF" verify "$cid" alpha "$(vec reveal_99)" "$(h "$(vec reveal_99)$n2")" >/dev/null
t "COL-1: after a passing reveal, an attacker's gen-2 anchor still fails"
printf 'gen: 2\nanchor: %s\nnext: %s\n' "$(h attacker2)" "$(h attacker3)" |
  HOME=$V2 "$B" "$GEN" verify-renewal "$cid" alpha >/dev/null 2>&1 && fail "hijack accepted" || pass

# --- legacy-uncommitted: once, then a commitment is required
V3=$(newhome verifier3)
la=$(vec legacy_anchor)
t "legacy chain accepted once, marked legacy-uncommitted"
HOME=$V3 "$B" "$GEN" accept-legacy "$cid" beta 1 100 "$la" >/dev/null &&
  grep -q "legacy-uncommitted\$" "$V3/.claude/overmind/collective/$cid/accepted" && pass || fail "not accepted"
t "a second legacy acceptance for the same peer is refused"
HOME=$V3 "$B" "$GEN" accept-legacy "$cid" beta 1 100 "$la" >/dev/null 2>&1 && fail "accepted twice" || pass
t "a fresh first anchor cannot replace a legacy peer"
rec1 | HOME=$V3 "$B" "$GEN" accept "$cid" beta >/dev/null 2>&1 && fail "replaced" || pass
t "legacy renewal without a passing Proof A in the round fails"
rec1 | HOME=$V3 "$B" "$GEN" verify-renewal "$cid" beta >/dev/null 2>&1 && fail "renewed without proof" || pass
# The legacy holder answers from the old derivation.
L=$(newhome legacyholder)
printf 'nonce: %s\n' "$(vec legacy_nonce)" > "$L/.claude/overmind/genesis-seed"
HOME=$L "$B" "$GEN" legacy-member "$cid" "$(vec legacy_collective_id)" 1 100 >/dev/null
iss=$(HOME=$V3 "$B" "$PROOF" issue "$cid" beta 99); n3=$(printf '%s\n' "$iss" | sed -n 's/^nonce: //p')
ans=$(HOME=$L "$B" "$PROOF" answer "$cid" 99 "$n3")
t "legacy holder answers with the pre-v5 chain"
[ "$(printf '%s\n' "$ans" | sed -n 's/^reveal: //p')" = "$(vec legacy_reveal_99)" ] && pass || fail "got: $ans"
HOME=$V3 "$B" "$PROOF" verify "$cid" beta "$(printf '%s\n' "$ans" | sed -n 's/^reveal: //p')" "$(printf '%s\n' "$ans" | sed -n 's/^proof: //p')" >/dev/null
t "legacy renewal without a next: commitment fails even after Proof A"
printf 'gen: 2\nanchor: %s\n' "$(vec anchor_1)" | HOME=$V3 "$B" "$GEN" verify-renewal "$cid" beta >/dev/null 2>&1 && fail "uncommitted renewal accepted" || pass
# A malformed record consumes nothing: run Proof A again for the real renewal.
iss=$(HOME=$V3 "$B" "$PROOF" issue "$cid" beta 98); n4=$(printf '%s\n' "$iss" | sed -n 's/^nonce: //p')
ans=$(HOME=$L "$B" "$PROOF" answer "$cid" 98 "$n4")
HOME=$V3 "$B" "$PROOF" verify "$cid" beta "$(printf '%s\n' "$ans" | sed -n 's/^reveal: //p')" "$(printf '%s\n' "$ans" | sed -n 's/^proof: //p')" >/dev/null
t "legacy renewal with a passing Proof A and a committed record passes"
printf 'gen: 2\nanchor: %s\nnext: %s\n' "$(vec anchor_2)" "$(vec next_2)" |
  HOME=$V3 "$B" "$GEN" verify-renewal "$cid" beta >/dev/null && grep -q "^beta$(printf '\t')2$(printf '\t')100.*committed\$" "$V3/.claude/overmind/collective/$cid/accepted" && pass || fail "not renewed"
t "after the re-anchor, a renewal needs the commitment (no proof shortcut)"
printf 'gen: 3\nanchor: %s\nnext: %s\n' "$(h x)" "$(h y)" | HOME=$V3 "$B" "$GEN" verify-renewal "$cid" beta >/dev/null 2>&1 && fail "accepted" || pass

# --- legacy-rows parses the live SEATS.md shapes (redacted fixture)
v1=$(h one); v2=$(h two); v3=$(h three)
cat > "$tmp/SEATS.md" <<EOF
# SEATS — ROSTER OF RECORD

| Overmind | Human principal | Handle | Seat status | Verified | Last signal |
|----------|-----------------|--------|-------------|----------|-------------|
| A-Bot | Example Person | a-bot | FULL (convener) | 2026-08-31 | 2026-10-04 |

## Genesis chain record

Written only by the convener.

| Overmind | Genesis ID | Generation | Last accepted index | Last accepted value | Accepted |
|----------|------------|------------|---------------------|---------------------|----------|
| A-Bot (home, a-bot, convener) | $v1 | 1 | 100 | $v2 | 2026-09-14 |
| B-Bot | \`$v1\` | 1 | 99 | \`$v3\` | 2026-09-11 |
| C-Bot | pending — mints under 4.1.4 | — | — | — | — |

## Notes
| D-Bot | $v1 | 1 | 50 | $v1 | 2026-09-01 |
EOF
printf '%s\n' "$(printf '%s' "$(cat "$tmp/SEATS.md")" | sed 's/$/\r/')" > "$tmp/SEATS.crlf.md"
want=$(printf 'A-Bot (home, a-bot, convener)\t1\t100\t%s\nB-Bot\t1\t99\t%s' "$v2" "$v3")
t "legacy-rows lists only the Genesis table's hex rows (plain and backticked; pending skipped)"
[ "$("$B" "$GEN" legacy-rows "$tmp/SEATS.md")" = "$want" ] && pass || fail "$("$B" "$GEN" legacy-rows "$tmp/SEATS.md")"
t "legacy-rows tolerates CRLF"
[ "$("$B" "$GEN" legacy-rows "$tmp/SEATS.crlf.md")" = "$want" ] && pass || fail "CRLF parse differs"

t "bad collective-id is refused and writes nothing"
H4=$(newhome badcid)
HOME=$H4 "$B" "$GEN" accept "../x" alpha < "$tmp/r1.want" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && [ -z "$(find "$H4" -type f)" ] && pass || fail "rc=$rc $(find "$H4" -type f)"

finish
