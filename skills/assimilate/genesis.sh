#!/usr/bin/env bash
# skills/assimilate/genesis.sh: the Genesis Seed and anchor-chain commitments
# (CONTRACT 5.4, 5.10, 5.11; formats in reference/collective.md "Formats").
#
# Holder side (this Overmind's own identity):
#   genesis.sh mint                      create ~/.claude/overmind/genesis-seed
#   genesis.sh anchor <cid> [g]          print the generation-g anchor record
#   genesis.sh renew <cid>               start the next generation, print its record
#   genesis.sh legacy-member <cid> <old-cid> <gen> <lowest-revealed>
#                                        register a pre-v5 chain this Overmind holds
# Verifier side (another Overmind's identity, kept in private state):
#   genesis.sh id                        Genesis ID of the record on stdin
#   genesis.sh accept <cid> <peer>       first anchor (trust on first use), record on stdin
#   genesis.sh accept-legacy <cid> <peer> <gen> <index> <value>
#                                        a pre-v5 chain value, once, marked legacy-uncommitted
#   genesis.sh verify-renewal <cid> <peer>
#                                        a next-generation record on stdin
#   genesis.sh legacy-rows <SEATS.md>    list a binder's pre-v5 chain rows for review
#
# Exit: 0 ok, 1 refused or failed verification, 2 usage, 3 missing state,
# 4 missing tool. Nothing here posts, pushes or reads the binder's state as
# authority: SEATS.md is only ever listed for the human (legacy-rows).
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../collective/lib.sh"
umask 077

usage() { die 2 "usage: genesis.sh mint|anchor|renew|legacy-member|id|accept|accept-legacy|verify-renewal|legacy-rows ..."; }

