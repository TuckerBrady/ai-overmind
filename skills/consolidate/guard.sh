#!/usr/bin/env bash
# guard.sh --session <id> --running <0|1> --fold <file> [--worktree <path>]...
#
# /consolidate's pre-archive guard (CONTRACT 6.9, GAP-45). Archiving a desktop
# session stops it and, by default, deletes its worktree, so a sibling is
# archived only when this exits 0. Every check runs; the exit code is the
# LOWEST failing code:
#
#   0  pass: safe to archive (still only after the human's yes this session)
#   10 running: the session is mid-turn or has live background work
#   11 dirty worktree: uncommitted or untracked changes
#   12 unpushed commits: HEAD has commits no remote branch holds
#   13 open PR on the worktree's branch with no fold note (a PR comment
#      containing the fold file's basename)
#   14 not folded: the fold file is missing, has no Siblings row for this
#      session, records it "not folded", or fails invariant.sh
#   15 cannot verify: a worktree path is not a git work tree, the repo's own
#      config defines a filter driver (inspecting it would run that program),
#      or a branch has a GitHub upstream and gh is missing, unauthenticated
#      or failing
#   2  bad usage
#
# One line per failed check goes to stdout as "guard: <code> <reason>".
set -u
here=$(cd "$(dirname "$0")" && pwd)
usage() { echo "usage: guard.sh --session <id> --running <0|1> --fold <file> [--worktree <path>]..." >&2; exit 2; }

sid=""; running=""; fold=""; wts=()
while [ $# -gt 0 ]; do
  case $1 in
    --session)  [ $# -ge 2 ] || usage; sid=$2; shift 2 ;;
    --running)  [ $# -ge 2 ] || usage; running=$2; shift 2 ;;
    --fold)     [ $# -ge 2 ] || usage; fold=$2; shift 2 ;;
    --worktree) [ $# -ge 2 ] || usage; wts+=("$2"); shift 2 ;;
    *) usage ;;
  esac
