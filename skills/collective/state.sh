#!/usr/bin/env bash
# skills/collective/state.sh: this Overmind's private Collective state
# (CONTRACT 5.5, A-23, A-24). Files under ~/.claude/overmind/collective/<cid>/
# are authoritative: pins/ (peers' public keys), allowed_signers (built from
# the pins), ack (the commit this Overmind last read), events. SEATS.md and the
# shared ledgers are compared against them; a difference is reported and never
# adopted. Nothing here writes a binder.
#
#   state.sh pin-github <cid> <label> <pubkey-file> <github-user>
#       The primary path. Run on this human's yes. Pins only when the key is
#       among <github-user>'s SSH signing keys on GitHub (fetched with gh api,
#       else curl); any fetch or parse failure pins nothing.
#   state.sh pin <cid> <label> <pubkey-file> <fingerprint-confirmed-out-of-band>
#       The fallback, for a peer without a usable GitHub account. Run only
#       after the two humans compared the fingerprint outside the venue AND
#       this human said yes. The pasted fingerprint must match the key.
#   state.sh pin-self <cid> <label>     pin this Overmind's own key under its label
#   state.sh unpin <cid> <label>        drop a pin (the human's call, e.g. a lost key)
#   state.sh pins <cid>                 list label, fingerprint, source (github:<user> | oob | self)
#   state.sh ack <cid> <commit-sha>     record the commit this sweep read up to
#   state.sh ack-get <cid>              print it
#   state.sh seed-ack <cid> <clone> <my-label> <ledger-path>
#       first v5 sweep: the last commit to this Overmind's own ledger that is
#       signed by its own pinned key (N4). None: confirm HEAD with the human.
#   state.sh event <cid> <text>         append to the private event log
#   state.sh check-seats <cid> <SEATS.md>   compare the binder's Keys table with the pins
#   state.sh check-ledger <cid> <ledger>    compare a shared ledger's acked-commit
#
# Labels are compared case-folded with punctuation stripped (N5); a label that
# collides with a different pinned label is a lookalike and is refused.
# Exit: 0 ok or no difference, 1 difference or refused, 2 usage, 3 missing state.
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
umask 077

usage() { die 2 "usage: state.sh pin|pin-github|pin-self|unpin|pins|ack|ack-get|seed-ack|event|check-seats|check-ledger <cid> ..."; }

cmd=${1:-}
[ $# -ge 2 ] || usage
shift
cid=$1; shift
d=$(state_dir "$cid") || exit 2

trim() { local x=$1; x=${x#"${x%%[! ]*}"}; x=${x%"${x##*[! ]}"}; printf '%s' "$x"; }

# do_pin LABEL PUBFILE SOURCE: shared by pin, pin-github and pin-self. SOURCE
# is recorded in pins/<n>.source: github:<user>, oob or self.
do_pin() {
  local raw=$1 pub=$2 src=$3 n fp other
  n=$(label_norm "$raw"); fp=$(fingerprint "$pub")
  mkdir -p "$d/pins" || die 3 "cannot create $d/pins"
  if [ -f "$d/pins/$n.label" ]; then
    IFS= read -r other < "$d/pins/$n.label"
    [ "$other" = "$raw" ] || die 1 "REFUSED: '$raw' is a lookalike of the pinned label '$other'"
  fi
  if [ -f "$d/pins/$n.pub" ]; then
    [ "$(key_body "$d/pins/$n.pub")" = "$(key_body "$pub")" ] && { echo "already pinned: $raw $fp"; return 0; }
    die 1 "REFUSED: a different key is pinned for '$raw'; replacing it needs unpin first, on the human's word"
  fi
  for other in "$d"/pins/*.pub; do
    [ -f "$other" ] || continue
    [ "$(key_body "$other")" = "$(key_body "$pub")" ] && die 1 "REFUSED: this key is already pinned under another label (${other##*/})"
  done
  key_body "$pub" | write_atomic "$d/pins/$n.pub" || die 3 "cannot write the pin"
  printf '%s\n' "$raw" | write_atomic "$d/pins/$n.label"
  printf '%s\n' "$src" | write_atomic "$d/pins/$n.source"
  allowed_signers "$cid"
  case $src in
    github:*) event "$d" "pinned $raw via $src $fp" ;;
    *) event "$d" "pinned $raw ($n) $fp" ;;
  esac
  echo "pinned: $raw $fp"
}

