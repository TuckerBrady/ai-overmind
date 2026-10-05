#!/usr/bin/env bash
# tests/l4/test_post_name.sh: naming and catchup order (CONTRACT 5.8, 5.9;
# COL-9, COL-12, COL-13). A far-future name is ignored for naming; a
# back-dated name is still caught; git catchup lists added, modified and
# renamed posts from the private ack and refuses a rewritten history.
# The clock is a fake `date` on PATH (the PATH seam), so results are exact.
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

mkdir -p "$tmp/bin"
cat > "$tmp/bin/date" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "+%Y%m%d%H%M" ] && [ -n "${FAKE_NOW:-}" ]; then echo "$FAKE_NOW"; exit 0; fi
for d in /usr/bin /bin; do [ -x "$d/date" ] && exec "$d/date" "$@"; done
exit 1
EOF
chmod +x "$tmp/bin/date"
P="$tmp/bin:$PATH"
name() { FAKE_NOW=$1 PATH=$P "$B" "$POSTNAME" "$tmp/posts" t-bot "$2" "$3" 2>"$tmp/err"; }

mkdir -p "$tmp/posts"
t "empty posts/: the name is this clock"
[ "$(name 202612312355 INFO hello)" = "20261231-2355-t-bot--INFO-hello.md" ] && pass || fail "$(name 202612312355 INFO hello)"

: > "$tmp/posts/20261231-2358-peer--STAT-x.md"
t "a newest post 3 minutes ahead counts: newest + 1 minute"
[ "$(name 202612312355 ASK q)" = "20261231-2359-t-bot--ASK-q.md" ] && pass || fail "$(name 202612312355 ASK q)"

: > "$tmp/posts/20261231-2359-peer--STAT-y.md"
t "minute arithmetic carries across the year"
[ "$(name 202612312355 ASK q)" = "20270101-0000-t-bot--ASK-q.md" ] && pass || fail "$(name 202612312355 ASK q)"

: > "$tmp/posts/20270115-0900-skewed--STAT-z.md"
t "a far-future post is ignored for naming"
[ "$(name 202612312355 ASK q)" = "20270101-0000-t-bot--ASK-q.md" ] && pass || fail "$(name 202612312355 ASK q)"
t "and flagged"
grep -q '^FUTURE 20270115-0900-skewed--STAT-z.md' "$tmp/err" && pass || fail "$(cat "$tmp/err")"

