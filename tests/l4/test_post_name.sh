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
cid=$(vec collective_id)
V=$(newhome sweeper)
g="$tmp/g"; mkdir -p "$g/posts"
gitc() { git -C "$g" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false -c core.autocrlf=false "$@"; }
gitc init -q
printf 'one\n' > "$g/posts/20261001-1000-a--INFO-one.md"; gitc add -A; gitc commit -qm one
ack=$(gitc rev-parse HEAD)
HOME=$V "$B" "$STATE" ack "$cid" "$ack"
printf 'two\n' > "$g/posts/20250101-0000-b--INFO-backdated.md"; gitc add -A; gitc commit -qm two
printf 'one, quietly changed\n' > "$g/posts/20261001-1000-a--INFO-one.md"; gitc add -A; gitc commit -qm edit
gitc mv posts/20250101-0000-b--INFO-backdated.md posts/20261005-0900-b--INFO-renamed.md; gitc commit -qm rename
c2=$(gitc rev-parse HEAD~2); c3=$(gitc rev-parse HEAD~1); c4=$(gitc rev-parse HEAD)
out=$(HOME=$V PATH=$P "$B" "$CATCHUP" git "$g" "$cid" 2>/dev/null)
want=$(printf 'NEW %s posts/20250101-0000-b--INFO-backdated.md\nEDITED %s posts/20261001-1000-a--INFO-one.md\nEDITED %s posts/20261005-0900-b--INFO-renamed.md renamed-from posts/20250101-0000-b--INFO-backdated.md' "$c2" "$c3" "$c4")
t "git catchup lists added, modified and renamed posts in git order"
[ "$out" = "$want" ] && pass || fail "got:
$out"
t "the shared ledger is not the cursor: a forged acked-commit in it changes nothing"
printf '**acked-commit:** %s\n' "$c4" > "$g/ledger-forged.md"
out2=$(HOME=$V PATH=$P "$B" "$CATCHUP" git "$g" "$cid" 2>/dev/null)
[ "$out2" = "$want" ] && pass || fail "output changed"

t "history rewritten: the ack is not an ancestor of HEAD"
gitc checkout -q --orphan rewritten; gitc rm -rqf . ; mkdir -p "$g/posts"; printf 'x\n' > "$g/posts/20261006-0000-z--INFO-new.md"; gitc add -A; gitc commit -qm rewritten
out=$(HOME=$V PATH=$P "$B" "$CATCHUP" git "$g" "$cid" 2>/dev/null); rc=$?
[ "$rc" -eq 3 ] && [ "$out" = "history rewritten" ] && pass || fail "rc=$rc out=$out"
t "nothing from the rewritten range is listed"
case $out in *NEW*|*EDITED*) fail "listed rewritten posts" ;; *) pass ;; esac
t "no private ack: catchup refuses rather than guess"
HOME=$(newhome noack) PATH=$P "$B" "$CATCHUP" git "$g" "$cid" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 3 ] && pass || fail "rc=$rc"

# --- the skill text carries the rules
sk="$repo/skills/collective/SKILL.md"; rf="$repo/reference/collective.md"
t "skill text: --diff-filter=AMR, EDITED, history rewritten, act on nothing rewritten"
grep -q -- '--diff-filter=AMR' "$sk" && grep -q 'EDITED' "$sk" && grep -q 'history rewritten' "$sk" &&
  grep -q 'act on nothing from the rewritten range' "$sk" && pass || fail "missing"
t "the sweep snippet carries the same rules"
grep -q -- '--diff-filter=AMR' "$rf" && grep -q 'EDITED' "$rf" && grep -q 'history rewritten' "$rf" && pass || fail "missing"
t "no remaining instruction uses --diff-filter=A alone"
grep -n -- '--diff-filter=A[^M]' "$sk" "$rf" "$repo/skills/assimilate/SKILL.md" >/dev/null && fail "$(grep -n -- '--diff-filter=A[^M]' "$sk" "$rf")" || pass

finish
