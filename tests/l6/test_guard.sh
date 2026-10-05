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

t "12 unpushed commit (bare remote behind)"
w2="$tmp/w2"; mkrepo "$w2"
echo c > "$w2/c.txt"; git -C "$w2" add c.txt; git -C "$w2" commit -qm local
rc=$(run --session "$SID" --running 0 --fold "$fold" --worktree "$w2")
[ "$rc" = 12 ] && pass || fail "rc=$rc"

t "12 a branch never pushed anywhere"
w3="$tmp/w3"; mkrepo "$w3"
git -C "$w3" checkout -q -b feature; echo d > "$w3/d.txt"; git -C "$w3" add d.txt; git -C "$w3" commit -qm feat
rc=$(run --session "$SID" --running 0 --fold "$fold" --worktree "$w3")
[ "$rc" = 12 ] && pass || fail "rc=$rc"

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

t "lowest code wins: unpushed + gh missing + not folded -> 12"
echo e > "$gw/e.txt"; git -C "$gw" add e.txt; git -C "$gw" commit -qm e
rc=$(runp "$np" --session "$SID" --running 0 --fold "$tmp/fold/none.md" --worktree "$gw")
[ "$rc" = 12 ] && pass || fail "rc=$rc"

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
  t "15 repo filter driver ($where config) and the payload never runs"
  w5="$tmp/w5-$where"; mkfilter "$w5" "$where"
  rc=$(run --session "$SID" --running 0 --fold "$fold" --worktree "$w5")
  [ "$rc" = 15 ] && [ ! -e "$tmp/pwned-$where" ] && LC_ALL=C grep -q 'filter driver' "$tmp/out" && pass ||
    fail "rc=$rc pwned=$([ -e "$tmp/pwned-$where" ] && echo yes || echo no) $(cat "$tmp/out")"
done
for where in local include; do
  t "positive control: plain git status in the $where repo does run the filter"
  ( cd "$tmp/w5-$where" && git status --porcelain > /dev/null 2>&1 )
  [ -e "$tmp/pwned-$where" ] && pass || fail "the fixture filter never fires, so the case above proves nothing"
done

t "2 on bad usage"
r1=$(run --session "$SID" --running maybe --fold "$fold")
r2=$(run --session 'a;b' --running 0 --fold "$fold")
r3=$(run --running 0 --fold "$fold")
r4=$(run --session "$SID" --running 0 --fold "$fold" --bogus)
[ "$r1$r2$r3$r4" = 2222 ] && pass || fail "got $r1 $r2 $r3 $r4"

echo "$([ $no -eq 0 ] && echo PASS || echo FAIL) ${0##*/} ($((ok+no)) cases)"; [ $no -eq 0 ]
