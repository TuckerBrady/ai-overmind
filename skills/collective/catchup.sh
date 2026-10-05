#!/usr/bin/env bash
# skills/collective/catchup.sh: list the posts this sweep must process
# (CONTRACT 5.8, 5.9; COL-9, COL-12, COL-13). Order is git order on a git
# venue and set membership elsewhere, never filename order.
#
#   catchup.sh git <binder-clone> <cid>
#       From the PRIVATE ack (state.sh ack), not the shared ledger, to HEAD:
#       added, modified and renamed posts, oldest commit first, one per line:
#         NEW <commit> <path>
#         EDITED <commit> <path>                 (a post changed after posting)
#         EDITED <commit> <path> renamed-from <old-path>
#       If the ack is not an ancestor of HEAD, prints "history rewritten" and
#       exits 3: act on nothing from the rewritten range; tell the human.
#   catchup.sh folder <posts-dir> <ledger-file>
#       Every post whose ID is not in the ledger's Processed list, as
#         NEW <post-id>
#       A legacy "floor:" line is not trusted as a filename cut-off: posts
#       under it are still listed unless their ID is in the list (COL-13).
#
# Any post named more than 10 minutes ahead of this clock is also flagged on
# stderr ("FUTURE <id>"); it is still listed, only ignored for naming.
# Exit: 0 ok, 2 usage, 3 history rewritten or no private ack.
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

usage() { die 2 "usage: catchup.sh git <binder-clone> <cid> | folder <posts-dir> <ledger-file>"; }

now=$(stamp_min "$(now_stamp)")
flag_future() {
  local s
  s=$(post_stamp "$1") || return 0
  [ "$(stamp_min "$s")" -gt $(( now + 10 )) ] && printf 'FUTURE %s: named more than 10 minutes ahead; ignored for naming\n' "${1##*/}" >&2
  return 0
}

case ${1:-} in
  git)
    [ $# -eq 3 ] || usage
    repo=$2 cid=$3
    d=$(state_dir "$cid") || exit 2
    [ -f "$d/ack" ] || die 3 "no private ack for this Collective: set one with state.sh ack before the first sweep"
    IFS= read -r ack < "$d/ack"; ack=${ack%$'\r'}
    is_hex "$ack" 40 || die 3 "private ack is malformed"
    if ! git -C "$repo" merge-base --is-ancestor "$ack" HEAD 2>/dev/null; then
      echo "history rewritten"
      exit 3
    fi
    commit=""
    git -C "$repo" log --reverse --diff-filter=AMR --name-status --format='commit %H' "$ack..HEAD" -- posts/ |
    while IFS= read -r l || [ -n "$l" ]; do
      l=${l%$'\r'}
      case $l in
        'commit '*) commit=${l#commit } ;;
        '') ;;
        A$'\t'*) p=${l#*$'\t'}; flag_future "$p"; echo "NEW $commit $p" ;;
        M$'\t'*) p=${l#*$'\t'}; echo "EDITED $commit $p" ;;
        R*$'\t'*$'\t'*) r=${l#*$'\t'}; old=${r%%$'\t'*}; p=${r#*$'\t'}; echo "EDITED $commit $p renamed-from $old" ;;
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
      echo "NEW $id"
    done
    ;;

  *) usage ;;
esac