done
case $running in 0|1) ;; *) usage ;; esac
[ -n "$sid" ] && [ -n "$fold" ] || usage
case $sid in *[!A-Za-z0-9_-]*) usage ;; esac
[ ${#sid} -le 64 ] || usage

# sid8: the first 8 characters of the id, without the desktop "local_" prefix.
bare=${sid#local_}; sid8=${bare:0:8}

# git, with core.fsmonitor off and hooks pointed at nothing. That closes two
# ways a repo's own config can make a git call run a program. It does not
# close the third: a filter driver (filter.<x>.clean / .process, named by
# .gitattributes) runs during "git status". So before any status, a repo
# whose own config (local, worktree, included files, or a submodule's)
# defines a filter is not inspected at all: exit 15, cannot verify. Filters
# in the user's global or system config are the user's own installs (git-lfs)
# and are not a repo-borne payload.
g() { git -c core.fsmonitor=false -c core.hooksPath=/dev/null -C "$@"; }
repo_filters() { # $1 work tree -> prints any repo-controlled filter.* config
  g "$1" config --local --includes --get-regexp '^filter\.' 2>/dev/null
  g "$1" config --worktree --includes --get-regexp '^filter\.' 2>/dev/null
  if [ -f "$1/.gitmodules" ]; then
    g "$1" submodule --quiet foreach --recursive \
      'git config --local --includes --get-regexp "^filter\." || :' 2>/dev/null
  fi
}

codes=""
flag() { codes="$codes $1"; echo "guard: $1 $2"; }

# Bound a network call when a timeout tool exists.
tmo=""
if command -v timeout >/dev/null 2>&1; then tmo="timeout 60"
elif command -v gtimeout >/dev/null 2>&1; then tmo="gtimeout 60"; fi

# --- 10 running ----------------------------------------------------------------
[ "$running" = 1 ] && flag 10 "session $sid8 is running"

# --- 11, 12, 13, 15 per worktree --------------------------------------------------
gh_state=""   # "", ok, missing, unauth
gh_ready() {
  if [ -z "$gh_state" ]; then
    if ! command -v gh >/dev/null 2>&1; then gh_state=missing
    else
      $tmo gh auth status >/dev/null 2>&1
      case $? in
        0) gh_state=ok ;;
        126|127) gh_state=missing ;;   # found but cannot run
        *) gh_state=unauth ;;
      esac
    fi
  fi
  [ "$gh_state" = ok ]
}
fbase=${fold##*/}

for wt in ${wts[@]+"${wts[@]}"}; do
  if [ ! -d "$wt" ] || [ "$(g "$wt" rev-parse --is-inside-work-tree 2>/dev/null)" != true ]; then
    flag 15 "not a git work tree: $wt"; continue
  fi
  if [ -n "$(repo_filters "$wt" | head -n 1)" ]; then
    flag 15 "repo config defines a filter driver; not inspected: $wt"; continue
  fi
  if [ -n "$(g "$wt" status --porcelain --untracked-files=normal 2>/dev/null | head -1)" ]; then
    flag 11 "uncommitted or untracked changes in $wt"
  fi
  if g "$wt" rev-parse --verify -q HEAD >/dev/null 2>&1; then
    ahead=$(g "$wt" rev-list --count HEAD --not --remotes 2>/dev/null)
    case $ahead in ''|*[!0-9]*) flag 15 "cannot count unpushed commits in $wt" ;; 0) ;; *) flag 12 "$ahead commit(s) on HEAD that no remote holds in $wt" ;; esac
  fi
  branch=$(g "$wt" symbolic-ref -q --short HEAD 2>/dev/null)
  [ -n "$branch" ] || continue
  remote=$(g "$wt" config --get "branch.$branch.remote" 2>/dev/null)
  [ -n "$remote" ] || continue
  url=$(g "$wt" config --get "remote.$remote.url" 2>/dev/null)
  case $url in *github.com[:/]*) ;; *) continue ;; esac
  repo=${url#*github.com}; repo=${repo#[:/]}; repo=${repo%.git}; repo=${repo%/}
  case $repo in *[!A-Za-z0-9_./-]*|*/*/*|/*|*..*|'') flag 15 "cannot parse GitHub repo from the upstream of $branch"; continue ;; esac
  merge=$(g "$wt" config --get "branch.$branch.merge" 2>/dev/null); head=${merge#refs/heads/}
  [ -n "$head" ] || head=$branch
  if ! gh_ready; then
    flag 15 "gh $gh_state: cannot check open PRs on $repo:$head"; continue
  fi
  prs=$($tmo gh pr list --repo "$repo" --head "$head" --state open --json number --jq '.[].number' 2>/dev/null); rc=$?
  if [ $rc -ne 0 ]; then flag 15 "gh pr list failed for $repo:$head"; continue; fi
  for pr in $prs; do
    case $pr in *[!0-9]*) flag 15 "unexpected PR number from gh: $pr"; continue ;; esac
    bodies=$($tmo gh pr view "$pr" --repo "$repo" --json comments --jq '.comments[].body' 2>/dev/null); rc=$?
    if [ $rc -ne 0 ]; then flag 15 "gh pr view failed for $repo#$pr"; continue; fi
    printf '%s\n' "$bodies" | LC_ALL=C grep -qF -- "$fbase" || flag 13 "open PR $repo#$pr on $head has no comment naming $fbase"
  done
done

# --- 14 folded ---------------------------------------------------------------------
if [ ! -f "$fold" ]; then
  flag 14 "fold file missing: $fold"
else
  row=$(tr -d '\r' < "$fold" | LC_ALL=C awk -v s="$sid8" '
    /^## / { on = ($0 ~ /^## Siblings[ \t]*$/); next }
    on && /^[ \t]*\|/ && index($0, s) { print; exit }')
  if [ -z "$row" ]; then
    flag 14 "no ## Siblings row for $sid8 in ${fold##*/}"
  else
    case $row in *[Nn]"ot folded"*) flag 14 "$sid8 is recorded not folded" ;; esac
  fi
  if ! "${BASH:-bash}" "$here/invariant.sh" "$fold" >/dev/null 2>&1; then
    flag 14 "invariant.sh fails on ${fold##*/}"
  fi
fi

low=""
for c in $codes; do
  if [ -z "$low" ] || [ "$c" -lt "$low" ]; then low=$c; fi
done
if [ -z "$low" ]; then
  echo "guard: 0 $sid8 may be archived"
  exit 0
fi
exit "$low"
