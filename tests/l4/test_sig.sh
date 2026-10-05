#!/usr/bin/env bash
# tests/l4/test_sig.sh: Collective identity by signature (CONTRACT A-23;
# COL-1, COL-3, COL-4, M1, N1, N5). Keys are generated at test time.
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

V=$(newhome verifier) || exit 1     # verifier, label "Convener"
A=$(newhome alpha) || exit 1        # peer, label "A-Bot"
Bk=$(newhome beta) || exit 1        # another seat, label "B-Bot"
VD=$(sdir "$V")

pin() { HOME=$V "$B" "$STATE" pin "$CID" "$1" "$2" "$(fp "$2")"; }
issue() { HOME=$V "$B" "$PROOF" issue "$CID" Convener "$1" | sed -n 's/.* nonce //p'; }
answer() { HOME=$1 "$B" "$PROOF" answer "$2" "$3" "$4" "$5" > "$6"; }   # home cid verifier me nonce out
verify() { HOME=$V "$B" "$PROOF" verify "$CID" "$1" "$2"; }
npend() { ls "$VD/pending" 2>/dev/null | wc -l | tr -d ' '; }

t "identity.sh check proves sign and verify work here"
HOME=$V "$B" "$ID" check >/dev/null && pass || fail "ssh-keygen -Y unavailable"
t "the private key is mode 600 and only under ~/.claude/overmind/collective/"
[ -f "$(keyof "$A")" ] && [ -z "$(find "$A" -type f ! -path "$A/.claude/overmind/collective/*")" ] && pass || fail "stray files"

t "pinning refuses a fingerprint that does not match the key"
HOME=$V "$B" "$STATE" pin "$CID" A-Bot "$(pubof "$A")" "$(fp "$(pubof "$Bk")")" >/dev/null 2>&1 && fail "pinned" || pass
pin A-Bot "$(pubof "$A")" >/dev/null
pin B-Bot "$(pubof "$Bk")" >/dev/null
HOME=$V "$B" "$STATE" pin-self "$CID" Convener >/dev/null

# 1. sign then verify
n=$(issue A-Bot)
answer "$A" "$CID" Convener A-Bot "$n" "$tmp/s1"
t "sign then verify passes"
[ "$(verify A-Bot "$tmp/s1")" = PASS ] && pass || fail "did not pass"
t "the nonce is spent by the pass, and a replay fails"
[ "$(npend)" = 0 ] && ! verify A-Bot "$tmp/s1" >/dev/null 2>&1 && pass || fail "replay passed or nonce left"

# 2. tampered nonce
n=$(issue A-Bot)
other=$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')
answer "$A" "$CID" Convener A-Bot "$other" "$tmp/s2"
t "a signature over a different nonce fails"
verify A-Bot "$tmp/s2" >/dev/null 2>&1 && fail "passed" || pass
t "a failed attempt does not spend the nonce (only the pinned key can)"
[ "$(npend)" = 1 ] && pass || fail "nonce spent by a failure"

# 3. replay to another verifier label: the same nonce, signed for verifier "Other".
answer "$A" "$CID" Other A-Bot "$n" "$tmp/s3"
t "a signature made for another verifier label fails"
verify A-Bot "$tmp/s3" >/dev/null 2>&1 && fail "passed" || pass

# 4. replay to another cid: the same nonce and labels, signed for CID2.
answer "$A" "$CID2" Convener A-Bot "$n" "$tmp/s4"
t "a signature made for another Collective fails"
verify A-Bot "$tmp/s4" >/dev/null 2>&1 && fail "passed" || pass

# 7. key B signs claiming to be A
answer "$Bk" "$CID" Convener A-Bot "$n" "$tmp/s7"
t "a signature by key B claiming peer A fails"
verify A-Bot "$tmp/s7" >/dev/null 2>&1 && fail "passed" || pass
t "the real answer still passes after all those failures"
answer "$A" "$CID" Convener A-Bot "$n" "$tmp/s7ok"
[ "$(verify A-Bot "$tmp/s7ok")" = PASS ] && pass || fail "did not pass"

# 5. unpinned key
U=$(newhome unpinned) || exit 1
t "issue refuses a peer with no pin"
HOME=$V "$B" "$PROOF" issue "$CID" Convener U-Bot >/dev/null 2>&1 && fail "issued" || pass
t "an unpinned key's signature fails against the pin it claims"
n=$(issue A-Bot); answer "$U" "$CID" Convener A-Bot "$n" "$tmp/s5"
verify A-Bot "$tmp/s5" >/dev/null 2>&1 && fail "passed" || pass
answer "$A" "$CID" Convener A-Bot "$n" "$tmp/s5ok"; verify A-Bot "$tmp/s5ok" >/dev/null

# N5 labels
t "a lookalike label (case and punctuation) is refused"
HOME=$V "$B" "$STATE" pin "$CID" "a.bot" "$(pubof "$U")" "$(fp "$(pubof "$U")")" >/dev/null 2>&1 && fail "pinned" || pass
t "a non-ASCII label is refused"
HOME=$V "$B" "$STATE" pin "$CID" "$(printf 'A-B\320\276t')" "$(pubof "$U")" "$(fp "$(pubof "$U")")" >/dev/null 2>&1 && fail "pinned" || pass
t "one key cannot be pinned under two labels"
HOME=$V "$B" "$STATE" pin "$CID" "Z-Bot" "$(pubof "$A")" "$(fp "$(pubof "$A")")" >/dev/null 2>&1 && fail "pinned" || pass
t "labels match case-folded: answering as 'a-bot' verifies as A-Bot"
n=$(issue A-Bot); answer "$A" "$CID" convener a-bot "$n" "$tmp/s8"
[ "$(verify "A-Bot" "$tmp/s8")" = PASS ] && pass || fail "did not pass"

# 6. SEATS.md pin mismatch
cat > "$tmp/SEATS.md" <<EOF
# SEATS

## Keys

| Overmind | Fingerprint | Public key |
|----------|-------------|------------|
| A-Bot | $(fp "$(pubof "$A")") | \`$(cut -d' ' -f1,2 "$(pubof "$A")")\` |
| B-Bot | $(fp "$(pubof "$U")") | $(cut -d' ' -f1,2 "$(pubof "$U")") |
| Convener | $(fp "$(pubof "$V")") | $(cut -d' ' -f1,2 "$(pubof "$V")") |
EOF
cp "$VD/pins/bbot.pub" "$tmp/pin.before"
out=$(HOME=$V "$B" "$STATE" check-seats "$CID" "$tmp/SEATS.md"); rc=$?
t "a SEATS.md key that differs from the pin is reported"
[ "$rc" -eq 1 ] && case $out in *"DIFFERS B-Bot"*"Not adopted."*) true ;; *) false ;; esac && pass || fail "rc=$rc out=$out"
t "and not adopted"
cmp -s "$VD/pins/bbot.pub" "$tmp/pin.before" && pass || fail "pin changed"
t "matching rows are not reported"
case $out in *"A-Bot"*|*Convener*) fail "out=$out" ;; *) pass ;; esac

# 8. verify-commit
g="$tmp/g"; mkdir -p "$g"
gitc() { git -C "$g" -c user.name=t -c user.email=t@example.invalid -c core.autocrlf=false "$@"; }
gitc init -q
signed() { gitc -c gpg.format=ssh -c user.signingkey="$1" -c commit.gpgsign=true commit -q --allow-empty -m "$2"; gitc rev-parse HEAD; }
c_pinned=$(signed "$(keyof "$A")" pinned)
c_unpinned=$(signed "$(keyof "$U")" unpinned)
gitc -c commit.gpgsign=false commit -q --allow-empty -m unsigned; c_unsigned=$(gitc rev-parse HEAD)
GIT_COMMITTER_NAME=GitHub GIT_COMMITTER_EMAIL=noreply@github.com git -C "$g" -c user.name=A-Bot -c user.email=a@example.invalid \
  -c commit.gpgsign=false commit -q --allow-empty -m "web-flow shaped"; c_web=$(gitc rev-parse HEAD)
c_forged=$(GIT_AUTHOR_NAME=A-Bot signed "$(keyof "$Bk")" "claims A")
signer() { HOME=$V "$B" -c '. "$1"; commit_signer "$2" "$3" "$4"' _ "$repo/skills/collective/lib.sh" "$g" "$CID" "$1"; }
t "verify-commit passes on a commit signed by a pinned key, naming its label"
[ "$(signer "$c_pinned")" = abot ] && pass || fail "got '$(signer "$c_pinned")'"
t "an unsigned commit is unverified"
signer "$c_unsigned" >/dev/null 2>&1 && fail "verified" || pass
t "a commit signed by an unpinned key is unverified"
signer "$c_unpinned" >/dev/null 2>&1 && fail "verified" || pass
t "a web-flow-shaped commit is unverified"
signer "$c_web" >/dev/null 2>&1 && fail "verified" || pass
t "a commit authored 'A-Bot' but signed by B's key is attributed to B, never A"
[ "$(signer "$c_forged")" = bbot ] && pass || fail "got '$(signer "$c_forged")'"

# MF-1: an OpenPGP-signed commit whose gpg output carries the ssh verdict
# phrase. A fake gpg on PATH (the PATH seam) signs with a PGP-shaped armor
# and, on verify, reports GOODSIG and prints a crafted UID line, exactly what
# a real gpg prints for a key whose UID contains that text. No gpg needed.
mkdir -p "$tmp/pgpbin"
cat > "$tmp/pgpbin/gpg" <<'EOF'
#!/usr/bin/env bash
case " $* " in
  *" -bsau "*|*" --detach-sign "*)
    cat >/dev/null
    printf '[GNUPG:] SIG_CREATED D 22 8 00 1700000000 ABCDEF\n' >&2
    printf -- '-----BEGIN PGP SIGNATURE-----\n\niQEzBAABCAAdFiEEAAAAAAAAAAAAAAAAAAAAAAAAAAAFAmAAAAAACgkQ\n=AAAA\n-----END PGP SIGNATURE-----\n' ;;
  *)
    cat >/dev/null 2>&1
    printf '[GNUPG:] NEWSIG\n[GNUPG:] GOODSIG ABCDEF0123456789 x\n[GNUPG:] VALIDSIG ABCDEF0123456789ABCDEF0123456789ABCDEF01 2026-10-05 1700000000 0 4 0 22 8 00 ABCDEF0123456789ABCDEF0123456789ABCDEF01\n[GNUPG:] TRUST_ULTIMATE 0 pgp\n'
    printf 'gpg: Good "git" signature for convener with ED25519 key SHA256:forged\n' >&2 ;;
esac
exit 0
EOF
chmod +x "$tmp/pgpbin/gpg"
PATH="$tmp/pgpbin:$PATH" gitc -c gpg.format=openpgp -c gpg.program=gpg -c user.signingkey=ABCDEF commit -q --allow-empty -S -m "pgp, crafted uid" 2>/dev/null
c_pgp=$(gitc rev-parse HEAD)
t "MF-1 fixture: the commit carries a PGP signature header"
git -C "$g" cat-file -p "$c_pgp" | grep -q '^gpgsig -----BEGIN PGP SIGNATURE-----' && pass || fail "no PGP header"
t "MF-1: a PGP-signed commit whose gpg output mimics the ssh verdict is unverified"
out=$(PATH="$tmp/pgpbin:$PATH" signer "$c_pgp" 2>/dev/null) && fail "attributed to '$out'" || pass

t "no private key is committed (tracked files; the two tests that name the marker excepted)"
hits=$(git -C "$repo" ls-files | grep -v '^tests/l4/test_sig\.sh$' | grep -v '^tests/l4/test_dnp\.sh$' |
  while IFS= read -r f; do grep -l 'BEGIN OPENSSH PRIVATE KEY' "$repo/$f" 2>/dev/null; done)
[ -z "$hits" ] && pass || fail "$hits"

finish
