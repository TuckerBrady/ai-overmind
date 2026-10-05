#!/usr/bin/env bash
# skills/collective/catchup.sh: sync and list the posts this sweep must process
# (CONTRACT 5.8, 5.9, A-23, A-24; COL-9, COL-12, COL-13, M1, M2, N2). Order is
# git order on a git venue and set membership elsewhere, never filename order.
#
#   catchup.sh git <binder-clone> <cid> [<branch>]
#       git fetch, then require the PRIVATE ack (state.sh ack) to be an
#       ancestor of origin/<branch> and fast-forward with --ff-only; anything
#       else prints "history rewritten", exits 3 and moves nothing. Then lists
#       first-parent changes to posts/ since the ack, oldest first:
#         NEW <commit> <author> <path>
#         EDITED <commit> <author> <path> [renamed-from <old-path>]
#         DELETED <commit> <author> <path>
#       <author> is verified:<label> only when `git verify-commit` passes
#       against allowed_signers built from this Overmind's pins; otherwise
#       unverified. GitHub's verified flag and logins never count.
#   catchup.sh folder <posts-dir> <ledger-file>
#       Every post whose ID is not in the ledger's Processed list, as
#         NEW <post-id> unverified
#       A legacy "floor:" line is not trusted as a filename cut-off: posts
#       under it are still listed unless their ID is in the list (COL-13).
#
# Any post named more than 10 minutes ahead of this clock is also flagged on
# stderr ("FUTURE <id>"); it is still listed, only ignored for naming.
# Exit: 0 ok, 2 usage, 3 history rewritten, no private ack, or no fast-forward.
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

usage() { die 2 "usage: catchup.sh git <binder-clone> <cid> [<branch>] | folder <posts-dir> <ledger-file>"; }

now=$(stamp_min "$(now_stamp)")
flag_future() {
  local s
  s=$(post_stamp "$1") || return 0
  [ "$(stamp_min "$s")" -gt $(( now + 10 )) ] && printf 'FUTURE %s: named more than 10 minutes ahead; ignored for naming\n' "${1##*/}" >&2
  return 0
}

case ${1:-} in
  git)
    [ $# -ge 3 ] && [ $# -le 4 ] || usage
    repo=$2 cid=$3
    d=$(state_dir "$cid") || exit 2
    [ -f "$d/ack" ] || die 3 "no private ack for this Collective: seed one with state.sh seed-ack before the first sweep"
    IFS= read -r ack < "$d/ack"; ack=${ack%$'\r'}
    is_hex "$ack" 40 || die 3 "private ack is malformed"
    branch=${4:-$(git -C "$repo" symbolic-ref --short HEAD 2>/dev/null)}
    [ -n "$branch" ] || die 2 "cannot tell the branch; pass it"
    git -C "$repo" fetch -q origin "$branch" 2>/dev/null || die 3 "git fetch failed"
    up="origin/$branch"
    git -C "$repo" update-ref "refs/remotes/$up" FETCH_HEAD 2>/dev/null
    if ! git -C "$repo" merge-base --is-ancestor "$ack" "$up" 2>/dev/null ||
       ! git -C "$repo" merge-base --is-ancestor HEAD "$up" 2>/dev/null ||
       ! git -C "$repo" merge -q --ff-only "$up" >/dev/null 2>&1; then
      echo "history rewritten"
      exit 3
    fi
    commit="" who=""
    git -C "$repo" log --reverse -m --first-parent --diff-filter=AMRD --name-status --format='commit %H' "$ack..HEAD" -- posts/ |
    while IFS= read -r l || [ -n "$l" ]; do
      l=${l%$'\r'}
      case $l in
        'commit '*) commit=${l#commit }
                    if s=$(commit_signer "$repo" "$cid" "$commit"); then who="verified:$s"; else who=unverified; fi ;;
        '') ;;
        A$'\t'*) p=${l#*$'\t'}; flag_future "$p"; echo "NEW $commit $who $p" ;;
        M$'\t'*) p=${l#*$'\t'}; echo "EDITED $commit $who $p" ;;
        D$'\t'*) p=${l#*$'\t'}; echo "DELETED $commit $who $p" ;;
        R*$'\t'*$'\t'*) r=${l#*$'\t'}; old=${r%%$'\t'*}; p=${r#*$'\t'}; echo "EDITED $commit $who $p renamed-from $old" ;;
      esac
    done
    ;;

  folder)
    [ $# -eq 3 ] || usage
    posts=$2 ledger=$3
    [ -d "$posts" ] || die 2 "no such directory: $posts"
    [ -f "$ledger" ] || die 2 "no such file: $ledger"
    done_ids="|"
    inlist=0
    while IFS= read -r l || [ -n "$l" ]; do
      l=${l%$'\r'}
      case $l in
        '## Processed'*) inlist=1 ;;
        '## '*) inlist=0 ;;
        '- '*) [ "$inlist" -eq 1 ] && done_ids="$done_ids${l#- }|" ;;
      esac
    done < "$ledger"
    for f in "$posts"/*.md; do
      [ -e "$f" ] || continue
      id=${f##*/}; id=${id%.md}
      case $done_ids in *"|$id|"*) continue ;; esac
      flag_future "$f"
      echo "NEW $id unverified"
    done
    ;;

  *) usage ;;
esac
