#!/usr/bin/env bash
# tests/l1/test_session_start.sh -- the SessionStart gate matrix
# (CONTRACT 1.2, TEST_STRATEGY 6.1). The hook prints the kernel only when the
# session's cwd or its parent holds BOOT.md or MISSION_BOARD.md, prints nothing
# otherwise, and exits 0 on every path.
set -u
here=$(cd "$(dirname "$0")" && pwd); repo=${here%/tests/l1}
ok=0; no=0; name=""
t() { name=$1; }
pass() { ok=$((ok+1)); }
fail() { no=$((no+1)); echo "  FAIL: $name: $1"; }
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ovm.XXXXXX"); trap 'rm -rf "$tmp"' EXIT

root="$tmp/plug root with space"
mkdir -p "$root/hooks"
cp -R "$repo/hooks/." "$root/hooks/"
cp -R "$repo/reference" "$root/"

# JSON string for a directory: the native path (cygpath -w on Windows, with
# its backslashes JSON-escaped), else the POSIX path.
jpath() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1" | LC_ALL=C awk '{ gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); printf "%s", $0 }'
  else
    printf '%s' "$1" | LC_ALL=C awk '{ gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); printf "%s", $0 }'
  fi
}
run() { # dir -> hook output, then rc=N
  printf '{"session_id":"s1","transcript_path":"","cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$(jpath "$1")" |
    CLAUDE_PLUGIN_ROOT="$root" bash "$root/hooks/session-start.sh"
  echo "rc=$?"
}
has_kernel() { case $1 in "# AI OVERMIND KERNEL v5"*"END OF KERNEL v5"*"rc=0") return 0 ;; esac; return 1; }

t "4 non-team cwd prints nothing"
mkdir -p "$tmp/plain/sub"
out=$(run "$tmp/plain/sub"); [ "$out" = "rc=0" ] && pass || fail "got: $(printf '%s' "$out" | head -c 80)"

t "1 BOOT.md in cwd gets the kernel"
mkdir -p "$tmp/team/A - Dev"; : > "$tmp/team/A - Dev/BOOT.md"
out=$(run "$tmp/team/A - Dev"); has_kernel "$out" && pass || fail "no kernel"

t "1b the reference dir is substituted, once, with forward slashes"
n=$(printf '%s\n' "$out" | LC_ALL=C grep -cF "$root/reference")
case $out in *'{{REFERENCE_DIR}}'*) fail "token left in output" ;; *) [ "$n" = 1 ] && pass || fail "reference dir appears $n times" ;; esac

t "2 BOOT.md in the parent gets the kernel"
mkdir -p "$tmp/team/A - Dev/drafts"
out=$(run "$tmp/team/A - Dev/drafts"); has_kernel "$out" && pass || fail "no kernel"

t "2b two levels below a seat gets nothing (GAP-50, accepted)"
mkdir -p "$tmp/team/A - Dev/drafts/x"
out=$(run "$tmp/team/A - Dev/drafts/x"); [ "$out" = "rc=0" ] && pass || fail "printed something"

t "3 MISSION_BOARD.md in cwd (the team root) gets the kernel"
mkdir -p "$tmp/root2"; : > "$tmp/root2/MISSION_BOARD.md"
out=$(run "$tmp/root2"); has_kernel "$out" && pass || fail "no kernel"

t "3b MISSION_BOARD.md in the parent gets the kernel"
mkdir -p "$tmp/root2/Seat"
out=$(run "$tmp/root2/Seat"); has_kernel "$out" && pass || fail "no kernel"

t "5 cwd with a space and an apostrophe"
mkdir -p "$tmp/team/Sam's Seat - QA"; : > "$tmp/team/Sam's Seat - QA/BOOT.md"
out=$(run "$tmp/team/Sam's Seat - QA"); has_kernel "$out" && pass || fail "no kernel"

t "6 empty stdin prints nothing and exits 0"
out=$( (cd "$tmp/team/A - Dev" && printf '' | CLAUDE_PLUGIN_ROOT="$root" bash "$root/hooks/session-start.sh"; echo "rc=$?") )
[ "$out" = "rc=0" ] && pass || fail "got: $(printf '%s' "$out" | head -c 80)"

t "6b malformed JSON prints nothing and exits 0"
out=$( (cd "$tmp/team/A - Dev" && printf 'not json {"cwd":' | CLAUDE_PLUGIN_ROOT="$root" bash "$root/hooks/session-start.sh"; echo "rc=$?") )
[ "$out" = "rc=0" ] && pass || fail "got: $(printf '%s' "$out" | head -c 80)"

t "6c empty cwd falls back to the process directory"
out=$( (cd "$tmp/team/A - Dev" && printf '{"cwd":""}' | CLAUDE_PLUGIN_ROOT="$root" bash "$root/hooks/session-start.sh"; echo "rc=$?") )
has_kernel "$out" && pass || fail "no kernel"

t "6d a cwd that is not a directory falls back to the process directory"
out=$( (cd "$tmp/plain" && printf '{"cwd":"/no/such/dir/at/all"}' | CLAUDE_PLUGIN_ROOT="$root" bash "$root/hooks/session-start.sh"; echo "rc=$?") )
[ "$out" = "rc=0" ] && pass || fail "printed something"

t "7 JSON-escaped backslashes and slashes in cwd"
if command -v cygpath >/dev/null 2>&1; then
  j=$(jpath "$tmp/team/A - Dev")
else
  j=$(printf '%s' "$tmp/team/A - Dev" | LC_ALL=C awk '{ gsub(/\//, "\\/"); printf "%s", $0 }')
fi
case $j in *'\'*) : ;; *) fail "fixture path has no escapes: $j" ;; esac
out=$(printf '{"cwd":"%s"}' "$j" | CLAUDE_PLUGIN_ROOT="$root" bash "$root/hooks/session-start.sh"; echo "rc=$?")
has_kernel "$out" && pass || fail "no kernel for $j"

t "8 plugin root with a space, given with backslashes on Windows"
if command -v cygpath >/dev/null 2>&1; then wr=$(cygpath -w "$root"); else wr=$root; fi
out=$(printf '{"cwd":"%s"}' "$(jpath "$tmp/team/A - Dev")" | CLAUDE_PLUGIN_ROOT="$wr" bash "$root/hooks/session-start.sh"; echo "rc=$?")
case $out in *'\reference'*) fail "backslash left in the reference dir" ;; *'/reference'*"rc=0") pass ;; *) fail "no reference dir" ;; esac

t "9 kernel missing prints nothing and exits 0"
mv "$root/hooks/kernel.md" "$root/hooks/kernel.md.off"
out=$(run "$tmp/team/A - Dev"); [ "$out" = "rc=0" ] && pass || fail "got: $(printf '%s' "$out" | head -c 80)"
mv "$root/hooks/kernel.md.off" "$root/hooks/kernel.md"

t "output carries no CR, even from a CRLF kernel"
awk '{ printf "%s\r\n", $0 }' "$repo/hooks/kernel.md" > "$root/hooks/kernel.md"
out=$(run "$tmp/team/A - Dev")
case $out in *$'\r'*) fail "CR in output" ;; *) has_kernel "$out" && pass || fail "no kernel" ;; esac

echo "$([ $no -eq 0 ] && echo PASS || echo FAIL) ${0##*/} ($((ok+no)) cases)"; [ $no -eq 0 ]