cmd=${1:-}
[ $# -ge 1 ] && shift

membership() { printf '%s/membership' "$(state_dir "$1")"; }

case $cmd in
  mint)
    f=$(seed_file)
    if s=$(seed_get seed); then
      is_hex "$s" 64 || die 1 "genesis-seed exists with a malformed seed: line; fix it by hand, never re-mint"
      echo "already minted"; exit 0
    fi
    mkdir -p "$(ovm_dir)" || die 3 "cannot create $(ovm_dir)"
    s=$(rand_hex 32)
    # Append, so a migrated pre-v5 file keeps its nonce: line.
    printf 'seed: %s\n' "$s" >> "$f" || die 3 "cannot write $f"
    chmod 600 "$f" 2>/dev/null
    echo "minted"
    ;;

  anchor)
    [ $# -ge 1 ] || usage
    cid=$1; d=$(state_dir "$cid") || exit 2
    if [ "$(kv_get "$(membership "$cid")" derivation 2>/dev/null)" = legacy-v2 ]; then
      die 1 "REFUSED: this membership is a pre-v5 chain; genesis.sh renew starts its committed generation"
    fi
    if [ $# -ge 2 ]; then
      g=$2
    else
      g=$(kv_get "$(membership "$cid")" generation) || g=1
    fi
    is_uint "$g" && [ "$g" -ge 1 ] || die 2 "generation must be a positive integer"
    seed_get seed >/dev/null || die 3 "no Genesis Seed: run genesis.sh mint first"
    mkdir -p "$d" || die 3 "cannot create $d"
    if [ ! -f "$(membership "$cid")" ]; then
      printf 'derivation: v5\ngeneration: %s\nlowest-revealed: 100\n' "$g" | write_atomic "$(membership "$cid")"
    fi
    record "$cid" "$g"
    ;;

  renew)
    [ $# -eq 1 ] || usage
    cid=$1; is_hex "$cid" 32 || die 2 "collective-id must be 32 lowercase hex characters"
    m=$(membership "$cid")
    [ -f "$m" ] || die 3 "no membership for $cid"
    g=$(kv_get "$m" generation) || die 3 "membership has no generation"
    seed_get seed >/dev/null || die 3 "no Genesis Seed: run genesis.sh mint first"
    ng=$(( g + 1 ))
    printf 'derivation: v5\ngeneration: %s\nlowest-revealed: 100\n' "$ng" | write_atomic "$m"
    record "$cid" "$ng"
    ;;

  legacy-member)
    [ $# -eq 4 ] || usage
    cid=$1 old=$2 g=$3 low=$4; d=$(state_dir "$cid") || exit 2
    is_uint "$g" && [ "$g" -ge 1 ] || die 2 "generation must be a positive integer"
    is_uint "$low" && [ "$low" -le 100 ] || die 2 "lowest-revealed must be 0-100"
    case $old in *[[:cntrl:]]*|*'|'*|'') die 2 "old collective-id must be printable, without |" ;; esac
    seed_get nonce >/dev/null || die 3 "no legacy nonce: line in the genesis-seed"
    mkdir -p "$d" || die 3 "cannot create $d"
    [ -f "$(membership "$cid")" ] && die 1 "membership already recorded for $cid"
    printf 'derivation: legacy-v2\nlegacy-cid: %s\ngeneration: %s\nlowest-revealed: %s\n' "$old" "$g" "$low" |
      write_atomic "$(membership "$cid")"
    echo "recorded"
    ;;

  id)
    parse_record || die 1 "not an anchor record"
    record_bytes | sha_hex | cut -c1-16
    ;;

  accept)
    [ $# -eq 2 ] || usage
    cid=$1 peer=$2; d=$(state_dir "$cid") || exit 2
    peer_ok "$peer" || die 2 "bad peer label"
    parse_record || die 1 "not an anchor record"
    mkdir -p "$d" || die 3 "cannot create $d"
    if accepted_get "$d" "$peer"; then die 1 "REFUSED: $peer already has an accepted chain; a new anchor needs verify-renewal"; fi
    [ -f "$d/legacy-used.$(peer_key "$peer")" ] && die 1 "REFUSED: $peer was accepted before; a new anchor needs verify-renewal"
    accepted_put "$d" "$peer" "$REC_GEN" 100 "$REC_ANCHOR" "$REC_NEXT" committed
    event "$d" "accepted first anchor for $peer gen $REC_GEN (trust on first use)"
    echo "accepted"
    ;;

  accept-legacy)
    [ $# -eq 5 ] || usage
    cid=$1 peer=$2 g=$3 i=$4 v=$5; d=$(state_dir "$cid") || exit 2
    peer_ok "$peer" || die 2 "bad peer label"
    is_uint "$g" && [ "$g" -ge 1 ] || die 2 "generation must be a positive integer"
    is_uint "$i" && [ "$i" -ge 1 ] && [ "$i" -le 100 ] || die 2 "index must be 1-100"
    is_hex "$v" 64 || die 2 "value must be 64 lowercase hex"
    mkdir -p "$d" || die 3 "cannot create $d"
    mark="$d/legacy-used.$(peer_key "$peer")"
    if accepted_get "$d" "$peer" || [ -f "$mark" ]; then
      die 1 "REFUSED: legacy-uncommitted is accepted once per peer; $peer must renew with a commitment"
    fi
    : > "$mark"
    accepted_put "$d" "$peer" "$g" "$i" "$v" - legacy-uncommitted
    event "$d" "accepted pre-v5 chain for $peer gen $g index $i as legacy-uncommitted"
    echo "accepted legacy-uncommitted"
    ;;

  verify-renewal)
    [ $# -eq 2 ] || usage
    cid=$1 peer=$2; d=$(state_dir "$cid") || exit 2
    peer_ok "$peer" || die 2 "bad peer label"
    parse_record || die 1 "FAIL: not an anchor record"
    accepted_get "$d" "$peer" || die 3 "FAIL: no accepted chain for $peer"
    [ "$REC_GEN" -eq $(( ACC_GEN + 1 )) ] || die 1 "FAIL: generation $REC_GEN, expected $(( ACC_GEN + 1 ))"
    key=$(peer_key "$peer")
    if [ "$ACC_STATUS" = committed ]; then
      h=$(sha_str "$REC_ANCHOR")
      [ "$h" = "$ACC_NEXT" ] || die 1 "FAIL: sha256(anchor) does not match the stored commitment"
    elif [ "$ACC_STATUS" = legacy-uncommitted ]; then
      # No commitment to check against: the renewal rides on a Proof A that
      # passed this round (proof.sh verify leaves a single-use marker).
      [ -f "$d/renew-ok.$key" ] || die 1 "FAIL: a legacy renewal needs a passing Proof A in the same round"
    else
      die 1 "FAIL: unknown accepted status $ACC_STATUS"
    fi
    rm -f "$d/renew-ok.$key"
    accepted_put "$d" "$peer" "$REC_GEN" 100 "$REC_ANCHOR" "$REC_NEXT" committed
    event "$d" "renewed $peer to gen $REC_GEN (committed)"
    echo "PASS"
    ;;

  legacy-rows)
    [ $# -eq 1 ] || usage
    [ -f "$1" ] || die 3 "no such file: $1"
    # The "## Genesis chain record" table: Overmind | Genesis ID | Generation |
    # Last accepted index | Last accepted value | Accepted. Backticks and
    # spaces are trimmed; rows without a 64-hex value (pending) are skipped.
    in=0
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
      trim() { local x=$1; x=${x#"${x%%[! ]*}"}; x=${x%"${x##*[! ]}"}; printf '%s' "$x"; }
      name=$(trim "$c1"); g=$(trim "$c3"); i=$(trim "$c4"); v=$(trim "$c5")
      is_hex "$v" 64 || continue
      is_uint "$g" && is_uint "$i" || continue
      printf '%s\t%s\t%s\t%s\n' "$name" "$g" "$i" "$v"
    done < "$1"
    ;;

  *) usage ;;
esac
