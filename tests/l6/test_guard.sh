#!/usr/bin/env bash
# L6 6.9 / RUBRIC L6.2: the pre-archive guard. Exit codes 0 and 10-15, each
# against a real fixture git repo (a bare remote for the unpushed case, a fake
# gh for the PR and auth cases), plus "lowest failing code wins" (GAP-45).
set -u
here=$(cd "$(dirname "$0")" && pwd); repo=${here%/tests/l6}
ok=0; no=0; name=""
t() { name=$1; }
pass() { ok=$((ok+1)); }
fail() { no=$((no+1)); echo "  FAIL: $name: $1"; }
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ovm.XXXXXX"); trap 'rm -rf "$tmp"' EXIT
guard="$repo/skills/consolidate/guard.sh"
SB=${BASH:-bash}

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_CONFIG_NOSYSTEM=1 HOME="$tmp/home"; mkdir -p "$HOME"
git config --global init.defaultBranch main
git config --global core.autocrlf false
git config --global protocol.file.allow always

SID=local_1589a98d-aba5-4d0b-b537-0d7db91eb862
U1=11111111-2222-4333-8444-555555555555
U2=66666666-7777-4888-9999-aaaaaaaaaaaa
fold="$tmp/fold/AXM-046-20261004-2210.md"; mkdir -p "$tmp/fold"
mkfold() { # $1 = Result cell for the sibling row; $2 = the decision's Source
  {
    echo "# CONSOLIDATE AXM-046 20261004-2210"
    echo "ANCHOR: AXM-046 (consolidated 20261004-2210) (f8d87694)"
    echo "## Siblings"
    echo "| Session | Class | Fork point | Mode | Result |"
    echo "|---|---|---|---|---|"
    echo "| 1589a98d | DIVERGED | $U1 | Read | $1 |"
    echo "## Inventory in"
    echo "| Item | Kind | Source | Timestamp | Text |"
    echo "|---|---|---|---|---|"
    echo "| 1589a98d-D1 | DECISION | $2 | 2026-10-01T20:00:00Z | Use the repair model |"
    echo "| 1589a98d-Q1 | QUESTION | assistant:$U2 | 2026-10-01T20:05:00Z | Which face for Ilvara? |"
    echo "## Merged record"
    echo "| Item | Kind | Status | Text |"
    echo "|---|---|---|---|"
    echo "| 1589a98d-D1 | DECISION | CURRENT | Use the repair model |"
    echo "| 1589a98d-Q1 | QUESTION | CURRENT | Which face for Ilvara? |"
    echo "## Conflicts"
    echo "none"
    echo "## Close"
  } > "$fold"
}
mkfold "folded: 1 decisions, 0 files" "user:$U1"

# A worktree with a bare remote, fully pushed.
mkrepo() { # $1 dir
  git init -q --bare "$1.git"
  git init -q "$1"
  git -C "$1" remote add origin "$1.git"
  echo a > "$1/a.txt"; git -C "$1" add a.txt; git -C "$1" commit -qm init
  git -C "$1" push -q -u origin main 2>/dev/null
}

# "gh missing": a stub dir first on PATH whose gh exits 127, the shell's
# "command not found". Nothing is removed from PATH, so git and coreutils
# stay reachable wherever they live (on Ubuntu, /usr/bin also holds gh).
stub="$tmp/nogh"; mkdir -p "$stub"
printf '#!/usr/bin/env bash\nexit 127\n' > "$stub/gh"; chmod +x "$stub/gh"
np="$stub:$PATH"
fake="$tmp/fakebin"; mkdir -p "$fake"
{
  echo '#!/usr/bin/env bash'
  echo '# fake gh: answers from $FAKEGH/{auth_rc,prs,comments}'
  echo 'case "$1 $2" in'
  echo '  "auth status") exit "$(cat "$FAKEGH/auth_rc" 2>/dev/null || echo 0)" ;;'
  echo '  "pr list") cat "$FAKEGH/prs" 2>/dev/null; exit 0 ;;'
  echo '  "pr view") cat "$FAKEGH/comments" 2>/dev/null; exit 0 ;;'
  echo 'esac'
  echo 'exit 1'
} > "$fake/gh"
chmod +x "$fake/gh"
export FAKEGH="$tmp/fakegh"; mkdir -p "$FAKEGH"

run() { "$SB" "$guard" "$@" > "$tmp/out" 2>&1; echo $?; }
runp() { local p=$1; shift; PATH=$p "$SB" "$guard" "$@" > "$tmp/out" 2>&1; echo $?; }

reported() { LC_ALL=C grep -q "^guard: $1 " "$tmp/out"; }

wt="$tmp/wt"; mkrepo "$wt"

t "0 clean, pushed, folded"
rc=$(run --session "$SID" --running 0 --fold "$fold" --worktree "$wt")
[ "$rc" = 0 ] && pass || fail "rc=$rc $(cat "$tmp/out")"

t "0 no worktree at all (a session that never touched a repo)"
rc=$(run --session "$SID" --running 0 --fold "$fold")
[ "$rc" = 0 ] && pass || fail "rc=$rc"

t "10 running"
rc=$(run --session "$SID" --running 1 --fold "$fold" --worktree "$wt")
[ "$rc" = 10 ] && pass || fail "rc=$rc"

t "11 dirty: modified tracked file"
echo b >> "$wt/a.txt"
rc=$(run --session "$SID" --running 0 --fold "$fold" --worktree "$wt")
[ "$rc" = 11 ] && pass || fail "rc=$rc"
git -C "$wt" checkout -q -- a.txt

