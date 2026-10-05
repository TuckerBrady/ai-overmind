#!/usr/bin/env bash
# guard.sh --session <id> --running <0|1> --fold <file> [--worktree <path>]...
#
# /consolidate's pre-archive guard (CONTRACT 6.9, GAP-45, amendment A-34).
# Archiving a desktop session stops it and, by default, deletes its worktree,
# so a sibling is archived only when this exits 0.
#
# The check is an outcome invariant, not a list of git states:
#
#   Everything archiving would delete must already be recoverable from what
#   is on a remote. Every file on disk under the worktree (resolved to its
#   toplevel) must exist as a blob reachable from a remote-tracking ref, and
#   every commit on any local ref, refs/worktree/*, refs/bisect/* and every
#   stash entry must be reachable from the remote-tracking refs. Content in
#   the index counts too. Any nested repository (a .git directory or file
#   anywhere below, in a build directory or not) is checked the same way.
#
# Skipped: the toplevel's .git, and a directory named node_modules, dist,
# build, .next, target, __pycache__ or .venv that sits beside the manifest
# that rebuilds it (package.json, Cargo.toml, pyproject.toml, ...) and holds
# no .git anywhere inside.
#
# Nothing a repository configures can run. The guard uses plumbing only
# (rev-parse, for-each-ref, rev-list, ls-files -s, hash-object --no-filters)
# and never git status, diff or submodule, so no filter driver, hook or
# fsmonitor is ever invoked. Files are hashed byte for byte; a file that only
# differs by line endings is hashed a second time in an empty sandbox
# repository with no system or global config, where no filter driver exists.
#
# It trusts remote-tracking refs as they are on disk (A-28): the remote is
# never contacted, because that would run the repo's ssh and credential
# programs. A stale or hand-written refs/remotes/... ref makes content look
# pushed.
#
# Every check runs; the exit code is the LOWEST failing code:
#   0  pass: safe to archive (still only after the human's yes this session)
#   10 running: the session is mid-turn or has live background work
#   11 a file no remote holds (up to 20 paths and the count are printed), or
#      a nested repository with no remote at all
#   12 a commit no remote holds: on a local branch, tag, HEAD, refs/worktree,
#      refs/bisect or the stash
#   13 open PR on the worktree's branch with no fold note (a PR comment
#      containing the fold file's basename)
#   14 not folded: the fold file is missing, or has no Siblings row whose
#      Session is exactly this sid8 with Class SUPERSEDED or DIVERGED and
#      Result "nothing unique" or "folded: ...", or fails invariant.sh
#   15 cannot verify: not a git work tree, no remote-tracking refs, a path
#      that cannot be read or holds a newline, more than 200000 files, or a
#      branch has a GitHub upstream and gh is missing, unauthenticated or
#      failing
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

MAXFILES=200000
nl='
'
# Plumbing only, and still hardened: no fsmonitor, no hooks, no pager, no
# automatic gc or maintenance, no optional index locks.
g() {
  git --no-optional-locks -c core.fsmonitor=false -c core.hooksPath=/dev/null \
    -c core.pager=cat -c gc.auto=0 -c maintenance.auto=false -C "$@"
}
tmpd=$(mktemp -d "${TMPDIR:-/tmp}/guard.XXXXXX") || exit 15
trap 'rm -rf "$tmpd"' EXIT

codes=""
flag() { codes="$codes $1"; echo "guard: $1 $2"; }

