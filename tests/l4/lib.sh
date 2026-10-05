#!/usr/bin/env bash
# tests/l4/lib.sh: helpers for the L4 (Collective) tests. Sourced by
# tests/l4/test_*.sh only; nothing outside this lane uses it.
#
# Provides: t/pass/fail/finish counters, a temp dir removed on exit, the
# script paths, fresh HOMEs, and runtime-generated ed25519 keys. No key is
# ever committed: every key here is made in $tmp and removed on exit.
set -u
here=$(cd "$(dirname "$0")" && pwd)
repo=${here%/tests/l4}
B=${BASH:-bash}
ID="$repo/skills/assimilate/identity.sh"
PROOF="$repo/skills/collective/proof.sh"
STATE="$repo/skills/collective/state.sh"
CATCHUP="$repo/skills/collective/catchup.sh"
POSTNAME="$repo/skills/collective/post-name.sh"
DNP="$repo/skills/collective/dnp-scan.sh"
ok=0 no=0 name=""
t() { name=$1; }
pass() { ok=$(( ok + 1 )); }
fail() { no=$(( no + 1 )); echo "  FAIL: $name: $1"; }
finish() {
  if [ "$no" -eq 0 ]; then echo "PASS ${0##*/} ($ok cases)"; else echo "FAIL ${0##*/} ($no of $(( ok + no )))"; fi
  [ "$no" -eq 0 ]
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ovm.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

CID=00112233445566778899aabbccddeeff
CID2=ffeeddccbbaa99887766554433221100

# newhome NAME: a fresh HOME for one Overmind, with its own minted key.
newhome() {
  local h="$tmp/home-$1"
  mkdir -p "$h"
  HOME=$h "$B" "$ID" mint >/dev/null || { echo "  cannot mint a key for $1" >&2; return 1; }
  printf '%s' "$h"
}
# pubof HOME: path of that Overmind's public key.
pubof() { printf '%s/.claude/overmind/collective/id_ed25519.pub' "$1"; }
keyof() { printf '%s/.claude/overmind/collective/id_ed25519' "$1"; }
# fp FILE: SHA256 fingerprint of a public key, computed here independently.
fp() { local o; o=$(ssh-keygen -lf "$1"); o=${o#* }; printf '%s' "${o%% *}"; }
# sdir HOME [CID]: that Overmind's private state dir for a Collective.
sdir() { printf '%s/.claude/overmind/collective/%s' "$1" "${2:-$CID}"; }