t "11 dirty: untracked file"
echo n > "$wt/new.txt"
rc=$(run --session "$SID" --running 0 --fold "$fold" --worktree "$wt")
[ "$rc" = 11 ] && pass || fail "rc=$rc"
rm -f "$wt/new.txt"

t "12 unpushed commit (bare remote behind); its file is 11 too"
w2="$tmp/w2"; mkrepo "$w2"
echo c > "$w2/c.txt"; git -C "$w2" add c.txt; git -C "$w2" commit -qm local
rc=$(run --session "$SID" --running 0 --fold "$fold" --worktree "$w2")
[ "$rc" = 11 ] && reported 12 && pass || fail "rc=$rc $(cat "$tmp/out")"

t "12 a branch never pushed anywhere"
w3="$tmp/w3"; mkrepo "$w3"
git -C "$w3" checkout -q -b feature; echo d > "$w3/d.txt"; git -C "$w3" add d.txt; git -C "$w3" commit -qm feat
rc=$(run --session "$SID" --running 0 --fold "$fold" --worktree "$w3")
[ "$rc" = 11 ] && reported 12 && pass || fail "rc=$rc"

t "12 clears once pushed"
git -C "$w2" push -q 2>/dev/null
rc=$(run --session "$SID" --running 0 --fold "$fold" --worktree "$w2")
[ "$rc" = 0 ] && pass || fail "rc=$rc $(cat "$tmp/out")"

# A GitHub upstream: point origin at github.com after the push, so the
# remote-tracking refs stay local and only the PR check needs gh.
gw="$tmp/gw"; mkrepo "$gw"
git -C "$gw" remote set-url origin https://github.com/acme/widgets.git

t "13 open PR with no comment naming the fold file"
echo 0 > "$FAKEGH/auth_rc"; echo 42 > "$FAKEGH/prs"; printf 'looks good\nmerge when ready\n' > "$FAKEGH/comments"
rc=$(runp "$fake:$np" --session "$SID" --running 0 --fold "$fold" --worktree "$gw")
[ "$rc" = 13 ] && pass || fail "rc=$rc $(cat "$tmp/out")"

t "13 clears when a PR comment names the fold basename"
printf 'Folded into the anchor: AXM-046-20261004-2210.md\n' > "$FAKEGH/comments"
rc=$(runp "$fake:$np" --session "$SID" --running 0 --fold "$fold" --worktree "$gw")
[ "$rc" = 0 ] && pass || fail "rc=$rc $(cat "$tmp/out")"

t "0 no open PR on the branch"
: > "$FAKEGH/prs"
rc=$(runp "$fake:$np" --session "$SID" --running 0 --fold "$fold" --worktree "$gw")
[ "$rc" = 0 ] && pass || fail "rc=$rc"

t "14 fold file missing"
rc=$(run --session "$SID" --running 0 --fold "$tmp/fold/none.md" --worktree "$wt")
[ "$rc" = 14 ] && pass || fail "rc=$rc"

t "14 no Siblings row for this session"
rc=$(run --session local_deadbeef-0000-4000-8000-000000000000 --running 0 --fold "$fold" --worktree "$wt")
[ "$rc" = 14 ] && pass || fail "rc=$rc"

t "14 recorded not folded"
mkfold "not folded (timed out)" "user:$U1"
rc=$(run --session "$SID" --running 0 --fold "$fold" --worktree "$wt")
[ "$rc" = 14 ] && pass || fail "rc=$rc"

t "14 the fold fails the invariant (assistant-sourced decision)"
mkfold "folded: 1 decisions, 0 files" "assistant:$U2"
rc=$(run --session "$SID" --running 0 --fold "$fold" --worktree "$wt")
[ "$rc" = 14 ] && pass || fail "rc=$rc"
mkfold "folded: 1 decisions, 0 files" "user:$U1"

t "15 gh missing with a GitHub upstream"
rc=$(runp "$np" --session "$SID" --running 0 --fold "$fold" --worktree "$gw")
[ "$rc" = 15 ] && LC_ALL=C grep -q 'gh missing' "$tmp/out" && pass || fail "rc=$rc $(cat "$tmp/out")"

t "15 gh unauthenticated with a GitHub upstream"
echo 1 > "$FAKEGH/auth_rc"; echo 42 > "$FAKEGH/prs"
rc=$(runp "$fake:$np" --session "$SID" --running 0 --fold "$fold" --worktree "$gw")
[ "$rc" = 15 ] && pass || fail "rc=$rc"
echo 0 > "$FAKEGH/auth_rc"

t "15 worktree path is not a git work tree"
mkdir -p "$tmp/plain"
rc=$(run --session "$SID" --running 0 --fold "$fold" --worktree "$tmp/plain")
[ "$rc" = 15 ] && pass || fail "rc=$rc"

t "0 gh is not needed without a GitHub upstream"
rc=$(runp "$np" --session "$SID" --running 0 --fold "$fold" --worktree "$wt")
[ "$rc" = 0 ] && pass || fail "rc=$rc"

t "lowest code wins: running + dirty + not folded -> 10"
echo z >> "$wt/a.txt"
rc=$(run --session "$SID" --running 1 --fold "$tmp/fold/none.md" --worktree "$wt")
[ "$rc" = 10 ] && pass || fail "rc=$rc"
git -C "$wt" checkout -q -- a.txt

