#!/usr/bin/env bash
# tests/rel/test_tars_rel.sh -- A-30 release items in hooks/tars.sh.
#   - the builtin watchdog (no timeout or gtimeout on PATH) sends KILL 2 s
#     after TERM, so a command that ignores TERM still stops;
#   - rootkey clears CDPATH and drops cd's output.
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

# tmo() exactly as tars.sh defines it, run with a PATH that has no timeout.
fn="$tmp/tmo.sh"
awk '/^tmo\(\) \{/ { p = 1 } p { print } p && /^\}/ { exit }' "$TARS" > "$fn"
bin="$tmp/bin"; mkdir -p "$bin"
for tool in sleep sh; do
  real=$(command -v "$tool") || continue
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$real" > "$bin/$tool"; chmod +x "$bin/$tool"
done

t "A-30: without timeout or gtimeout, a command that ignores TERM is killed about 2 s after it"
[ -s "$fn" ] || fail "tmo() not found in tars.sh"
s=$SECONDS
rc=$(PATH="$bin" "$B" -c '. "$1"; tmo sh -c '"'"'trap "" TERM; i=0; while [ $i -lt 25 ]; do sleep 1; i=$((i+1)); done'"'"'; echo $?' _ "$fn" 2>/dev/null)
el=$((SECONDS - s))
echo "  watchdog stopped a TERM-proof command after ${el} s (rc $rc)"
[ "$el" -le 15 ] && [ "$rc" = 124 ] && pass || fail "took $el s, rc '$rc'"

t "A-30: timeout and gtimeout are given -k 2 as well"
c=$(grep -c 'timeout -k 2 8 "\$@"' "$TARS")
[ "$c" -eq 2 ] && pass || fail "found $c"

t "A-30: rootkey clears CDPATH and drops cd's output"
grep -q 'CDPATH= cd -P -- "\$root" >/dev/null' "$TARS" && pass || fail "rootkey line not found"

t "A-30: a CDPATH in the environment changes no TARS output"
team="$tmp/team"; mkdir -p "$team/T-Bot - The Overmind" "$tmp/cdp/team"
printf '# MISSION BOARD\n' > "$team/MISSION_BOARD.md"; printf '# BOOT\n' > "$team/T-Bot - The Overmind/BOOT.md"
j='{"session_id":"cd1","cwd":"'"$(js "$team/T-Bot - The Overmind")"'","hook_event_name":"UserPromptSubmit","prompt":"hi"}'
out=$(printf '%s' "$j" | CDPATH="$tmp/cdp" TARS_HOME="$tmp/th" "$B" "$TARS" 2>&1)
case $out in *"$tmp"*) fail "a path leaked: $out" ;; *) pass ;; esac

finish
