#!/usr/bin/env bash
# tests/l1/test_diag.sh -- the two /diagnostic Level 3 scripts (CONTRACT 1.10).
#   too-large.sh: a truncated SessionStart record fails; a tool call or tool
#                 result that only quotes the phrase does not; a clean
#                 transcript passes.
#   fwhash.sh:    the 7.5 hash of a fixture tree equals a hard-coded value and an
#                 independent computation.
set -u
here=$(cd "$(dirname "$0")" && pwd); repo=${here%/tests/l1}
ok=0; no=0; name=""
t() { name=$1; }
pass() { ok=$((ok+1)); }
fail() { no=$((no+1)); echo "  FAIL: $name: $1"; }
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ovm.XXXXXX"); trap 'rm -rf "$tmp"' EXIT
tl="$repo/skills/diagnostic/too-large.sh"
fh="$repo/skills/diagnostic/fwhash.sh"

rc() { bash "$tl" "$1" >/dev/null 2>&1; echo $?; }

t "real-shape SessionStart record (redacted from a 4.11 seat transcript) exits 1"
[ "$(rc "$here/fixtures/sessionstart-too-large.jsonl")" = 1 ] && pass || fail "expected 1"

t "the record still fails among other lines"
{ printf '{"type":"user","message":{"role":"user","content":"hi"}}\n'
  cat "$here/fixtures/sessionstart-too-large.jsonl"
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"ok"}]}}\n'; } > "$tmp/mixed.jsonl"
[ "$(rc "$tmp/mixed.jsonl")" = 1 ] && pass || fail "expected 1"

t "tool_use and tool_result lines that quote the phrase exit 0"
{ printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"grep \"Output too large\" x | grep SessionStart"}}]}}'
  printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"SessionStart:startup hook: Output too large (123.7KB)"}]}}'; } > "$tmp/tools.jsonl"
[ "$(rc "$tmp/tools.jsonl")" = 0 ] && pass || fail "expected 0"

t "a clean transcript exits 0"
printf '%s\n' '{"type":"attachment","attachment":{"type":"hook_success","hookName":"SessionStart:startup","hookEvent":"SessionStart","content":"# AI OVERMIND KERNEL v5"}}' > "$tmp/clean.jsonl"
[ "$(rc "$tmp/clean.jsonl")" = 0 ] && pass || fail "expected 0"

t "a missing transcript exits 0"
[ "$(rc "$tmp/none.jsonl")" = 0 ] && pass || fail "expected 0"

# Fixture tree, built at runtime: CRLF, a missing final newline, and two
# reference files whose names sort differently from their creation order.
mkdir -p "$tmp/plug/hooks" "$tmp/plug/reference"
printf '# K\r\nEND OF KERNEL v5' > "$tmp/plug/hooks/kernel.md"
printf '# B\nbody b\n' > "$tmp/plug/reference/b-topic.md"
printf '# A\r\nbody a' > "$tmp/plug/reference/a.md"
want=51697fc9b59ee9a95441d81e07e59c88b7164dfa5dfbf700dabace1be57d9e37

t "fwhash.sh on the fixture tree equals the hard-coded hash"
got=$(bash "$fh" "$tmp/plug")
[ "$got" = "$want" ] && pass || fail "got $got"

t "an independent 7.5 computation agrees"
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi; }
ind=$(printf '=== hooks/kernel.md\n# K\nEND OF KERNEL v5\n=== reference/a.md\n# A\nbody a\n=== reference/b-topic.md\n# B\nbody b\n' | sha | cut -c1-64)
[ "$ind" = "$want" ] && pass || fail "independent $ind"

t "a changed reference file changes the hash"
printf '# A\nbody a, edited\n' > "$tmp/plug/reference/a.md"
got2=$(bash "$fh" "$tmp/plug")
[ -n "$got2" ] && [ "$got2" != "$want" ] && pass || fail "hash did not change"

t "fwhash.sh on a tree with no kernel exits non-zero and prints no hash"
out=$(bash "$fh" "$tmp/none" 2>/dev/null); r=$?
[ $r -ne 0 ] && [ -z "$out" ] && pass || fail "rc=$r out=$out"

t "fwhash.sh on this repo matches the Go concatenation's shape (64 hex)"
case $(bash "$fh" "$repo") in [0-9a-f]*) [ "$(bash "$fh" "$repo" | wc -c | tr -d ' ')" = 65 ] && pass || fail "not 64 hex" ;; *) fail "no hash" ;; esac

t "the diagnostic skill invokes both scripts"
LC_ALL=C grep -q 'skills/diagnostic/too-large.sh' "$repo/skills/diagnostic/SKILL.md" &&
  LC_ALL=C grep -q 'skills/diagnostic/fwhash.sh' "$repo/skills/diagnostic/SKILL.md" && pass || fail "missing invocation"

echo "$([ $no -eq 0 ] && echo PASS || echo FAIL) ${0##*/} ($((ok+no)) cases)"; [ $no -eq 0 ]