t "lowest code wins: unpushed + gh missing + not folded -> 11"
echo e > "$gw/e.txt"; git -C "$gw" add e.txt; git -C "$gw" commit -qm e
rc=$(runp "$np" --session "$SID" --running 0 --fold "$tmp/fold/none.md" --worktree "$gw")
[ "$rc" = 11 ] && pass || fail "rc=$rc"

t "lowest code wins: every failing check is still reported"
n=$(LC_ALL=C grep -cE '^guard: (12|14|15) ' "$tmp/out")
[ "$n" -ge 3 ] && pass || fail "reported $n: $(cat "$tmp/out")"

t "a repo config cannot make status run a program (core.fsmonitor)"
w4="$tmp/w4"; mkrepo "$w4"
git -C "$w4" config core.fsmonitor "touch '$tmp/pwned'; false"
run --session "$SID" --running 0 --fold "$fold" --worktree "$w4" > /dev/null
[ ! -e "$tmp/pwned" ] && pass || fail "the fsmonitor command ran"

# A filter driver named by .gitattributes runs during "git status". The guard
# must not inspect such a repo at all: exit 15, and the payload never runs.
mkfilter() { # $1 dir, $2 where the filter is defined: local | include
  mkrepo "$1"
  case $2 in
    local) git -C "$1" config filter.evil.clean "touch '$tmp/pwned-$2'; cat" ;;
    include)
      git config --file "$1/.git/extra.cfg" filter.evil.clean "touch '$tmp/pwned-$2'; cat"
      git -C "$1" config include.path extra.cfg ;;
  esac
  echo '* filter=evil' > "$1/.gitattributes"
  git -C "$1" -c filter.evil.clean=cat add .gitattributes
  git -C "$1" -c filter.evil.clean=cat commit -qm attrs
  git -C "$1" -c filter.evil.clean=cat push -q 2>/dev/null
  touch -t 202901010000 "$1/a.txt"   # same content, new mtime: status must hash it through the filter
}
for where in local include; do
  t "repo filter driver ($where config): the payload never runs; same content is recoverable -> 0"
  w5="$tmp/w5-$where"; mkfilter "$w5" "$where"
  rc=$(run --session "$SID" --running 0 --fold "$fold" --worktree "$w5")
  [ "$rc" = 0 ] && [ ! -e "$tmp/pwned-$where" ] && pass ||
    fail "rc=$rc pwned=$([ -e "$tmp/pwned-$where" ] && echo yes || echo no) $(cat "$tmp/out")"
done
for where in local include; do
  t "positive control: plain git status in the $where repo does run the filter"
  ( cd "$tmp/w5-$where" && git status --porcelain > /dev/null 2>&1 )
  [ -e "$tmp/pwned-$where" ] && pass || fail "the fixture filter never fires, so the case above proves nothing"
done

# --- the security reviewer's attack corpus (L6 r2) ---------------------------------
# Work that archiving would delete must stop the archive; a repo must not be
# able to make the guard run a program. Each case is the reviewer's, by id.
pwn="$tmp/PWNED"
mkpay() { printf '#!/bin/sh\necho %s >> "%s"\ncat\n' "$1" "$pwn" > "$tmp/pay_$1.sh"; chmod +x "$tmp/pay_$1.sh"; }
addsub() { # $1 name: a pushed superproject with a pushed submodule at sub/
  mkrepo "$tmp/$1src"; mkrepo "$tmp/$1"
  git -C "$tmp/$1" submodule -q add "$tmp/$1src.git" sub > /dev/null 2>&1
  git -C "$tmp/$1" commit -qm addsub; git -C "$tmp/$1" push -q 2>/dev/null
}
G() { run --session "$SID" --running 0 --fold "${F:-$fold}" "$@"; }
expect_rc() { # want rc -- guard args
  local want=$1; shift; local rc; rc=$(G "$@")
  [ "$rc" = "$want" ] && pass || fail "rc=$rc want $want: $(head -c 300 "$tmp/out")"
}

