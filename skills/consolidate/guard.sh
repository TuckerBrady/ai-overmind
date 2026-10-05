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
#      config or a submodule's defines a filter driver (inspecting it would
#      run that program), a populated gitlink has no .gitmodules entry,
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
g() {
  git --no-optional-locks -c core.fsmonitor=false -c core.hooksPath=/dev/null \
    -c core.pager=cat -c gc.auto=0 -c maintenance.auto=false -C "$@"
}
# An ignored path may go with the worktree only when it is a directory a
# build or an install recreates: its LAST component is one of these names
# AND the manifest that recreates it sits next to it. Anything else is
# someone's work.
rebuildable() { # $1 repo dir, $2 ignored path relative to it
  local p=${2%/} last parent m f
  last=${p##*/}; parent=$1
  case $p in */*) parent="$1/${p%/*}" ;; esac
  case $last in
    node_modules|.next) set -- package.json ;;
    dist|build) set -- package.json pyproject.toml setup.py setup.cfg Cargo.toml go.mod pom.xml build.gradle build.gradle.kts ;;
    target) set -- Cargo.toml pom.xml build.sbt ;;
    .venv) set -- pyproject.toml requirements.txt setup.py setup.cfg Pipfile poetry.lock ;;
    __pycache__)
      for f in "$parent"/*.py; do [ -f "$f" ] && return 0; done
      set -- pyproject.toml setup.py setup.cfg requirements.txt ;;
    *) return 1 ;;
  esac
  for m in "$@"; do [ -f "$parent/$m" ] && return 0; done
  return 1
}
tmpd=$(mktemp -d "${TMPDIR:-/tmp}/guard.XXXXXX") || exit 15
trap 'rm -rf "$tmpd"' EXIT
# Every filter.* setting git would actually apply in this repo (includes and
# includeIf resolved exactly as git resolves them), minus the user's own
# global and system scopes. What is left came from the repo: its config, a
# worktree config, or a file one of those includes.
filters_in() { # $1 repo dir
  g "$1" config --show-scope --includes --get-regexp '^filter\.' 2>/dev/null |
    LC_ALL=C grep -vE '^(global|system|command)[[:space:]]'
}
# Every populated gitlink (index mode 160000) under $1, recursively, found
# without running anything a repo configures: ls-files reads the index and
# config -f reads .gitmodules as a plain file. One line each:
#   MAPPED <dir>     declared in that repo's .gitmodules
#   UNMAPPED <dir>   not declared: a nested repo nothing vouches for
#   DEEP <dir>       nesting past 8 levels
# A populated gitlink is a directory holding a .git. git status recurses into
# it, and its own config (a filter) would run, so each one is scanned below.
walk_links() { # $1 repo dir, $2 depth
  local dir=$1 depth=$2 ent mode path full
  if [ "$depth" -gt 8 ]; then echo "DEEP $dir"; return; fi
  g "$dir" ls-files -s -z > "$tmpd/ls.$depth" 2>/dev/null
  : > "$tmpd/map.$depth"
  if [ -f "$dir/.gitmodules" ]; then
    git config -f "$dir/.gitmodules" --get-regexp '^submodule\..*\.path$' 2>/dev/null |
      LC_ALL=C sed 's/^[^ ]* //' > "$tmpd/map.$depth"
  fi
  while IFS= read -r -d '' ent; do
    mode=${ent%% *}
    [ "$mode" = 160000 ] || continue
    path=${ent#*$'\t'}; full="$dir/$path"
    [ -e "$full/.git" ] || continue
    if LC_ALL=C grep -qxF -- "$path" "$tmpd/map.$depth"; then
      echo "MAPPED $full"
      walk_links "$full" $((depth + 1))
    else
      echo "UNMAPPED $full"
    fi
  done < "$tmpd/ls.$depth"
}
# 11 and 12 for one repository: a worktree or a submodule.
check_repo() { # $1 repo dir
  local r=$1 ent code path dirty=0 nign=0 gdir cdir ahead what
  # 11: tracked changes, untracked files, dirty submodules (whatever
  # .gitmodules or diff.ignoreSubmodules say), and ignored files. Archiving
  # deletes the worktree, ignored files included.
  if ! g "$r" status --porcelain -z --untracked-files=normal --ignore-submodules=none --ignored=matching > "$tmpd/st" 2>/dev/null; then
    flag 15 "git status failed in $r"; return
  fi
  while IFS= read -r -d '' ent; do
    code=${ent:0:2}; path=${ent:3}
    case $code in R?|C?) IFS= read -r -d '' _ ;; esac   # a rename's source path follows
    if [ "$code" = '!!' ]; then
      if rebuildable "$r" "$path"; then
        nign=$((nign+1)); [ $nign -le 20 ] && echo "guard: ignored (rebuildable) $path in $r"
      else
        flag 11 "ignored, not rebuildable, deleted on archive: $path in $r"
      fi
    else
      dirty=1
    fi
  done < "$tmpd/st"
  [ $dirty = 1 ] && flag 11 "uncommitted or untracked changes in $r"
  # 12: commits no remote holds. A main worktree or a submodule counts every
  # local ref (other branches, tags, a detached commit); a linked worktree
  # checks its own HEAD, since the shared refs belong to the main one. The
  # stash is uncommitted work: 11. Remote-tracking refs are trusted as they
  # are on disk; nothing here asks the remote (that would run its ssh and
  # credential programs).
  gdir=$(g "$r" rev-parse --path-format=absolute --git-dir 2>/dev/null)
  cdir=$(g "$r" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  if [ -n "$gdir" ] && [ "$gdir" = "$cdir" ]; then
    g "$r" rev-parse -q --verify refs/stash > /dev/null 2>&1 && flag 11 "the stash holds uncommitted work in $r"
    ahead=$(g "$r" rev-list --count --exclude=refs/stash --all --not --remotes 2>/dev/null)
    what="on local branches, tags or HEAD"
  elif g "$r" rev-parse --verify -q HEAD > /dev/null 2>&1; then
    ahead=$(g "$r" rev-list --count HEAD --not --remotes 2>/dev/null)
    what="on HEAD"
  else
    ahead=0; what=""
  fi
  case $ahead in
    ''|*[!0-9]*) flag 15 "cannot count unpushed commits in $r" ;;
    0) ;;
    *) flag 12 "$ahead commit(s) $what that no remote holds in $r" ;;
  esac
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

if [ ${#wts[@]} -eq 0 ]; then
  echo "guard: note no --worktree given: nothing on disk was checked for $sid8"
fi
for wt in ${wts[@]+"${wts[@]}"}; do
  if [ ! -d "$wt" ] || [ "$(g "$wt" rev-parse --is-inside-work-tree 2>/dev/null)" != true ]; then
    flag 15 "not a git work tree: $wt"; continue
  fi
  # Gitlinks first: nothing below may run inside a nested repo that is not
  # declared, or one whose own config defines a filter.
  walk_links "$wt" 0 > "$tmpd/links"
  bad=$(LC_ALL=C grep -E '^(UNMAPPED|DEEP) ' "$tmpd/links" | head -n 1)
  if [ -n "$bad" ]; then
    flag 15 "nested repo with no .gitmodules entry (${bad#* }); not inspected: $wt"; continue
  fi
  : > "$tmpd/subs"
  while read -r kind sub; do printf '%s\n' "$sub" >> "$tmpd/subs"; done < "$tmpd/links"
  fdir=""
  if [ -n "$(filters_in "$wt" | head -n 1)" ]; then fdir=$wt; fi
  while IFS= read -r sub; do
    [ -z "$fdir" ] && [ -n "$(filters_in "$sub" | head -n 1)" ] && fdir=$sub
  done < "$tmpd/subs"
  if [ -n "$fdir" ]; then
    flag 15 "repo config defines a filter driver ($fdir); not inspected: $wt"; continue
  fi
  check_repo "$wt"
  # ...and every submodule, recursively, the same way.
  while IFS= read -r sub; do check_repo "$sub"; done < "$tmpd/subs"
  branch=$(g "$wt" symbolic-ref -q --short HEAD 2>/dev/null)
  [ -n "$branch" ] || continue
  remote=$(g "$wt" config --get "branch.$branch.remote" 2>/dev/null)
  # No upstream set: a PR can still be open on this branch at origin.
  [ -n "$remote" ] || remote=origin
  url=$(g "$wt" config --get "remote.$remote.url" 2>/dev/null)
  case $url in *github.com[:/]*) ;; *) continue ;; esac
  repo=${url#*github.com}; repo=${repo#[:/]}; repo=${repo%.git}; repo=${repo%/}
  case $repo in *[!A-Za-z0-9_./-]*|*/*/*|/*|*..*|'') flag 15 "cannot parse GitHub repo from the upstream of $branch"; continue ;; esac
  merge=$(g "$wt" config --get "branch.$branch.merge" 2>/dev/null); merge=${merge:-refs/heads/$branch}; head=${merge#refs/heads/}
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
  # The row whose Session cell is exactly sid8. Class must be SUPERSEDED or
  # DIVERGED, and Result must open "nothing unique" or "folded:". A missing
  # row, any matching row that fails, or anything else is 14.
  verdict=$(tr -d '\r' < "$fold" | LC_ALL=C awk -F '|' -v s="$sid8" '
    function trim(x) { gsub(/^[ \t]+|[ \t]+$/, "", x); return x }
    /^## / { on = ($0 ~ /^## Siblings[ \t]*$/); next }
    on && /^[ \t]*\|/ {
      if (trim($2) != s) next
      seen = 1
      cls = trim($3); res = $6
      for (i = 7; i < NF; i++) res = res "|" $i
      res = trim(res)
      if (cls != "SUPERSEDED" && cls != "DIVERGED") bad = bad " class=" cls
      else if (res !~ /^(nothing unique|folded:)/) bad = bad " result=" res
    }
    END { if (!seen) print "missing"; else if (bad != "") print "bad" bad; else print "ok" }')
  case $verdict in
    ok) ;;
    missing) flag 14 "no ## Siblings row for $sid8 in ${fold##*/}" ;;
    *) flag 14 "$sid8 is not folded in ${fold##*/} (${verdict#bad }; want SUPERSEDED or DIVERGED, and nothing unique or folded:)" ;;
  esac
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
