#!/usr/bin/env bash
# skills/collective/proof.sh: Proof A, nonce first (CONTRACT 5.3; formats in
# reference/collective.md "Formats").
#
#   proof.sh issue <cid> <peer> <k>       verifier: store a fresh nonce and index k
#                                         for <peer>, then print them for the post
#   proof.sh answer <cid> <k> <nonce>     holder: print X_k and sha256(X_k || nonce)
#   proof.sh verify <cid> <peer> <X_k> <proof>
#                                         verifier: pass only against the stored
#                                         nonce, which is deleted on any attempt
#
# The nonce is written to private state BEFORE anything is printed, so it
# exists before the challenge can be sent. At most one round is in flight per
# Collective (FW-26). Exit: 0 pass, 1 fail or refused, 2 usage, 3 missing
# state, 4 missing tool.
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
umask 077

usage() { die 2 "usage: proof.sh issue <cid> <peer> <k> | answer <cid> <k> <nonce> | verify <cid> <peer> <X_k> <proof>"; }

cmd=${1:-}
[ $# -ge 1 ] && shift

case $cmd in
  issue)
    [ $# -eq 3 ] || usage
    cid=$1 peer=$2 k=$3; d=$(state_dir "$cid") || exit 2
    peer_ok "$peer" || die 2 "bad peer label"
    is_uint "$k" && [ "$k" -ge 1 ] || die 2 "index must be a positive integer"
    accepted_get "$d" "$peer" || die 3 "no accepted chain for $peer; accept an anchor first"
    [ "$k" -lt "$ACC_INDEX" ] || die 1 "REFUSED: index $k is not below the last accepted index $ACC_INDEX"
    mkdir -p "$d/pending" || die 3 "cannot create $d/pending"
    for p in "$d"/pending/*; do
      [ -e "$p" ] && die 1 "REFUSED: a round is already in flight in this Collective (one at a time)"
    done
    rm -f "$d/renew-ok.$(peer_key "$peer")"   # a legacy renewal rides on this round only
    n=$(rand_hex 16)
    printf 'peer: %s\nnonce: %s\nindex: %s\n' "$peer" "$n" "$k" | write_atomic "$d/pending/$(peer_key "$peer")" ||
      die 3 "cannot store the nonce"
    event "$d" "issued Proof A to $peer at index $k"
    printf 'nonce: %s\nindex: %s\n' "$n" "$k"
    ;;

  answer)
    [ $# -eq 3 ] || usage
    cid=$1 k=$2 n=$3; d=$(state_dir "$cid") || exit 2; m="$d/membership"
    is_uint "$k" && [ "$k" -ge 1 ] && [ "$k" -le 99 ] || die 2 "index must be 1-99"
    is_hex "$n" 32 || die 2 "nonce must be 32 lowercase hex characters"
    [ -f "$m" ] || die 3 "no membership for $cid"
    g=$(kv_get "$m" generation) || die 3 "membership has no generation"
    low=$(kv_get "$m" lowest-revealed) || die 3 "membership has no lowest-revealed"
    der=$(kv_get "$m" derivation) || der=v5
    [ "$k" -lt "$low" ] || die 1 "REFUSED: index $k is not below the lowest index already revealed ($low); never reveal a step twice"
    case $der in
      v5) s=$(seed_get seed) && is_hex "$s" 64 || die 3 "no Genesis Seed: run genesis.sh mint first"
          x0=$(chain_base "$cid" "$g") ;;
      legacy-v2)
        old=$(kv_get "$m" legacy-cid) || die 3 "legacy membership has no legacy-cid"
        nonce=$(seed_get nonce) || die 3 "no legacy nonce: line in the genesis-seed"
        x0=$(sha_str "AI-OVERMIND-GENESIS-CHAIN-V2|$old|$g|$nonce") ;;
      *) die 3 "unknown derivation $der" ;;
    esac
    x=$(chain_step "$x0" "$k")
    # Spend the step before it can be shown to anyone.
    { printf 'derivation: %s\n' "$der"
      [ "$der" = legacy-v2 ] && printf 'legacy-cid: %s\n' "$old"
      printf 'generation: %s\nlowest-revealed: %s\n' "$g" "$k"; } | write_atomic "$m" || die 3 "cannot update membership"
    printf 'reveal: %s\nindex: %s\nproof: %s\n' "$x" "$k" "$(sha_str "$x$n")"
    ;;

  verify)
    [ $# -eq 4 ] || usage
    cid=$1 peer=$2 x=$3 h=$4; d=$(state_dir "$cid") || exit 2
    peer_ok "$peer" || die 2 "bad peer label"
    key=$(peer_key "$peer"); pf="$d/pending/$key"
    [ -f "$pf" ] || die 1 "FAIL: no stored nonce for $peer (issue one first; each nonce works once)"
    n=$(kv_get "$pf" nonce); k=$(kv_get "$pf" index); sp=$(kv_get "$pf" peer)
    rm -f "$pf"   # single use: any attempt spends it
    [ "$sp" = "$peer" ] || die 1 "FAIL: stored nonce belongs to another peer"
    is_hex "$n" 32 && is_uint "$k" || die 1 "FAIL: stored nonce is malformed"
    is_hex "$x" 64 || die 1 "FAIL: reveal is not 64 lowercase hex"
    is_hex "$h" 64 || die 1 "FAIL: proof is not 64 lowercase hex"
    [ "$(sha_str "$x$n")" = "$h" ] || { event "$d" "Proof A FAIL for $peer: proof does not bind the stored nonce"; die 1 "FAIL: proof does not match sha256(reveal || nonce)"; }
    accepted_get "$d" "$peer" || die 3 "FAIL: no accepted chain for $peer"
    [ "$k" -lt "$ACC_INDEX" ] || die 1 "FAIL: index $k is not below the last accepted index"
    [ "$(chain_step "$x" $(( ACC_INDEX - k )))" = "$ACC_VALUE" ] ||
      { event "$d" "Proof A FAIL for $peer: reveal does not hash to the accepted value"; die 1 "FAIL: reveal does not hash forward to the last accepted value"; }
    accepted_put "$d" "$peer" "$ACC_GEN" "$k" "$x" "$ACC_NEXT" "$ACC_STATUS"
    : > "$d/renew-ok.$key"
    event "$d" "Proof A PASS for $peer at index $k"
    echo "PASS"
    ;;

  *) usage ;;
esac