t "2a ignored file (info/exclude) -> 11"
mkrepo "$tmp/ig"; echo '*.secret' >> "$tmp/ig/.git/info/exclude"; echo work > "$tmp/ig/notes.secret"
expect_rc 11 --worktree "$tmp/ig"
t "2a the ignored path is named"
LC_ALL=C grep -q '^guard:     notes.secret$' "$tmp/out" && pass || fail "$(cat "$tmp/out")"
t "2b ignored dir via committed .gitignore -> 11"
mkrepo "$tmp/ig2"; echo 'cowork-prompts/' > "$tmp/ig2/.gitignore"; git -C "$tmp/ig2" add .gitignore; git -C "$tmp/ig2" commit -qm gi; git -C "$tmp/ig2" push -q 2>/dev/null
mkdir "$tmp/ig2/cowork-prompts"; echo prompt > "$tmp/ig2/cowork-prompts/PROMPT_99.md"
expect_rc 11 --worktree "$tmp/ig2"
t "ignored rebuildable dirs pass and are listed"
mkrepo "$tmp/rb"; printf 'node_modules/\ndist/\npkg/.venv/\n' > "$tmp/rb/.gitignore"
echo '{}' > "$tmp/rb/package.json"; mkdir -p "$tmp/rb/pkg"; : > "$tmp/rb/pkg/pyproject.toml"
git -C "$tmp/rb" add .gitignore package.json pkg/pyproject.toml; git -C "$tmp/rb" commit -qm gi; git -C "$tmp/rb" push -q 2>/dev/null
mkdir -p "$tmp/rb/node_modules/x" "$tmp/rb/dist" "$tmp/rb/pkg/.venv"; : > "$tmp/rb/node_modules/x/i.js"; : > "$tmp/rb/dist/o.js"; : > "$tmp/rb/pkg/.venv/p"
rc=$(G --worktree "$tmp/rb")
[ "$rc" = 0 ] && LC_ALL=C grep -q 'skipped (rebuildable) node_modules in' "$tmp/out" && pass || fail "rc=$rc $(cat "$tmp/out")"
t "r3 P2: an allow-listed name with no manifest beside it -> 11"
mkrepo "$tmp/rb2"; printf 'node_modules/\nbuild/\n' > "$tmp/rb2/.gitignore"; git -C "$tmp/rb2" add .gitignore; git -C "$tmp/rb2" commit -qm gi; git -C "$tmp/rb2" push -q 2>/dev/null
mkdir -p "$tmp/rb2/node_modules" "$tmp/rb2/build"; echo notes > "$tmp/rb2/node_modules/my-notes.md"; echo work > "$tmp/rb2/build/draft.txt"
expect_rc 11 --worktree "$tmp/rb2"
t "A-34: a manifest-backed node_modules with no .git inside is skipped whole -> 0"
mkrepo "$tmp/rb3"; echo 'node_modules/*.local' > "$tmp/rb3/.gitignore"; echo '{}' > "$tmp/rb3/package.json"
git -C "$tmp/rb3" add .gitignore package.json; git -C "$tmp/rb3" commit -qm gi; git -C "$tmp/rb3" push -q 2>/dev/null
mkdir -p "$tmp/rb3/node_modules"; echo draft > "$tmp/rb3/node_modules/notes.local"
rc=$(G --worktree "$tmp/rb3")
[ "$rc" = 0 ] && LC_ALL=C grep -q 'skipped (rebuildable) node_modules in' "$tmp/out" && pass || fail "rc=$rc $(cat "$tmp/out")"
t "2c unpushed tag-only commit -> 12 (its file is not on disk)"
mkrepo "$tmp/tg"; git -C "$tmp/tg" checkout -q --detach; echo b > "$tmp/tg/b"; git -C "$tmp/tg" add b; git -C "$tmp/tg" commit -qm tagonly; git -C "$tmp/tg" tag v-local; git -C "$tmp/tg" checkout -q main
expect_rc 12 --worktree "$tmp/tg"
t "2d unpushed commit on a branch that is not HEAD -> 12"
mkrepo "$tmp/nb"; git -C "$tmp/nb" checkout -qb side; echo b > "$tmp/nb/b"; git -C "$tmp/nb" add b; git -C "$tmp/nb" commit -qm side; git -C "$tmp/nb" checkout -q main
expect_rc 12 --worktree "$tmp/nb"
t "2e stash only -> 12 (A-34: the stash is a ref to verify)"
mkrepo "$tmp/st"; echo dirty >> "$tmp/st/a.txt"; git -C "$tmp/st" stash -q
expect_rc 12 --worktree "$tmp/st"
t "2f detached HEAD, unpushed -> 12"
mkrepo "$tmp/dh"; git -C "$tmp/dh" checkout -q --detach; echo b > "$tmp/dh/b"; git -C "$tmp/dh" add b; git -C "$tmp/dh" commit -qm det
expect_rc 11 --worktree "$tmp/dh"
t "2f ...and the commit is reported 12"
reported 12 && pass || fail "$(cat "$tmp/out")"
t "2h nested repo ignored by the outer one -> 11"
mkrepo "$tmp/ne"; echo 'inner/' > "$tmp/ne/.gitignore"; git -C "$tmp/ne" add .gitignore; git -C "$tmp/ne" commit -qm gi; git -C "$tmp/ne" push -q 2>/dev/null
git init -q "$tmp/ne/inner"; echo w > "$tmp/ne/inner/w"; git -C "$tmp/ne/inner" add w; git -C "$tmp/ne/inner" commit -qm inner
expect_rc 11 --worktree "$tmp/ne"
t "2i nested repo, not ignored -> 11"
mkrepo "$tmp/ne2"; git init -q "$tmp/ne2/inner"; echo w > "$tmp/ne2/inner/w"; git -C "$tmp/ne2/inner" add w; git -C "$tmp/ne2/inner" commit -qm inner
expect_rc 11 --worktree "$tmp/ne2"
t "2j/2k dirty submodule, even with ignore=all committed in .gitmodules -> 11"
addsub sm; git -C "$tmp/sm" config -f .gitmodules submodule.sub.ignore all; git -C "$tmp/sm" add .gitmodules; git -C "$tmp/sm" commit -qm ign; git -C "$tmp/sm" push -q 2>/dev/null
echo dirt >> "$tmp/sm/sub/a.txt"
expect_rc 11 --worktree "$tmp/sm"
t "2l unpushed submodule commit, superproject bump pushed -> 12"
addsub sm2; echo n > "$tmp/sm2/sub/n"; git -C "$tmp/sm2/sub" add n; git -C "$tmp/sm2/sub" commit -qm subwork
git -C "$tmp/sm2" add sub; git -C "$tmp/sm2" commit -qm bump; git -C "$tmp/sm2" push -q 2>/dev/null
expect_rc 11 --worktree "$tmp/sm2"
t "2l ...and the submodule commit is reported 12"
reported 12 && LC_ALL=C grep -q '^guard: 12 .*sm2/sub$' "$tmp/out" && pass || fail "$(cat "$tmp/out")"
t "2m diff.ignoreSubmodules=all in local config, dirty submodule -> 11"
addsub sm3; git -C "$tmp/sm3" config diff.ignoreSubmodules all; echo dirt >> "$tmp/sm3/sub/a.txt"
expect_rc 11 --worktree "$tmp/sm3"
t "2n linked worktree, local-only branch commit -> 12"
mkrepo "$tmp/lw"; git -C "$tmp/lw" worktree add -q -b wtb "$tmp/lw-wt" 2>/dev/null; echo z > "$tmp/lw-wt/z"; git -C "$tmp/lw-wt" add z; git -C "$tmp/lw-wt" commit -qm wt
expect_rc 11 --worktree "$tmp/lw-wt"
t "2n ...and the branch commit is reported 12"
reported 12 && pass || fail "$(cat "$tmp/out")"
t "2p no --worktree: the guard says nothing on disk was checked"
rc=$(G)
[ "$rc" = 0 ] && LC_ALL=C grep -q 'note no --worktree given' "$tmp/out" && pass || fail "rc=$rc $(cat "$tmp/out")"

