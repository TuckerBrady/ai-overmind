#!/usr/bin/env bash
# skills/collective/state.sh: this Overmind's private Collective state
# (CONTRACT 5.5). The files under ~/.claude/overmind/collective/<cid>/ are
# authoritative. SEATS.md and the shared ledger are compared against them;
# a difference is reported and never adopted. Nothing here writes the binder.
#
#   state.sh ack <cid> <commit-sha>       record the commit this sweep read up to
#   state.sh ack-get <cid>                print the recorded commit
#   state.sh event <cid> <text>           append a line to the private event log
#   state.sh check-seats <cid> <SEATS.md> compare the binder's Genesis chain record
#   state.sh check-ledger <cid> <ledger>  compare a shared ledger's acked-commit
#
# Exit: 0 ok or no difference, 1 difference found, 2 usage, 3 missing state.
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
umask 077

usage() { die 2 "usage: state.sh ack|ack-get|event|check-seats|check-ledger <cid> ..."; }

cmd=${1:-}
[ $# -ge 2 ] || usage
shift
cid=$1; shift
d=$(state_dir "$cid") || exit 2

trim() { local x=$1; x=${x#"${x%%[! ]*}"}; x=${x%"${x##*[! ]}"}; printf '%s' "$x"; }

case $cmd in
  ack)
    [ $# -eq 1 ] || usage
    is_hex "$1" 40 || die 2 "commit must be a full 40-hex sha"
    mkdir -p "$d" || die 3 "cannot create $d"
    printf '%s\n' "$1" | write_atomic "$d/ack" || die 3 "cannot write $d/ack"
    event "$d" "ack advanced to $1"
    ;;

  ack-get)
    [ -f "$d/ack" ] || die 3 "no private ack for this Collective"
    IFS= read -r a < "$d/ack"; printf '%s\n' "${a%$'\r'}"
    ;;

  event)
    [ $# -eq 1 ] || usage
    mkdir -p "$d" || die 3 "cannot create $d"
    event "$d" "$1"
    ;;

  check-seats)
    [ $# -eq 1 ] || usage
    [ -f "$1" ] || die 3 "no such file: $1"
    [ -f "$d/accepted" ] || die 3 "no accepted chains for this Collective"
    diff=0 in=0 seen=""
    while IFS= read -r l || [ -n "$l" ]; do
      l=${l%$'\r'}
      case $l in
        '## Genesis chain record'*) in=1; continue ;;
        '## '*) in=0; continue ;;
      esac
      [ "$in" -eq 1 ] || continue
      case $l in '|'*) ;; *) continue ;; esac
      row=$(printf '%s' "$l" | tr -d '`')
      IFS='|' read -r _ c1 c2 c3 c4 c5 _ <<EOF
$row
EOF
      name=$(trim "$c1"); g=$(trim "$c3"); i=$(trim "$c4"); v=$(trim "$c5")
      case $name in ''|Overmind|-*) continue ;; esac
      if accepted_get "$d" "$name"; then
        seen="$seen|$name|"
        if [ "$g" != "$ACC_GEN" ] || [ "$i" != "$ACC_INDEX" ] || [ "$v" != "$ACC_VALUE" ]; then
          echo "DIFFERS $name: SEATS.md has gen $g index $i value $v; private state has gen $ACC_GEN index $ACC_INDEX value $ACC_VALUE. Not adopted."
          diff=1
        fi
      else
        echo "UNTRACKED $name: in SEATS.md, never accepted by this Overmind. Not adopted."
      fi
    done < "$1"
    tab=$(printf '\t')
    while IFS="$tab" read -r p _ || [ -n "$p" ]; do
      case $seen in *"|$p|"*) ;; *) echo "MISSING $p: accepted here, absent from SEATS.md."; diff=1 ;; esac
    done < "$d/accepted"
    [ "$diff" -eq 1 ] && event "$d" "SEATS.md differs from private state; reported, not adopted"
    exit "$diff"
    ;;

  check-ledger)
    [ $# -eq 1 ] || usage
    [ -f "$1" ] || die 3 "no such file: $1"
    [ -f "$d/ack" ] || die 3 "no private ack for this Collective"
    IFS= read -r mine < "$d/ack"; mine=${mine%$'\r'}
    theirs=""
    while IFS= read -r l || [ -n "$l" ]; do
      l=${l%$'\r'}
      case $l in '**acked-commit:**'*) theirs=$(trim "${l#'**acked-commit:**'}"); break ;; esac
    done < "$1"
    if [ "$theirs" = "$mine" ]; then echo "same"; exit 0; fi
    echo "DIFFERS: shared ledger says ${theirs:-nothing}; private ack is $mine. Not adopted."
    event "$d" "shared ledger acked-commit differs from private ack; reported, not adopted"
    exit 1
    ;;

  *) usage ;;
esac
