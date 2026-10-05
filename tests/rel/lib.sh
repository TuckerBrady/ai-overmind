#!/usr/bin/env bash
# tests/rel/lib.sh: helpers for the OPS-030 release-lane tests. Sourced by
# tests/rel/test_*.sh only.
#
# Provides: t/pass/fail/finish counters, a temp dir removed on exit, the
# script paths, a JSON string escaper and a twin-guard driver.
set -u
here=$(cd "$(dirname "$0")" && pwd)
repo=${here%/tests/rel}
B=${BASH:-bash}
GUARD=${GUARD_UNDER_TEST:-$repo/hooks/twin-guard.sh}
TARS=${TARS_UNDER_TEST:-$repo/hooks/tars.sh}
CLAIM=${CLAIM_UNDER_TEST:-$repo/skills/go/claim.sh}
PROOF=${PROOF_UNDER_TEST:-$repo/skills/collective/proof.sh}
TWIN='ai-overmind:splinter-twin'
ok=0 no=0 name=""
t() { name=$1; }
pass() { ok=$(( ok + 1 )); }
fail() { no=$(( no + 1 )); echo "  FAIL: $name: $1"; }
finish() {
  if [ "$no" -eq 0 ]; then echo "PASS ${0##*/} ($ok cases)"; else echo "FAIL ${0##*/} ($no of $(( ok + no )))"; fi
  [ "$no" -eq 0 ]
}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ovmrel.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

# js STRING: STRING as a JSON string body.
js() { local s=$1; s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\t'/\\t}; s=${s//$'\n'/\\n}; s=${s//$'\r'/\\r}; printf '%s' "$s"; }

# gk GUARD EVENT CWD COMMAND TUID: one twin Bash hook event, records under
# $tmp/snaps (GUARD defaults to the guard under test when empty).
gk() {
  printf '{"session_id":"s1","cwd":"%s","hook_event_name":"%s","agent_id":"agentr","agent_type":"%s","tool_name":"Bash","tool_input":{"command":"%s"},"tool_use_id":"%s"}' \
    "$(js "$3")" "$2" "$TWIN" "$(js "$4")" "$5" | TMPDIR="$tmp/snaps" "$B" "${1:-$GUARD}" 2>/dev/null
}
# twinrun GUARD CWD COMMAND TUID: Pre, run COMMAND in CWD (TMPDIR set), Post.
# Prints DENIED, or Post's output.
twinrun() {
  local out
  out=$(gk "$1" PreToolUse "$2" "$3" "$4")
  case $out in *'"permissionDecision":"deny"'*) echo DENIED; return ;; esac
  (cd "$2" && TMPDIR="$tmp/snaps" bash -c "$3" > /dev/null 2>&1)
  gk "$1" PostToolUse "$2" "$3" "$4"
}
mkdir -p "$tmp/snaps"