# Fold rows that must not count as folded (2r-alt, 2r, 2s, 2t).
mkrows() { # file, siblings rows
  sed '/^| 1589a98d | DIVERGED /d' "$fold" | awk -v rows="$2" '{ print } /^\|---\|---\|---\|---\|---\|$/ && !done { print rows; done = 1 }' > "$1"
}
t "2r-alt only another row mentions this sid8 -> 14"
F="$tmp/fold/AXM-046-20261004-2214.md"; mkrows "$F" "| aaaaaaaa | DIVERGED | handoff of 1589a98d | Read | folded: 1 decisions, 0 files |"
expect_rc 14 --worktree "$wt"
t "2r an earlier row mentions this sid8; this row is LIVE, not folded -> 14"
F="$tmp/fold/AXM-046-20261004-2211.md"; mkrows "$F" "| aaaaaaaa | DIVERGED | after 1589a98d handoff | Read | folded: 1 decisions, 0 files |
| 1589a98d | LIVE | - | Ask | not folded (timed out) |"
expect_rc 14 --worktree "$wt"
t "2s NOT FOLDED in capitals -> 14"
F="$tmp/fold/AXM-046-20261004-2212.md"; mkrows "$F" "| 1589a98d | DIVERGED | - | Ask | NOT FOLDED (timed out) |"
expect_rc 14 --worktree "$wt"
t "2t FOREIGN, report only -> 14"
F="$tmp/fold/AXM-046-20261004-2213.md"; mkrows "$F" "| 1589a98d | FOREIGN | - | - | report only |"
expect_rc 14 --worktree "$wt"
t "a SUPERSEDED row with nothing unique passes"
F="$tmp/fold/AXM-046-20261004-2215.md"; mkrows "$F" "| 1589a98d | SUPERSEDED | handoff | Read | nothing unique |"
expect_rc 0 --worktree "$wt"
unset F

t "code-exec attacks: hooks, hooksPath, submodule hooks, fsmonitor, ssh, credential, pager, diff, gc"
mkrepo "$tmp/hk"; for h in post-index-change post-checkout reference-transaction; do printf '#!/bin/sh\necho hook-%s >> "%s"\n' "$h" "$pwn" > "$tmp/hk/.git/hooks/$h"; chmod +x "$tmp/hk/.git/hooks/$h"; done; touch "$tmp/hk/a.txt"; G --worktree "$tmp/hk" > /dev/null
mkrepo "$tmp/hp"; mkdir "$tmp/hpd"; printf '#!/bin/sh\necho hookpath >> "%s"\n' "$pwn" > "$tmp/hpd/post-index-change"; chmod +x "$tmp/hpd/post-index-change"; git -C "$tmp/hp" config core.hooksPath "$tmp/hpd"; touch "$tmp/hp/a.txt"; G --worktree "$tmp/hp" > /dev/null
addsub smh; printf '#!/bin/sh\necho subhook >> "%s"\n' "$pwn" > "$tmp/smh/.git/modules/sub/hooks/post-index-change"; chmod +x "$tmp/smh/.git/modules/sub/hooks/post-index-change"; touch "$tmp/smh/sub/a.txt"; G --worktree "$tmp/smh" > /dev/null
addsub sm5; mkpay fsmsub; git -C "$tmp/sm5/sub" config core.fsmonitor "$tmp/pay_fsmsub.sh"; touch "$tmp/sm5/sub/a.txt"; G --worktree "$tmp/sm5" > /dev/null
mkrepo "$tmp/ss"; mkpay ssh; mkpay cred; git -C "$tmp/ss" config core.sshCommand "$tmp/pay_ssh.sh"; git -C "$tmp/ss" config credential.helper "!$tmp/pay_cred.sh"; git -C "$tmp/ss" config core.askPass "$tmp/pay_cred.sh"; git -C "$tmp/ss" remote set-url origin git@github.com:acme/widgets.git
PATH="$fake:$PATH" G --worktree "$tmp/ss" > /dev/null
mkrepo "$tmp/de"; mkpay dext; mkpay tconv; git -C "$tmp/de" config diff.external "$tmp/pay_dext.sh"; git -C "$tmp/de" config diff.t.textconv "$tmp/pay_tconv.sh"; echo '* diff=t' > "$tmp/de/.gitattributes"; git -C "$tmp/de" config core.pager "$tmp/pay_dext.sh"; echo zz >> "$tmp/de/a.txt"; G --worktree "$tmp/de" > /dev/null
mkrepo "$tmp/ar"; mkpay alt; git -C "$tmp/ar" config core.alternateRefsCommand "$tmp/pay_alt.sh"; git -C "$tmp/ar" config gc.auto 1; G --worktree "$tmp/ar" > /dev/null
addsub sm6; mkpay upd; git -C "$tmp/sm6" config submodule.sub.update "!$tmp/pay_upd.sh"; G --worktree "$tmp/sm6" > /dev/null
[ ! -s "$pwn" ] && pass || fail "ran: $(tr '\n' ' ' < "$pwn")"

