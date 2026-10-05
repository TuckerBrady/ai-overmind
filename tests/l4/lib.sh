#!/usr/bin/env bash
# tests/l4/lib.sh: helpers for the L4 (Collective) tests. Sourced by
# tests/l4/test_*.sh only; nothing outside this lane uses it.
#
# Provides: t/pass/fail/finish counters, a temp dir removed on exit, the
# script paths, a sha256 of its own (independent of skills/collective/lib.sh,
# so the published vectors are checked by a second implementation), and the
# section 7.10 test vectors read out of reference/collective.md.
set -u
here=$(cd "$(dirname "$0")" && pwd)
repo=${here%/tests/l4}
B=${BASH:-bash}
GEN="$repo/skills/assimilate/genesis.sh"
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

# h TEXT: sha256 hex of TEXT, no newline.
h() {
  local o
  if command -v sha256sum >/dev/null 2>&1; then o=$(printf '%s' "$1" | sha256sum)
  elif command -v shasum >/dev/null 2>&1; then o=$(printf '%s' "$1" | shasum -a 256)
  else o=$(printf '%s' "$1" | openssl dgst -sha256); o=${o##*= }; fi
  printf '%s' "${o%% *}"
}
# hn X N: hash X forward N times.
hn() { local x=$1 i=0; while [ "$i" -lt "$2" ]; do x=$(h "$x"); i=$(( i + 1 )); done; printf '%s' "$x"; }

# newhome NAME: a fresh HOME for one Overmind.
newhome() { mkdir -p "$tmp/$1/.claude/overmind"; printf '%s' "$tmp/$1"; }

# vec KEY: a value from the "vectors" block of reference/collective.md.
vec() {
  tr -d '\r' < "$repo/reference/collective.md" |
    sed -n '/^```vectors$/,/^```$/p' | sed -n "s/^$1 = //p" | head -1
}

# rec1 / rec2: the published anchor records, exact bytes.
rec1() { printf 'gen: 1\nanchor: %s\nnext: %s\n' "$(vec anchor_1)" "$(vec next_1)"; }
rec2() { printf 'gen: 2\nanchor: %s\nnext: %s\n' "$(vec anchor_2)" "$(vec next_2)"; }
