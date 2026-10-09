#!/usr/bin/env bash
# tests/l4/test_pin_github.sh: pinning a peer's key from its GitHub signing
# keys, and publishing this Overmind's key there (OPS-032). gh and curl are
# PATH shims (the PATH seam); nothing here reaches the network. Keys are
# generated at test time.
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

V=$(newhome verifier) || exit 1      # verifier, label "Convener"
A=$(newhome alpha) || exit 1         # peer "A-Bot", GitHub user alice
X=$(newhome other) || exit 1         # an unrelated key
VD=$(sdir "$V")
AK=$(pubof "$A"); XK=$(pubof "$X"); VK=$(pubof "$V")
body() { cut -d' ' -f1,2 "$1"; }
ssh-keygen -q -t rsa -b 2048 -N "" -C rsa -f "$tmp/rsa" </dev/null >/dev/null 2>&1 || { echo "cannot make an rsa key"; exit 1; }
RK="$tmp/rsa.pub"

# --- shims ---------------------------------------------------------------------
# gh and curl read their behaviour from files under $tmp/ctl and log every
# call to $tmp/gh.log and $tmp/curl.log.
S="$tmp/shim"; mkdir -p "$S" "$tmp/ctl"
cat > "$S/gh" <<'EOF'
#!/usr/bin/env bash
c="$SHIM_CTL"
printf '%s\n' "$*" >> "$c/../gh.log"
case " $* " in
  *" users/"*)
    [ -f "$c/gh_fail" ] && { echo "HTTP 502: Bad Gateway" >&2; exit 1; }
    cat "$c/peer.json"; exit 0 ;;
  *" user/ssh_signing_keys"*)
    [ -f "$c/gh_noscope" ] && {
      printf 'HTTP 404: Not Found (https://api.github.com/user/ssh_signing_keys?per_page=100)\nThis API operation needs the "admin:ssh_signing_key" scope. To request it, run:  gh auth refresh -h github.com -s admin:ssh_signing_key\n' >&2
      exit 1; }
    cat "$c/own.json"; exit 0 ;;
  *" ssh-key add "*)
    [ -f "$c/gh_add_noscope" ] && { echo 'HTTP 404: Not Found (https://api.github.com/user/ssh_signing_keys)' >&2; exit 1; }
    printf '%s\n' "$3" > "$c/added"; exit 0 ;;
  *" user ")
    printf '{"login":"tester","id":1}\n'; exit 0 ;;
esac
echo "gh shim: unexpected: $*" >&2; exit 1
EOF
cat > "$S/curl" <<'EOF'
#!/usr/bin/env bash
c="$SHIM_CTL"
printf '%s\n' "$*" >> "$c/../curl.log"
[ -f "$c/curl_fail" ] && { echo "curl: (22) The requested URL returned error: 404" >&2; exit 22; }
cat "$c/peer.json"
EOF
chmod +x "$S/gh" "$S/curl"
export SHIM_CTL="$tmp/ctl"

# A PATH with no gh at all: wrappers for the tools the scripts use, plus the
# curl shim. Used for the "gh absent" cases.
M="$tmp/nogh"; mkdir -p "$M"
for tool in bash env cat mv rm mkdir mktemp tr cut grep head sed wc sleep uname ssh-keygen od date chmod ls dirname sort; do
  p=$(command -v "$tool") || continue
  printf '#!%s\nexec "%s" "$@"\n' "$B" "$p" > "$M/$tool"; chmod +x "$M/$tool"
done
cp "$S/curl" "$M/curl"
WITH="$S:$PATH"; NOGH="$M"