# Filter drivers from every repo-controlled place: each is refused (15) and
# never runs. includeIf conditions are written so they hold on this host.
for kind in sub mixedcase worktree linked onbranch gitdir hasconfig; do
  t "filter driver via $kind: payload never runs; the untracked .gitattributes is not recoverable"
  d="$tmp/f_$kind"; mkpay "f$kind"; inc="$tmp/inc_$kind.cfg"
  printf '[filter "z"]\n\tclean = %s\n' "$tmp/pay_f$kind.sh" > "$inc"
  case $kind in
    sub) addsub "f_$kind"; git -C "$d/sub" config filter.z.clean "$tmp/pay_f$kind.sh"; echo '* filter=z' > "$d/sub/.gitattributes"; touch "$d/sub/a.txt" ;;
    mixedcase) mkrepo "$d"; printf '[Filter "Z"]\n\tclean = %s\n' "$tmp/pay_f$kind.sh" >> "$d/.git/config" ;;
    worktree) mkrepo "$d"; git -C "$d" config extensions.worktreeConfig true; git -C "$d" config --worktree filter.z.clean "$tmp/pay_f$kind.sh" ;;
    linked) mkrepo "$d.main"; git -C "$d.main" config extensions.worktreeConfig true; git -C "$d.main" worktree add -q -b w2 "$d" 2>/dev/null
            git -C "$d" push -q -u origin w2 2>/dev/null; git -C "$d" config --worktree filter.z.clean "$tmp/pay_f$kind.sh" ;;
    onbranch) mkrepo "$d"; git -C "$d" config includeIf.onbranch:main.path "$inc" ;;
    gitdir) mkrepo "$d"; git -C "$d" config "includeIf.gitdir:**/f_gitdir/.git.path" "$inc" ;;
    hasconfig) mkrepo "$d"; git -C "$d" config 'includeIf.hasconfig:remote.*.url:**/*.git.path' "$inc" ;;
  esac
  [ -f "$d/.gitattributes" ] || echo '* filter=z' > "$d/.gitattributes"
  touch "$d/a.txt"
  rc=$(G --worktree "$d")
  [ "$rc" != 0 ] && ! LC_ALL=C grep -q "^f$kind\$" "$pwn" 2>/dev/null && pass || fail "rc=$rc ran=$(cat "$pwn" 2>/dev/null | tr '\n' ' ') $(head -c 200 "$tmp/out")"
done
t "positive control: the includeIf filters are live for git itself"
live=0; for kind in onbranch gitdir hasconfig; do [ -n "$(git -C "$tmp/f_$kind" config --get filter.z.clean)" ] && live=$((live+1)); done
[ $live = 3 ] && pass || fail "$live of 3 includeIf filters are active"

# --- r3 grader findings -------------------------------------------------------------
# A gitlink staged with no .gitmodules entry: git status recurses into the
# nested repo, whose own filter would run. The guard refuses it (15) before
# any status, and the payload never runs (g1 repro).
mklink() { # $1 dir, $2 "filter" to give the nested repo a filter payload
  mkrepo "$1"; git init -q "$1/sub"; echo s > "$1/sub/s.txt"
  git -C "$1/sub" add s.txt; git -C "$1/sub" commit -qm s
  if [ "${2:-}" = filter ]; then
    mkpay "link$$"; git -C "$1/sub" config filter.evil.clean "$tmp/pay_link$$.sh"
    echo '* filter=evil' > "$1/sub/.gitattributes"
  fi
  git -C "$1" add sub 2> /dev/null; git -C "$1" commit -qm link; git -C "$1" push -q 2>/dev/null
  [ "${2:-}" = filter ] && touch -t 202901010000 "$1/sub/s.txt"
  return 0
}
t "r3 MUST: gitlink without .gitmodules, nested filter: payload never runs; a nested repo with no remote -> 11"
mklink "$tmp/gl1" filter
rc=$(G --worktree "$tmp/gl1")
[ "$rc" = 11 ] && ! LC_ALL=C grep -q "^link$$\$" "$pwn" 2>/dev/null && LC_ALL=C grep -q 'nested repository with no remote' "$tmp/out" && pass ||
  fail "rc=$rc ran=$(cat "$pwn" 2>/dev/null | tr '\n' ' ') $(head -c 300 "$tmp/out")"
