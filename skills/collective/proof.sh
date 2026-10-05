#!/usr/bin/env bash
# skills/collective/proof.sh: Proof A by signature (CONTRACT A-23; COL-1, COL-3).
#
#   proof.sh issue <cid> <my-label> <peer-label>
#       verifier: store a fresh 128-bit nonce for a PINNED peer, then print
#       the challenge. Nothing is printed unless the nonce was stored first.
#   proof.sh answer <cid> <verifier-label> <my-label> <nonce>
#       holder: sign the Proof A message with this Overmind's key and print
#       the armored signature.
#   proof.sh verify <cid> <peer-label> <signature-file>
#       verifier: check the signature against the peer's PIN. The pending
#       nonce is claimed with mv first (N1); only a signature that verifies
#       spends it, so a stranger cannot burn a round.
#
# The signed message is exactly
#   ai-overmind-proof-a|<cid>|<verifier-label>|<peer-label>|<nonce>
# with both labels in normalized form (lowercase letters and digits), signed
# under the namespace ai-overmind-collective. Naming the cid and the verifier
# means a signature replayed to another verifier or Collective fails. At most
# one round is in flight per Collective (FW-26).
# Exit: 0 pass, 1 fail or refused, 2 usage, 3 missing state, 4 missing tool.
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
umask 077

usage() { die 2 "usage: proof.sh issue <cid> <my-label> <peer-label> | answer <cid> <verifier-label> <my-label> <nonce> | verify <cid> <peer-label> <signature-file>"; }
message() { printf 'ai-overmind-proof-a|%s|%s|%s|%s' "$1" "$2" "$3" "$4"; }

cmd=${1:-}
[ $# -ge 1 ] && shift

case $cmd in
  issue)
    [ $# -eq 3 ] || usage
    cid=$1; d=$(state_dir "$cid") || exit 2
    label_ok "$2" && label_ok "$3" || die 2 "labels must be plain ASCII letters, digits, space and . _ ( ) , -"
    me=$(label_norm "$2"); peer=$(label_norm "$3")
    [ -f "$d/pins/$peer.pub" ] || die 3 "REFUSED: $3 has no pinned key; pin it after an out-of-band fingerprint check"
    mkdir -p "$d/pending" || die 3 "cannot create $d/pending"
    for p in "$d"/pending/*; do
      [ -e "$p" ] && die 1 "REFUSED: a round is already in flight in this Collective (one at a time)"
    done
    n=$(rand_hex 16)
    printf 'verifier: %s\npeer: %s\nnonce: %s\n' "$me" "$peer" "$n" | write_atomic "$d/pending/$peer" ||
      die 3 "cannot store the nonce"
    event "$d" "issued Proof A to $peer"
    printf 'proof-a: cid %s verifier %s peer %s nonce %s\n' "$cid" "$me" "$peer" "$n"
    ;;

  answer)
    [ $# -eq 4 ] || usage
    cid=$1 n=$4
    state_dir "$cid" >/dev/null || exit 2
    label_ok "$2" && label_ok "$3" || die 2 "bad label"
    is_hex "$n" 32 || die 2 "nonce must be 32 lowercase hex characters"
    k=$(key_file); [ -f "$k" ] || die 3 "no key: run identity.sh mint"
    t=$(mktemp -d "${TMPDIR:-/tmp}/ovmpa.XXXXXX") || die 3 "no temp dir"
    message "$cid" "$(label_norm "$2")" "$(label_norm "$3")" "$n" > "$t/m"
    if ssh-keygen -Y sign -f "$k" -n "$NAMESPACE" "$t/m" </dev/null >/dev/null 2>&1; then
      cat "$t/m.sig"; rm -rf "$t"
    else
      rm -rf "$t"; die 4 "ssh-keygen could not sign"
    fi
    ;;

  verify)
    [ $# -eq 3 ] || usage
    cid=$1 sig=$3; d=$(state_dir "$cid") || exit 2
    label_ok "$2" || die 2 "bad label"
    peer=$(label_norm "$2"); pin="$d/pins/$peer.pub"
    [ -f "$pin" ] || die 1 "FAIL: $2 has no pinned key"
    [ -f "$sig" ] || die 2 "no such signature file: $sig"
    pf="$d/pending/$peer"; claim="$d/pending/.claim.$peer.$$"
    mv "$pf" "$claim" 2>/dev/null || die 1 "FAIL: no stored nonce for $2 (issue one first; each nonce works once)"
    me=$(kv_get "$claim" verifier); n=$(kv_get "$claim" nonce); sp=$(kv_get "$claim" peer)
    restore() { mv "$claim" "$pf" 2>/dev/null; }
    if [ "$sp" != "$peer" ] || ! is_hex "$n" 32; then restore; die 1 "FAIL: stored nonce is malformed"; fi
    t=$(mktemp -d "${TMPDIR:-/tmp}/ovmpv.XXXXXX") || { restore; die 3 "no temp dir"; }
    message "$cid" "$me" "$peer" "$n" > "$t/m"
    printf '%s namespaces="%s" %s\n' "$peer" "$NAMESPACE" "$(key_body "$pin")" > "$t/as"
    if ssh-keygen -Y verify -f "$t/as" -I "$peer" -n "$NAMESPACE" -s "$sig" < "$t/m" >/dev/null 2>&1; then
      rm -rf "$t"; rm -f "$claim"
      event "$d" "Proof A PASS for $peer"
      echo "PASS"
    else
      rm -rf "$t"; restore
      event "$d" "Proof A FAIL for $peer (nonce kept: only the pinned key spends it)"
      die 1 "FAIL: the signature does not verify against $2's pinned key for this nonce, Collective and verifier"
    fi
    ;;

  *) usage ;;
esac