# --- the invariant, for one repository and (recursively) the ones inside it ------
ctn=0
check_tree() { # $1 directory, $2 1 if this is a nested repository
  local dir=$1 nested=$2 top f extras stashlog ahead fmt rc nmiss nested_roots r
  ctn=$((ctn + 1)); f="$tmpd/ct$ctn"
  top=$(g "$dir" rev-parse --show-toplevel 2>/dev/null)
  if [ -z "$top" ] || [ ! -d "$top" ]; then
    flag 15 "not a git work tree: $dir"; return
  fi
  if [ -z "$(g "$top" for-each-ref --count=1 --format=x refs/remotes 2>/dev/null)" ]; then
    if [ "$nested" = 1 ]; then flag 11 "nested repository with no remote at all: $top"
    else flag 15 "no remote-tracking refs to verify against: $top"; fi
    return
  fi

  # Refs: every local ref, the per-worktree refs, and every stash entry (the
  # stash reflog, not only its tip) must be reachable from the remotes.
  g "$top" for-each-ref --format='%(objectname)' refs/worktree refs/bisect > "$f.extra" 2>/dev/null
  stashlog=$(g "$top" rev-parse --git-path logs/refs/stash 2>/dev/null)
  case $stashlog in /*|?:/*) ;; ?*) stashlog="$top/$stashlog" ;; esac
  if [ -n "$stashlog" ] && [ -f "$stashlog" ]; then
    LC_ALL=C awk '$2 ~ /^[0-9a-f]+$/ && (length($2) == 40 || length($2) == 64) { print $2 }' "$stashlog" >> "$f.extra"
  fi
  # --not before --stdin leaves the stdin revisions positive.
  ahead=$(g "$top" rev-list --count --all --not --remotes --stdin < "$f.extra" 2>/dev/null); rc=$?
  case $rc:$ahead in
    0:0) ;;
    0:*[!0-9]*|0:|[!0]*) flag 15 "cannot walk the refs of $top" ;;
    *) flag 12 "$ahead commit(s) no remote holds (local branches, tags, HEAD, refs/worktree, refs/bisect, stash) in $top" ;;
  esac

  # Files. Three walks, no git involved: the .git entries below the toplevel
  # (nested repositories), the allow-listed directory names, and every file
  # and symlink. Nothing is pruned except .git, so nested repositories
  # inside build directories are found.
  if [ -n "$(cd "$top" && find . -path ./.git -prune -o -name "*$nl*" -print 2>/dev/null | head -n 1)" ]; then
    flag 15 "a path below $top holds a newline; cannot verify"; return
  fi
  # Walks run from inside the toplevel, so no character in its path can act
  # as a -path pattern.
  ( cd "$top" && find . -path ./.git -prune -o -name .git -prune -print ) > "$f.git" 2> "$f.err1"
  ( cd "$top" && find . -name .git -prune -o -type d \( -name node_modules -o -name dist -o -name build \
    -o -name .next -o -name target -o -name __pycache__ -o -name .venv \) -print ) > "$f.dirs" 2> "$f.err2"
  ( cd "$top" && find . -name .git -prune -o -type f -print ) > "$f.files" 2> "$f.err3"
  ( cd "$top" && find . -name .git -prune -o -type l -print ) > "$f.links" 2> "$f.err4"
  if [ -s "$f.err1" ] || [ -s "$f.err2" ] || [ -s "$f.err3" ] || [ -s "$f.err4" ]; then
    flag 15 "cannot read every path below $top: $(head -n 1 "$f.err1" "$f.err2" "$f.err3" "$f.err4" 2>/dev/null | LC_ALL=C grep -v '^==>' | LC_ALL=C grep . | head -n 1)"
    return
  fi
  # Classify (relative paths). Out: $f.keep (files to verify), $f.klinks
  # (symlinks to verify), $f.nested (outermost nested repositories),
  # $f.skipped (rebuildable directories left out).
  LC_ALL=C awk -v top="./" -v f="$f" '
    function rel(p) { return substr(p, length(top) + 1) }
    function parent(p) { return (p ~ /\//) ? substr(p, 1, match(p, /\/[^\/]*$/) - 1) : "" }
    function under(p, set,   q) { q = p; while (q != "") { if (q in set) return 1; q = parent(q) } return 0 }
    FILENAME ~ /\.git$/   { n = rel($0); n = parent(n); if (n != "") NR_[n] = 1; next }
    FILENAME ~ /\.dirs$/  { D[rel($0)] = 1; next }
    FILENAME ~ /\.files$/ { r = rel($0); F[r] = 1; FO[++nf] = r
                            if (r ~ /\.py$/) PY[parent(r)] = 1; next }
    FILENAME ~ /\.links$/ { LO[++nl] = rel($0); next }
    END {
      M["node_modules"] = "package.json"; M[".next"] = "package.json"
      M["dist"] = "package.json pyproject.toml setup.py setup.cfg Cargo.toml go.mod pom.xml build.gradle build.gradle.kts"
      M["build"] = M["dist"]
      M["target"] = "Cargo.toml pom.xml build.sbt"
      M[".venv"] = "pyproject.toml requirements.txt setup.py setup.cfg Pipfile poetry.lock"
      M["__pycache__"] = "pyproject.toml setup.py setup.cfg requirements.txt"
      # outermost nested repositories
      for (n in NR_) { if (!under(parent(n), NR_)) { OUT[n] = 1; print n > (f ".nested") } }
      # a nested repository anywhere inside a directory taints all its ancestors
      for (n in NR_) { q = parent(n); while (q != "") { HASGIT[q] = 1; q = parent(q) } }
      for (d in D) {
        if (d in HASGIT || d in NR_) continue
        last = d; sub(/.*\//, "", last); par = parent(d)
        ok = 0; k = split(M[last], ms, " ")
        for (i = 1; i <= k; i++) if (((par == "" ? "" : par "/") ms[i]) in F) ok = 1
        if (last == "__pycache__" && (par in PY)) ok = 1
        if (ok) SKIP[d] = 1
      }
      for (d in SKIP) if (!under(parent(d), SKIP)) print d > (f ".skipped")
      for (i = 1; i <= nf; i++) { r = FO[i]; if (under(parent(r), OUT) || under(parent(r), SKIP)) continue; print r > (f ".keep") }
      for (i = 1; i <= nl; i++) { r = LO[i]; if (under(parent(r), OUT) || under(parent(r), SKIP)) continue; print r > (f ".klinks") }
    }' "$f.git" "$f.dirs" "$f.files" "$f.links"
  touch "$f.keep" "$f.klinks" "$f.nested" "$f.skipped"
  if [ "$(wc -l < "$f.keep" | tr -d ' ')" -gt "$MAXFILES" ]; then
    flag 15 "more than $MAXFILES files below $top; too large to verify"; return
  fi
  LC_ALL=C sort "$f.skipped" | head -n 20 | while IFS= read -r r; do echo "guard: skipped (rebuildable) $r in $top"; done
  n=$(wc -l < "$f.skipped" | tr -d ' ')
  [ "$n" -gt 20 ] && echo "guard: skipped (rebuildable) ...and $((n - 20)) more in $top"

  # The blobs the remotes hold.
  if ! g "$top" rev-list --objects --remotes > "$f.robj" 2>/dev/null; then
    flag 15 "cannot list the objects the remotes hold in $top"; return
  fi
  LC_ALL=C awk '{ print $1 }' "$f.robj" > "$f.remote"

  # Hash every file byte for byte.
  : > "$f.h1"
  if [ -s "$f.keep" ] && ! g "$top" hash-object --no-filters --stdin-paths < "$f.keep" > "$f.h1" 2> "$f.err5"; then
    flag 15 "cannot read every file below $top: $(head -n 1 "$f.err5")"; return
  fi
  # Symlinks: the blob is the link text.
  : > "$f.lk"
  while IFS= read -r r; do
    printf '%s\t%s\n' "$(readlink "$top/$r" | g "$top" hash-object --no-filters --stdin 2>/dev/null)" "$r" >> "$f.lk"
  done < "$f.klinks"
  # Files whose bytes are not on a remote.
  LC_ALL=C awk -v f="$f" 'FILENAME == f ".remote" { R[$1] = 1; next }
    FILENAME == f ".keep" { P[FNR] = $0; next }
    FILENAME == f ".h1" { if (!($1 in R)) print P[FNR] }' "$f.remote" "$f.keep" "$f.h1" > "$f.miss1"
  # A second look at those, as git add would store them on this platform
  # (line endings), in an empty sandbox: no repository config, no system or
  # global config, so no filter driver exists to run.
  : > "$f.miss2"
  if [ -s "$f.miss1" ]; then
    fmt=$(g "$top" rev-parse --show-object-format 2>/dev/null); fmt=${fmt:-sha1}
    if [ ! -d "$tmpd/sandbox-$fmt.git" ]; then
      GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null HOME="$tmpd" \
        git init -q --bare --object-format="$fmt" "$tmpd/sandbox-$fmt.git" > /dev/null 2>&1
    fi
    ( cd "$top" && GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_ATTR_NOSYSTEM=1 HOME="$tmpd" \
        GIT_DIR="$tmpd/sandbox-$fmt.git" GIT_WORK_TREE=. \
        git -c core.autocrlf=true -c core.safecrlf=false -c core.fsmonitor=false -c core.hooksPath=/dev/null \
        hash-object --stdin-paths < "$f.miss1" ) > "$f.h2" 2> /dev/null || : > "$f.h2"
    LC_ALL=C awk -v f="$f" 'FILENAME == f ".remote" { R[$1] = 1; next }
      FILENAME == f ".miss1" { P[FNR] = $0; n = FNR; next }
      FILENAME == f ".h2" { H[FNR] = $1 }
      END { for (i = 1; i <= n; i++) if (!(H[i] in R)) print P[i] }' "$f.remote" "$f.miss1" "$f.h2" > "$f.miss2"
  fi
  LC_ALL=C awk -v f="$f" 'FILENAME == f ".remote" { R[$1] = 1; next }
    { split($0, a, "\t"); if (!(a[1] in R)) print a[2] }' "$f.remote" "$f.lk" >> "$f.miss2"
  # Content staged in the index (it goes with the worktree too).
  g "$top" ls-files -s -z 2>/dev/null | LC_ALL=C tr '\0' '\n' |
    LC_ALL=C awk -v f="$f" 'FILENAME == f ".remote" { R[$1] = 1; next }
      { split($0, a, "\t"); split(a[1], m, " "); if (m[1] != "160000" && !(m[2] in R)) print a[2] " (staged)" }' "$f.remote" - >> "$f.miss2"
  nmiss=$(LC_ALL=C sort -u "$f.miss2" | LC_ALL=C grep -c .)
  if [ "$nmiss" -gt 0 ]; then
    flag 11 "$nmiss file(s) no remote holds in $top; archiving would delete them:"
    LC_ALL=C sort -u "$f.miss2" | head -n 20 | sed 's/^/guard:     /'
  fi

  # Each outermost nested repository, the same way.
  while IFS= read -r r; do
    [ -n "$r" ] && check_tree "$top/$r" 1
  done < "$f.nested"
}

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
  if [ ! -d "$wt" ]; then flag 15 "not a git work tree: $wt"; continue; fi
  check_tree "$wt" 0
  top=$(g "$wt" rev-parse --show-toplevel 2>/dev/null)
  [ -n "$top" ] || continue
  branch=$(g "$top" symbolic-ref -q --short HEAD 2>/dev/null)
  [ -n "$branch" ] || continue
  remote=$(g "$top" config --get "branch.$branch.remote" 2>/dev/null)
  # No upstream set: a PR can still be open on this branch at origin.
  [ -n "$remote" ] || remote=origin
  url=$(g "$top" config --get "remote.$remote.url" 2>/dev/null)
  case $url in *github.com[:/]*) ;; *) continue ;; esac
  repo=${url#*github.com}; repo=${repo#[:/]}; repo=${repo%.git}; repo=${repo%/}
  case $repo in *[!A-Za-z0-9_./-]*|*/*/*|/*|*..*|'') flag 15 "cannot parse GitHub repo from the upstream of $branch"; continue ;; esac
  merge=$(g "$top" config --get "branch.$branch.merge" 2>/dev/null); merge=${merge:-refs/heads/$branch}; head=${merge#refs/heads/}
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