t "r3 MUST: positive control: plain git status runs that nested filter"
( cd "$tmp/gl1" && git status --porcelain > /dev/null 2>&1 )
LC_ALL=C grep -q "^link$$\$" "$pwn" 2>/dev/null && pass || fail "the fixture filter never fires"
: > "$pwn"
t "r3 MUST: gitlink without .gitmodules, no filter -> 11 (no remote holds it)"
mklink "$tmp/gl2"
expect_rc 11 --worktree "$tmp/gl2"
t "r3 MUST: a declared submodule whose own config has a filter: never runs"
addsub sf; mkpay sf; git -C "$tmp/sf/sub" config filter.q.clean "$tmp/pay_sf.sh"; echo '* filter=q' > "$tmp/sf/sub/.gitattributes"; touch -t 202901010000 "$tmp/sf/sub/a.txt"
rc=$(G --worktree "$tmp/sf")
[ "$rc" != 0 ] && ! LC_ALL=C grep -q '^sf$' "$pwn" 2>/dev/null && pass || fail "rc=$rc ran=$(cat "$pwn" 2>/dev/null | tr '\n' ' ')"
# Inside submodules: ignored files, every branch, and the stash.
t "r3 MUST: an ignored, non-rebuildable file inside a submodule -> 11"
addsub si; echo '*.secret' >> "$(git -C "$tmp/si/sub" rev-parse --path-format=absolute --git-path info/exclude)"; echo k > "$tmp/si/sub/key.secret"
rc=$(G --worktree "$tmp/si")
[ "$rc" = 11 ] && LC_ALL=C grep -q '^guard:     key.secret$' "$tmp/out" && pass || fail "rc=$rc $(cat "$tmp/out")"
t "r3 MUST: an unpushed commit on a submodule branch that is not its HEAD -> 12"
addsub sb; git -C "$tmp/sb/sub" checkout -q -b side; echo b > "$tmp/sb/sub/b"; git -C "$tmp/sb/sub" add b; git -C "$tmp/sb/sub" commit -qm side; git -C "$tmp/sb/sub" checkout -q main
expect_rc 12 --worktree "$tmp/sb"
t "r3 MUST: a stash inside a submodule -> 12"
addsub ss2; echo d >> "$tmp/ss2/sub/a.txt"; git -C "$tmp/ss2/sub" stash -q
expect_rc 12 --worktree "$tmp/ss2"
t "r3 P3: no upstream: the PR check falls back to origin and the branch -> 13"
mkrepo "$tmp/nu2"; git -C "$tmp/nu2" checkout -q -b feat; echo f > "$tmp/nu2/f"; git -C "$tmp/nu2" add f; git -C "$tmp/nu2" commit -qm f
git -C "$tmp/nu2" push -q origin feat 2>/dev/null; git -C "$tmp/nu2" remote set-url origin https://github.com/acme/widgets.git
echo 0 > "$FAKEGH/auth_rc"; echo 77 > "$FAKEGH/prs"; echo 'nothing here' > "$FAKEGH/comments"
rc=$(PATH="$fake:$PATH" G --worktree "$tmp/nu2")
[ "$rc" = 13 ] && pass || fail "rc=$rc $(cat "$tmp/out")"
: > "$FAKEGH/prs"

# --- A-34: the outcome invariant (r4 domain findings) --------------------------------
t "A-34 clean, fully pushed repo -> 0"
mkrepo "$tmp/cl"; mkdir -p "$tmp/cl/docs"; echo d > "$tmp/cl/docs/d.md"; git -C "$tmp/cl" add docs; git -C "$tmp/cl" commit -qm docs; git -C "$tmp/cl" push -q 2>/dev/null
expect_rc 0 --worktree "$tmp/cl"
t "A-34 a renamed but identical file is recoverable -> 0"
mkrepo "$tmp/rn"; mv "$tmp/rn/a.txt" "$tmp/rn/renamed.txt"
expect_rc 0 --worktree "$tmp/rn"
t "A-34 a CRLF checkout of LF content (core.autocrlf) is recoverable -> 0"
mkrepo "$tmp/crlf"; printf 'a\r\n' > "$tmp/crlf/a.txt"
expect_rc 0 --worktree "$tmp/crlf"
t "A-34 ...but CRLF content that differs from every remote blob -> 11"
mkrepo "$tmp/crlf2"; printf 'b\r\n' > "$tmp/crlf2/a.txt"
expect_rc 11 --worktree "$tmp/crlf2"
t "B-1 --worktree is a subdirectory: the toplevel is checked, and its undeclared nested repo's filter never runs"
mklink "$tmp/b1" filter; mkdir -p "$tmp/b1/docs"; echo d > "$tmp/b1/docs/x.md"; git -C "$tmp/b1" add docs; git -C "$tmp/b1" commit -qm d; git -C "$tmp/b1" push -q 2>/dev/null
rc=$(G --worktree "$tmp/b1/docs")
[ "$rc" = 11 ] && ! LC_ALL=C grep -q "^link$$\$" "$pwn" 2>/dev/null && LC_ALL=C grep -q 'nested repository with no remote.*b1/sub' "$tmp/out" && pass ||
  fail "rc=$rc ran=$(cat "$pwn" 2>/dev/null | tr '\n' ' ') $(head -c 300 "$tmp/out")"