reset_ctl() { rm -f "$tmp/ctl"/* "$tmp/gh.log" "$tmp/curl.log"; : > "$tmp/gh.log"; : > "$tmp/curl.log"; }
# keylist FILE KEYFILE...: a GitHub-shaped JSON array; a KEYFILE of the form
# path:comment appends that comment to the key text.
keylist() {
  local out=$1 i=0 f c sep=""
  shift
  {
    printf '[\n'
    for f in "$@"; do
      i=$(( i + 1 )); c=""
      case $f in *:*) c=" ${f##*:}"; f=${f%:*} ;; esac
      printf '%s  {\n    "key": "%s%s",\n    "id": %s,\n    "url": "https://api.github.com/user/ssh_signing_keys/%s",\n    "title": "key %s",\n    "created_at": "2026-10-01T00:00:00Z"\n  }' "$sep" "$(body "$f")" "$c" "$i" "$i" "$i"
      sep=",
"
    done
    printf '\n]\n'
  } > "$out"
}
peer() { keylist "$tmp/ctl/peer.json" "$@"; }
own() { keylist "$tmp/ctl/own.json" "$@"; }

pg() { HOME=$V PATH=$WITH "$B" "$STATE" pin-github "$@"; }          # cid label pub user
pins_snap() { { ls -la "$VD/pins" 2>/dev/null | awk '{print $NF, $5}'; cat "$VD"/pins/* 2>/dev/null; } | cksum; }
# refused NAME RC-EXPECTED CMD...: the command exits RC-EXPECTED (or any
# non-zero when "nz") and the pins dir is byte-identical afterwards.
refused() {
  local nm=$1 want=$2 before after rc
  shift 2
  t "$nm"
  before=$(pins_snap)
  "$@" >"$tmp/out" 2>&1; rc=$?
  after=$(pins_snap)
  if [ "$rc" -eq 0 ]; then fail "exit 0: $(cat "$tmp/out")"; return; fi
  if [ "$want" != nz ] && [ "$rc" -ne "$want" ]; then fail "exit $rc, wanted $want: $(cat "$tmp/out")"; return; fi
  [ "$before" = "$after" ] && pass || fail "pins changed"
}

HOME=$V "$B" "$STATE" pin-self "$CID" Convener >/dev/null

# --- 1. pins on a match ----------------------------------------------------------
reset_ctl
peer "$XK" "$RK" "$AK:alice-laptop" "$VK"
t "pin-github pins a key found in a multi-key list whose comment differs"
out=$(pg "$CID" A-Bot "$AK" alice 2>&1) && case $out in "pinned: A-Bot $(fp "$AK")") pass ;; *) fail "out=$out" ;; esac || fail "exit: $out"
t "the fetch went to gh api for that user on github.com"
grep -q -- '--hostname github.com .*users/alice/ssh_signing_keys?per_page=100' "$tmp/gh.log" && pass || fail "$(cat "$tmp/gh.log")"
t "pins/<n>.source records github:<user>"
[ "$(cat "$VD/pins/abot.source")" = "github:alice" ] && pass || fail "$(cat "$VD/pins/abot.source" 2>&1)"
t "the pin holds exactly the key body"
[ "$(cat "$VD/pins/abot.pub")" = "$(body "$AK")" ] && pass || fail "pin body differs"
t "allowed_signers carries the new pin"
grep -qF "abot namespaces=\"git,ai-overmind-collective\" $(body "$AK")" "$VD/allowed_signers" && pass || fail "missing"
t "the event log says pinned <label> via github:<user> <fp>"
grep -qF "pinned A-Bot via github:alice $(fp "$AK")" "$VD/events" && pass || fail "$(tail -2 "$VD/events")"
t "pins shows the source column"
p=$(HOME=$V "$B" "$STATE" pins "$CID")
printf '%s\n' "$p" | grep -qF "$(printf 'A-Bot\t%s\tgithub:alice' "$(fp "$AK")")" &&
  printf '%s\n' "$p" | grep -qF "$(printf 'Convener\t%s\tself' "$(fp "$VK")")" && pass || fail "$p"
t "pinning the same key under the same label again is a no-op"
out=$(pg "$CID" A-Bot "$AK" alice 2>&1) && case $out in "already pinned: A-Bot"*) pass ;; *) fail "$out" ;; esac || fail "$out"

t "a fingerprint pin shows source oob"
HOME=$V "$B" "$STATE" pin "$CID2" O-Bot "$XK" "$(fp "$XK")" >/dev/null
HOME=$V "$B" "$STATE" pins "$CID2" | grep -qF "$(printf 'O-Bot\t%s\toob' "$(fp "$XK")")" && pass || fail "$(HOME=$V "$B" "$STATE" pins "$CID2")"
t "a pin written before OPS-032 (no .source file) shows oob"
rm -f "$(sdir "$V" "$CID2")/pins/obot.source"
HOME=$V "$B" "$STATE" pins "$CID2" | grep -qF "$(printf 'O-Bot\t%s\toob' "$(fp "$XK")")" && pass || fail "no oob"
t "unpin removes the .source file"
HOME=$V PATH=$WITH "$B" "$STATE" pin-github "$CID2" Q-Bot "$AK" alice >/dev/null 2>&1 &&
  HOME=$V "$B" "$STATE" unpin "$CID2" Q-Bot >/dev/null && [ ! -e "$(sdir "$V" "$CID2")/pins/qbot.source" ] && pass || fail "source left behind"

# gh failing (not signed in, rate limit) falls back to curl.
CID3=0123456789abcdef0123456789abcdef
reset_ctl; peer "$AK"; : > "$tmp/ctl/gh_fail"
t "gh failing falls back to curl, which pins"
HOME=$V PATH=$WITH "$B" "$STATE" pin-github "$CID3" A-Bot "$AK" alice >/dev/null 2>&1 && pass || fail "not pinned"
t "curl was called on https://api.github.com with a size cap and timeout"
grep -q -- "--proto =https .*--max-time .*--max-filesize 262144 .*https://api.github.com/users/alice/ssh_signing_keys?per_page=100" "$tmp/curl.log" && pass || fail "$(cat "$tmp/curl.log")"
CID4=abcdef0123456789abcdef0123456789
reset_ctl; peer "$AK"
t "with no gh on PATH, curl alone pins"
HOME=$V PATH=$NOGH "$B" "$STATE" pin-github "$CID4" A-Bot "$AK" alice >/dev/null 2>&1 && [ -s "$tmp/curl.log" ] && pass || fail "not pinned"

t "no env var redirects the fetch (GH_HOST, a proxy-looking API var are ignored)"
reset_ctl; peer "$AK"; : > "$tmp/ctl/gh_fail"
CID5=5555555555555555aaaaaaaaaaaaaaaa
HOME=$V PATH=$WITH GH_HOST=evil.example GITHUB_API_URL=https://evil.example GH_API=https://evil.example \
  "$B" "$STATE" pin-github "$CID5" A-Bot "$AK" alice >/dev/null 2>&1
! grep -q evil "$tmp/gh.log" "$tmp/curl.log" && grep -q -- '--hostname github.com' "$tmp/gh.log" &&
  grep -q 'https://api.github.com/users/alice/' "$tmp/curl.log" && pass || fail "redirected"
t "production code names no env var for the GitHub host or URL"
hits=$(grep -nE 'api\.github\.com|--hostname' "$repo/skills/collective/lib.sh" "$repo/skills/collective/state.sh" "$repo/skills/assimilate/identity.sh" | grep -E '\$\{?[A-Za-z_]*(HOST|URL|API|BASE)')
[ -z "$hits" ] && pass || fail "$hits"

# --- 2. refusals: nothing is pinned ----------------------------------------------
B2=$(newhome beta) || exit 1; BK=$(pubof "$B2")
reset_ctl; peer "$XK" "$RK" "$VK"
refused "refuses a key absent from the user's signing keys" 1 pg "$CID" B-Bot "$BK" bob
t "and says why"
grep -q "REFUSED: key not among bob's GitHub signing keys" "$tmp/out" && pass || fail "$(cat "$tmp/out")"

mkdir -p "$tmp/binder/posts"
printf '## Keys\n\n| Overmind | Fingerprint | Public key |\n|---|---|---|\n| B-Bot | %s | %s |\n' "$(fp "$BK")" "$(body "$BK")" > "$tmp/binder/SEATS.md"
printf 'hello\n\n```\n%s\n%s\n```\n' "$(body "$BK")" "$(fp "$BK")" > "$tmp/binder/posts/202610080000-bbot-hello.md"
refused "refuses a key that appears only in SEATS.md and a post, not on GitHub" 1 pg "$CID" B-Bot "$BK" bob

reset_ctl; printf '[]\n' > "$tmp/ctl/peer.json"
refused "refuses an empty key list" 1 pg "$CID" B-Bot "$BK" bob
reset_ctl; peer "$RK"
refused "refuses a list holding only non-ed25519 keys" 1 pg "$CID" B-Bot "$BK" bob

reset_ctl; peer "$BK"; : > "$tmp/ctl/gh_fail"; : > "$tmp/ctl/curl_fail"
refused "refuses when gh and curl both fail (the key is listed, the fetch is not)" 1 pg "$CID" B-Bot "$BK" bob
t "and both were tried"
[ -s "$tmp/gh.log" ] && [ -s "$tmp/curl.log" ] && pass || fail "gh=$(wc -l < "$tmp/gh.log") curl=$(wc -l < "$tmp/curl.log")"
reset_ctl; peer "$BK"; : > "$tmp/ctl/curl_fail"
refused "refuses when gh is absent and curl fails" 1 env HOME="$V" PATH="$NOGH" "$B" "$STATE" pin-github "$CID" B-Bot "$BK" bob

reset_ctl; printf '{"message":"Not Found","key":"%s"}\n' "$(body "$BK")" > "$tmp/ctl/peer.json"
refused "refuses a JSON object instead of a list (malformed)" 1 pg "$CID" B-Bot "$BK" bob
reset_ctl; printf '[{"key":"%s","id":1' "$(body "$BK")" > "$tmp/ctl/peer.json"
refused "refuses a truncated list (malformed)" 1 pg "$CID" B-Bot "$BK" bob
reset_ctl; printf '<html>%s</html>\n' "$(body "$BK")" > "$tmp/ctl/peer.json"
refused "refuses an HTML page (malformed)" 1 pg "$CID" B-Bot "$BK" bob
reset_ctl; : > "$tmp/ctl/peer.json"
refused "refuses an empty body" 1 pg "$CID" B-Bot "$BK" bob
reset_ctl; peer "$BK"
{ printf '[\n'; i=0; while [ $i -lt 3000 ]; do printf '{"title":"%0100d"},\n' 0; i=$(( i + 1 )); done; tail -n +2 "$tmp/ctl/peer.json"; } > "$tmp/big.json"
mv "$tmp/big.json" "$tmp/ctl/peer.json"
refused "refuses a body over 256 KiB even when the key is in it" 1 pg "$CID" B-Bot "$BK" bob

reset_ctl; printf '[{"key":"%sAAAA","id":1}]\n' "$(body "$BK")" > "$tmp/ctl/peer.json"
refused "refuses a listed key that only starts with the key (exact match only)" 1 pg "$CID" B-Bot "$BK" bob
reset_ctl; printf '[{"title":"\\"key\\": \\"%s\\"","key":"%s","id":1}]\n' "$(body "$BK")" "$(body "$XK")" > "$tmp/ctl/peer.json"
refused "refuses a key that appears only inside another field's text" 1 pg "$CID" B-Bot "$BK" bob

reset_ctl; peer "$BK"
long=$(printf 'a%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40)
for u in '../x' '-x' 'x-' 'a b' "$long" '' 'a/b' 'a?x=1' 'a_b' "$(printf 'a\nb')"; do
  : > "$tmp/gh.log"; : > "$tmp/curl.log"
  refused "refuses the user name '$u' (exit 2)" 2 pg "$CID" B-Bot "$BK" "$u"
  t "and fetches nothing for '$u'"
  [ ! -s "$tmp/gh.log" ] && [ ! -s "$tmp/curl.log" ] && pass || fail "fetched"
done
t "accepts a 39-character user name and one with an inner double dash"
reset_ctl; peer "$BK" "$XK"
u39=${long%?}
CID6=6666666666666666bbbbbbbbbbbbbbbb
pg "$CID6" B-Bot "$BK" "$u39" >/dev/null 2>&1 && pg "$CID6" Y-Bot "$XK" "a--b" >/dev/null 2>&1 && pass || fail "rejected"

reset_ctl; peer "$RK"
refused "refuses a non-ed25519 public key file even when GitHub lists it" 2 pg "$CID" R-Bot "$RK" bob
refused "refuses a bad label before fetching" 2 pg "$CID" "B|Bot" "$BK" bob

# --- 3. the existing refusals hold through pin-github ------------------------------
reset_ctl; peer "$XK" "$AK" "$BK"
refused "lookalike label (a.bot vs A-Bot) is refused" 1 pg "$CID" a.bot "$XK" alice
refused "a key already pinned under another label is refused" 1 pg "$CID" Z-Bot "$AK" alice
refused "a different key for an already-pinned label is refused" 1 pg "$CID" A-Bot "$XK" alice

# --- 5. publish-github ---------------------------------------------------------------
pub() { HOME=$1 PATH=$2 "$B" "$ID" publish-github; }
reset_ctl; printf '[]\n' > "$tmp/ctl/own.json"
t "publish-github adds the public key as a signing key"
out=$(pub "$A" "$WITH" 2>&1) && case $out in "published: $(fp "$AK") as an SSH signing key on GitHub account tester") pass ;; *) fail "$out" ;; esac || fail "$out"
t "it passed only the .pub to gh ssh-key add, as a signing key with the collective title"
[ "$(cat "$tmp/ctl/added")" = "$AK" ] && grep -q -- "ssh-key add $AK --type signing --title ai-overmind collective (" "$tmp/gh.log" && pass || fail "$(cat "$tmp/gh.log")"
t "no gh call names the private key path"
! grep -E "id_ed25519( |$)" "$tmp/gh.log" >/dev/null && pass || fail "$(cat "$tmp/gh.log")"

reset_ctl; own "$XK" "$AK:ai-overmind-collective"
t "publish-github is idempotent: an already-published key prints already published, exit 0"
out=$(pub "$A" "$WITH" 2>&1) && case $out in "already published: $(fp "$AK")") pass ;; *) fail "$out" ;; esac || fail "$out"
t "and adds nothing"
[ ! -e "$tmp/ctl/added" ] && ! grep -q 'ssh-key add' "$tmp/gh.log" && pass || fail "added"

FIX='gh auth refresh -h github.com -s admin:ssh_signing_key'
reset_ctl; : > "$tmp/ctl/gh_noscope"
t "publish-github exits 4 with the exact scope fix when gh lacks the scope"
pub "$A" "$WITH" >"$tmp/out" 2>&1; rc=$?
[ "$rc" -eq 4 ] && grep -qF "$FIX" "$tmp/out" && [ ! -e "$tmp/ctl/added" ] && pass || fail "rc=$rc $(cat "$tmp/out")"
reset_ctl; printf '[]\n' > "$tmp/ctl/own.json"; : > "$tmp/ctl/gh_add_noscope"
t "publish-github exits 4 with the exact scope fix when the add is refused for scope"
pub "$A" "$WITH" >"$tmp/out" 2>&1; rc=$?
[ "$rc" -eq 4 ] && grep -qF "$FIX" "$tmp/out" && pass || fail "rc=$rc $(cat "$tmp/out")"
reset_ctl
t "publish-github exits 4 with the exact scope fix when gh is absent"
pub "$A" "$NOGH" >"$tmp/out" 2>&1; rc=$?
[ "$rc" -eq 4 ] && grep -qF "$FIX" "$tmp/out" && [ ! -s "$tmp/gh.log" ] && pass || fail "rc=$rc $(cat "$tmp/out")"
t "publish-github with no key exits 3"
mkdir -p "$tmp/home-empty"
pub "$tmp/home-empty" "$WITH" >/dev/null 2>&1; [ $? -eq 3 ] && pass || fail "not 3"

t "publish-github never reads the private key (grep: its block names only \$k.pub)"
blk=$(tr -d '\r' < "$ID" | sed -n '/^  publish-github)/,/^    ;;/p')
[ -n "$blk" ] && ! printf '%s\n' "$blk" | grep -E '"\$k"|\$\{k\}|\$k([^.A-Za-z0-9_]|$)|\$k\.([^p]|$)|id_ed25519([^.]|$)' >/dev/null &&
  printf '%s\n' "$blk" | grep -q 'pub="\$k.pub"' && pass || fail "$(printf '%s\n' "$blk" | grep -nE '\$k([^.]|$)|id_ed25519')"

finish