case $cmd in
  pin)
    [ $# -eq 3 ] || usage
    label_ok "$1" || die 2 "labels must be plain ASCII letters, digits, space and . _ ( ) , -"
    pubkey_ok "$2" || die 2 "not a single ssh-ed25519 public key: $2"
    fp=$(fingerprint "$2")
    [ "$3" = "$fp" ] || die 1 "REFUSED: the key's fingerprint is $fp, not the one confirmed out of band ($3). Not pinned."
    do_pin "$1" "$2" oob
    ;;

  pin-github)
    [ $# -eq 3 ] || usage
    label_ok "$1" || die 2 "labels must be plain ASCII letters, digits, space and . _ ( ) , -"
    gh_user_ok "$3" || die 2 "not a GitHub user name: $3 (letters, digits and -, at most 39, no leading or trailing -)"
    pubkey_ok "$2" || die 2 "not a single ssh-ed25519 public key: $2"
    want=$(key_body "$2")
    gt=$(mktemp -d "${TMPDIR:-/tmp}/ovmgh.XXXXXX") || die 3 "cannot make a temp dir"
    if ! gh_fetch_signing_keys "$3" "$gt/keys"; then
      rm -rf "$gt"; die 1 "REFUSED: could not fetch $3's GitHub signing keys. Not pinned."
    fi
    if ! gh_key_bodies "$gt/keys" > "$gt/bodies"; then
      rm -rf "$gt"; die 1 "REFUSED: GitHub's answer for $3 is not a key list. Not pinned."
    fi
    if [ ! -s "$gt/bodies" ]; then
      rm -rf "$gt"; die 1 "REFUSED: $3 has no ssh-ed25519 signing keys on GitHub. Not pinned."
    fi
    found=0
    while IFS= read -r kb; do
      [ "$kb" = "$want" ] && { found=1; break; }
    done < "$gt/bodies"
    rm -rf "$gt"
    [ "$found" -eq 1 ] || die 1 "REFUSED: key not among $3's GitHub signing keys. Not pinned."
    do_pin "$1" "$2" "github:$3"
    ;;

  pin-self)
    [ $# -eq 1 ] || usage
    label_ok "$1" || die 2 "bad label"
    k=$(key_file)
    [ -f "$k.pub" ] || die 3 "no key: run identity.sh mint"
    do_pin "$1" "$k.pub" self
    ;;

  unpin)
    [ $# -eq 1 ] || usage
    n=$(label_norm "$1")
    [ -f "$d/pins/$n.pub" ] || die 3 "no pin for $1"
    rm -f "$d/pins/$n.pub" "$d/pins/$n.label" "$d/pins/$n.source" "$d/pending/$n"
    allowed_signers "$cid"
    event "$d" "unpinned $1 ($n)"
    echo "unpinned: $1"
    ;;

  pins)
    for p in "$d"/pins/*.pub; do
      [ -f "$p" ] || continue
      n=${p##*/}; n=${n%.pub}
      IFS= read -r raw < "$d/pins/$n.label" 2>/dev/null || raw=$n
      src=""
      [ -f "$d/pins/$n.source" ] && IFS= read -r src < "$d/pins/$n.source"
      printf '%s\t%s\t%s\n' "$raw" "$(fingerprint "$p")" "${src:-oob}"
    done
    ;;

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

  seed-ack)
    [ $# -eq 3 ] || usage
    clone=$1 me=$(label_norm "$2") ledger=$3
    [ -f "$d/pins/$me.pub" ] || die 3 "pin your own key first (state.sh pin-self)"
    for c in $(git -C "$clone" log --format=%H -- "$ledger" 2>/dev/null); do
      s=$(commit_signer "$clone" "$cid" "$c") || continue
      if [ "$s" = "$me" ]; then
        mkdir -p "$d"
        printf '%s\n' "$c" | write_atomic "$d/ack"
        event "$d" "ack seeded from own signed ledger commit $c"
        echo "seeded: $c"
        exit 0
      fi
    done
    echo "NONE: no commit to $ledger is signed by your own pinned key. Show the human HEAD and, on a yes, run state.sh ack with it."
    exit 1
    ;;

  event)
    [ $# -eq 1 ] || usage
    mkdir -p "$d" || die 3 "cannot create $d"
    event "$d" "$1"
    ;;

  check-seats)
    [ $# -eq 1 ] || usage
    [ -f "$1" ] || die 3 "no such file: $1"
    diff=0 in=0 seen="|"
    while IFS= read -r l || [ -n "$l" ]; do
      l=${l%$'\r'}
      case $l in
        '## Keys'*) in=1; continue ;;
        '## '*) in=0; continue ;;
      esac
      [ "$in" -eq 1 ] || continue
      case $l in '|'*) ;; *) continue ;; esac
      row=$(printf '%s' "$l" | tr -d '`')
      IFS='|' read -r _ c1 c2 c3 _ <<EOF
$row
EOF
      raw=$(trim "$c1"); fp=$(trim "$c2"); key=$(trim "$c3")
      case $raw in ''|Overmind|-*) continue ;; esac
      n=$(label_norm "$raw")
      [ -n "$n" ] || continue
      if [ -f "$d/pins/$n.pub" ]; then
        IFS= read -r praw < "$d/pins/$n.label"
        seen="$seen$n|"
        if [ "$praw" != "$raw" ]; then
          echo "LOOKALIKE $raw: collides with pinned label '$praw'. Not adopted."; diff=1
        elif [ "$key" != "$(key_body "$d/pins/$n.pub")" ] || [ "$fp" != "$(fingerprint "$d/pins/$n.pub")" ]; then
          echo "DIFFERS $raw: SEATS.md shows $fp; the pin is $(fingerprint "$d/pins/$n.pub"). Not adopted."; diff=1
        fi
      else
        echo "UNPINNED $raw: in SEATS.md, not pinned here. Pin only on the human's yes: state.sh pin-github, or pin after an out-of-band fingerprint check."
      fi
    done < "$1"
    for p in "$d"/pins/*.pub; do
      [ -f "$p" ] || continue
      n=${p##*/}; n=${n%.pub}
      case $seen in *"|$n|"*) ;; *) IFS= read -r praw < "$d/pins/$n.label"; echo "MISSING $praw: pinned here, absent from SEATS.md."; diff=1 ;; esac
    done
    [ "$diff" -eq 1 ] && event "$d" "SEATS.md differs from the pins; reported, not adopted"
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