t "B-2 an edit hidden by assume-unchanged -> 11"
mkrepo "$tmp/au"; git -C "$tmp/au" update-index --assume-unchanged a.txt; echo hidden >> "$tmp/au/a.txt"
expect_rc 11 --worktree "$tmp/au"
t "B-2 an edit hidden by skip-worktree -> 11"
mkrepo "$tmp/sw"; git -C "$tmp/sw" update-index --skip-worktree a.txt; echo hidden >> "$tmp/sw/a.txt"
expect_rc 11 --worktree "$tmp/sw"
for kind in build venv; do
  t "B-3 a nested repo with unpushed commits inside an ignored $kind/ beside its manifest -> 12"
  d="$tmp/b3$kind"; mkrepo "$d"
  case $kind in
    build) inner="$d/build/tool"; echo 'build/' > "$d/.gitignore"; echo '{}' > "$d/package.json"; git -C "$d" add .gitignore package.json ;;
    venv) inner="$d/.venv/src/lib"; echo '.venv/' > "$d/.gitignore"; : > "$d/pyproject.toml"; git -C "$d" add .gitignore pyproject.toml ;;
  esac
  git -C "$d" commit -qm m; git -C "$d" push -q 2>/dev/null
  git init -q --bare "$inner.git"; git init -q "$inner"; git -C "$inner" remote add origin "$inner.git"
  echo i > "$inner/i"; git -C "$inner" add i; git -C "$inner" commit -qm i; git -C "$inner" push -q -u origin main 2>/dev/null
  echo j > "$inner/j"; git -C "$inner" add j; git -C "$inner" commit -qm unpushed
  rc=$(G --worktree "$d")
  [ "$rc" = 11 ] && reported 12 && LC_ALL=C grep -q "^guard: 12 .*$(basename "$inner")\$" "$tmp/out" && pass || fail "rc=$rc $(cat "$tmp/out")"
done
t "B-3 control: the same build/ with no .git inside is skipped -> 0"
mkrepo "$tmp/b3c"; echo 'build/' > "$tmp/b3c/.gitignore"; echo '{}' > "$tmp/b3c/package.json"; git -C "$tmp/b3c" add .gitignore package.json; git -C "$tmp/b3c" commit -qm m; git -C "$tmp/b3c" push -q 2>/dev/null
mkdir -p "$tmp/b3c/build"; echo o > "$tmp/b3c/build/out.js"
expect_rc 0 --worktree "$tmp/b3c"
t "P2-a a gitlink directory with no .git is plain files under the invariant -> 11"
mklink "$tmp/p2a"; rm -rf "$tmp/p2a/sub/.git"
expect_rc 11 --worktree "$tmp/p2a"
for kind in worktree bisect; do
  t "P3-d a linked worktree whose only unpushed commit is on refs/$kind -> 12"
  m="$tmp/rw$kind"; mkrepo "$m"; git -C "$m" worktree add -q --detach "$m-wt" 2>/dev/null
  echo w > "$m-wt/w"; git -C "$m-wt" add w; git -C "$m-wt" commit -qm w
  case $kind in worktree) ref=refs/worktree/keep ;; bisect) ref=refs/bisect/bad ;; esac
  git -C "$m-wt" update-ref "$ref" HEAD; git -C "$m-wt" checkout -q --detach origin/main; rm -f "$m-wt/w"
  expect_rc 12 --worktree "$m-wt"
done
t "an older stash entry (stash@{1}) counts, not only the tip -> 12"
mkrepo "$tmp/st2"; echo x >> "$tmp/st2/a.txt"; git -C "$tmp/st2" stash -q; git -C "$tmp/st2" stash pop -q; git -C "$tmp/st2" stash -q
git -C "$tmp/st2" update-ref -d refs/stash 2>/dev/null; mkdir -p "$tmp/st2/.git/logs/refs"
printf '%s %s t <t@x> 0 +0000\tWIP\n' "$(git -C "$tmp/st2" rev-parse HEAD)" "$(git -C "$tmp/st2" commit-tree -m old "$(git -C "$tmp/st2" write-tree)" -p HEAD)" > "$tmp/st2/.git/logs/refs/stash"
git -C "$tmp/st2" checkout -q -- a.txt
expect_rc 12 --worktree "$tmp/st2"
t "staged content that is on no remote (the file on disk reverted) -> 11"
mkrepo "$tmp/stg"; echo staged > "$tmp/stg/a.txt"; git -C "$tmp/stg" add a.txt; echo a > "$tmp/stg/a.txt"
rc=$(G --worktree "$tmp/stg")
[ "$rc" = 11 ] && LC_ALL=C grep -q 'a.txt (staged)' "$tmp/out" && pass || fail "rc=$rc $(cat "$tmp/out")"
t "a nested repo with no remote anywhere below -> 11"
mkrepo "$tmp/nr"; mkdir -p "$tmp/nr/vendor"; git init -q "$tmp/nr/vendor/x"; echo y > "$tmp/nr/vendor/x/y"
expect_rc 11 --worktree "$tmp/nr"
t "a toplevel with no remote-tracking refs -> 15"
git init -q "$tmp/norem"; echo a > "$tmp/norem/a"; git -C "$tmp/norem" add a; git -C "$tmp/norem" commit -qm a
expect_rc 15 --worktree "$tmp/norem"
t "A-34 no payload ever ran during any guard call in this file"
[ ! -s "$pwn" ] && [ ! -e "$tmp/pwned" ] && [ ! -e "$tmp/pwned-local" ] || [ "$(cat "$pwn" 2>/dev/null)" = "" ]
ran=$(cat "$pwn" 2>/dev/null | LC_ALL=C grep -v "^link$$\$" | tr '\n' ' ')
[ -z "$ran" ] && pass || fail "ran: $ran"

t "2 on bad usage"
r1=$(run --session "$SID" --running maybe --fold "$fold")
r2=$(run --session 'a;b' --running 0 --fold "$fold")
r3=$(run --running 0 --fold "$fold")
r4=$(run --session "$SID" --running 0 --fold "$fold" --bogus)
[ "$r1$r2$r3$r4" = 2222 ] && pass || fail "got $r1 $r2 $r3 $r4"

echo "$([ $no -eq 0 ] && echo PASS || echo FAIL) ${0##*/} ($((ok+no)) cases)"; [ $no -eq 0 ]