: > "$tmp/posts/20200101-0000-old--STAT-w.md"
t "a back-dated post does not move the name"
[ "$(name 202612312355 ASK q)" = "20270101-0000-t-bot--ASK-q.md" ] && pass || fail "moved"
t "a later clock wins over every post"
[ "$(name 202702280930 DEC d)" = "20270228-0930-t-bot--DEC-d.md" ] && pass || fail "$(name 202702280930 DEC d)"
t "leap day: 2028-02-28 23:59 + 1 minute = 2028-02-29 00:00"
rm -f "$tmp/posts"/*; : > "$tmp/posts/20280228-2359-peer--STAT-l.md"
[ "$(name 202802282350 INFO l)" = "20280229-0000-t-bot--INFO-l.md" ] && pass || fail "$(name 202802282350 INFO l)"
t "bad author or slug is refused"
FAKE_NOW=202612312355 PATH=$P "$B" "$POSTNAME" "$tmp/posts" 'T Bot' INFO x >/dev/null 2>&1 && fail "accepted" || pass

# --- synced-folder catchup: set membership, no filename floor (COL-13)
mkdir -p "$tmp/f/posts"
for p in 20261001-1000-a--INFO-one 20261002-1000-b--INFO-two 20250101-0000-c--INFO-backdated 20261003-1000-d--INFO-new; do : > "$tmp/f/posts/$p.md"; done
cat > "$tmp/f/ledger.md" <<'EOF'
# LEDGER — me
**format:** 2

## Processed
floor: 20261002-1000-b--INFO-two
- 20261001-1000-a--INFO-one
- 20261002-1000-b--INFO-two
EOF
out=$(PATH=$P "$B" "$CATCHUP" folder "$tmp/f/posts" "$tmp/f/ledger.md" 2>/dev/null)
t "a back-dated post under the old floor is not dropped"
case $out in *"NEW 20250101-0000-c--INFO-backdated"*) pass ;; *) fail "out=$out" ;; esac
t "processed posts are not listed; new ones are"
case $out in *one*|*two*) fail "listed a processed post" ;; *"NEW 20261003-1000-d--INFO-new"*) pass ;; *) fail "out=$out" ;; esac

# --- git catchup from the private ack
cid=$CID
V=$(newhome sweeper) || exit 1
W=$(newhome writer) || exit 1     # a pinned peer that signs its posts
HOME=$V "$B" "$STATE" pin "$cid" Writer "$(pubof "$W")" "$(fp "$(pubof "$W")")" >/dev/null
rem="$tmp/remote.git"; git init -q --bare "$rem"
w="$tmp/w"; git clone -q "$rem" "$w" 2>/dev/null
gw() { git -C "$w" -c user.name=Writer -c user.email=w@example.invalid -c core.autocrlf=false \
  -c gpg.format=ssh -c user.signingkey="$(keyof "$W")" -c commit.gpgsign=true "$@"; }
mkdir -p "$w/posts"
printf 'one\n' > "$w/posts/20261001-1000-a--INFO-one.md"; gw add -A; gw commit -qm one
br=$(git -C "$w" symbolic-ref --short HEAD); gw push -q origin "$br" 2>/dev/null
g="$tmp/g"; git clone -q "$rem" "$g" 2>/dev/null
ack=$(git -C "$g" rev-parse HEAD)
HOME=$V "$B" "$STATE" ack "$cid" "$ack"
printf 'two\n' > "$w/posts/20250101-0000-b--INFO-backdated.md"; gw add -A; gw commit -qm two
printf 'one, quietly changed\n' > "$w/posts/20261001-1000-a--INFO-one.md"; gw add -A; gw commit -qm edit
gw mv posts/20250101-0000-b--INFO-backdated.md posts/20261005-0900-b--INFO-renamed.md; gw commit -qm rename
gw -c commit.gpgsign=false rm -q posts/20261001-1000-a--INFO-one.md; gw -c commit.gpgsign=false commit -qm "delete, unsigned"
# a merge commit: a side branch adds a post, merged with --no-ff
gw checkout -q -b side; printf 's\n' > "$w/posts/20261007-0000-s--INFO-side.md"; gw add -A; gw commit -qm side
gw checkout -q "$br"; gw merge -q --no-ff -m merge side
gw push -q origin "$br" 2>/dev/null
c2=$(gw rev-parse HEAD~4); c3=$(gw rev-parse HEAD~3); c4=$(gw rev-parse HEAD~2); c5=$(gw rev-parse HEAD~1); cm=$(gw rev-parse HEAD)
out=$(HOME=$V PATH=$P "$B" "$CATCHUP" git "$g" "$cid" 2>/dev/null); rc=$?
want=$(printf 'NEW %s verified:writer posts/20250101-0000-b--INFO-backdated.md\nEDITED %s verified:writer posts/20261001-1000-a--INFO-one.md\nEDITED %s verified:writer posts/20261005-0900-b--INFO-renamed.md renamed-from posts/20250101-0000-b--INFO-backdated.md\nDELETED %s unverified posts/20261001-1000-a--INFO-one.md\nNEW %s verified:writer posts/20261007-0000-s--INFO-side.md' "$c2" "$c3" "$c4" "$c5" "$cm")
t "git catchup fetches, fast-forwards, and lists A/M/R/D first-parent changes with signers"
[ "$rc" -eq 0 ] && [ "$out" = "$want" ] && pass || fail "rc=$rc got:
$out"
t "the clone fast-forwarded to the remote head"
[ "$(git -C "$g" rev-parse HEAD)" = "$cm" ] && pass || fail "HEAD not moved"
t "the shared ledger is not the cursor: a forged acked-commit in it changes nothing"
printf '**acked-commit:** %s\n' "$cm" > "$g/forged-ledger.md"
out2=$(HOME=$V PATH=$P "$B" "$CATCHUP" git "$g" "$cid" 2>/dev/null)
[ "$out2" = "$want" ] && pass || fail "output changed"

t "a force-push is reported as history rewritten and merged in by nothing (M2)"
HOME=$V "$B" "$STATE" ack "$cid" "$cm"
gw checkout -q --orphan rewritten; gw rm -rqf . ; mkdir -p "$w/posts"
printf 'x\n' > "$w/posts/20261006-0000-z--INFO-new.md"; gw add -A; gw commit -qm rewritten
gw push -q -f origin "rewritten:$br" 2>/dev/null
out=$(HOME=$V PATH=$P "$B" "$CATCHUP" git "$g" "$cid" 2>/dev/null); rc=$?
[ "$rc" -eq 3 ] && [ "$out" = "history rewritten" ] && pass || fail "rc=$rc out=$out"
t "the local clone did not move and nothing rewritten is listed"
[ "$(git -C "$g" rev-parse HEAD)" = "$cm" ] && [ ! -e "$g/posts/20261006-0000-z--INFO-new.md" ] && pass || fail "clone moved"
t "a local commit not on the remote is also not merged around"
HOME=$V "$B" "$STATE" ack "$cid" "$cm"
git -C "$g" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q --allow-empty -m local
HOME=$V PATH=$P "$B" "$CATCHUP" git "$g" "$cid" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 3 ] && pass || fail "rc=$rc"
t "no private ack: catchup refuses rather than guess"
HOME=$(newhome noack) PATH=$P "$B" "$CATCHUP" git "$g" "$cid" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 3 ] && pass || fail "rc=$rc"

# --- the skill text carries the rules
sk="$repo/skills/collective/SKILL.md"; rf="$repo/reference/collective.md"
t "skill text: AMRD, first-parent, EDITED, DELETED, fetch + ff-only, history rewritten, act on nothing rewritten"
grep -q -- '--diff-filter=AMRD' "$sk" && grep -q -- '--first-parent' "$sk" && grep -q 'EDITED' "$sk" && grep -q 'DELETED' "$sk" &&
  grep -q -- '--ff-only' "$sk" && grep -q 'history rewritten' "$sk" &&
  grep -q 'act on nothing from the rewritten range' "$sk" && pass || fail "missing"
t "the sweep snippet carries the same rules"
grep -q -- '--diff-filter=AMRD' "$rf" && grep -q 'fast-forwards only' "$rf" && grep -q 'DELETED' "$rf" && grep -q 'history rewritten' "$rf" && pass || fail "missing"
t "no remaining instruction uses --diff-filter=A alone, or a plain pull"
grep -n -- '--diff-filter=A[^M]' "$sk" "$rf" "$repo/skills/assimilate/SKILL.md" >/dev/null && fail "diff-filter=A" || pass

finish
