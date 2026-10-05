#!/usr/bin/env bash
# tests/rel/test_twin_guard_rel.sh -- the OPS-030 release fixes to
# hooks/twin-guard.sh (AMENDMENTS A-33 S-1, S-2, S-3; A-31).
#   S-1  a folder that holds a BOOT.md is walked even when it holds a .git;
#        only the .git itself is pruned (live: a seat folder that is a repo).
#   S-2  ovm-twin-guard is a protected name; Post alerts when the marker says
#        noroot but a team root resolves.
#   S-3  the 512 KiB cap is checked before the twin test: agent_type placed
#        after a huge tool_input can't slip a write through.
#   A-31 the snapshot is cached by path, mtime, ctime, size and inode: a quiet
#        call hashes nothing, and an edit that restores the mtime is still seen.
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

# mkteam ROOT: a team root, a seat with a stub board, a seat folder that is its
# own git repo (BOOT.md and .git side by side) and a plain repo clone.
mkteam() {
  local r=$1
  mkdir -p "$r/Nash - Developer" "$r/Mercer - Media/.git" "$r/clone/.git"
  printf '# MISSION BOARD\n\n## Active\n' > "$r/MISSION_BOARD.md"
  printf '# MISSION BOARD \342\200\224 RETIRED BRIDGE COPY\n' > "$r/Nash - Developer/MISSION_BOARD.md"
  for s in "Nash - Developer" "Mercer - Media"; do
    printf '# BOOT\n' > "$r/$s/BOOT.md"; printf '## 2026-10-05 - note - READ\n' > "$r/$s/INBOX.md"
  done
  printf 'ref: refs/heads/master\n' > "$r/Mercer - Media/.git/HEAD"
  printf 'inside .git\n' > "$r/Mercer - Media/.git/HANDOFF.md"
  printf '# a cloned repo\n' > "$r/clone/CLAUDE.md"
}
team="$tmp/team"; mkteam "$team"; seat="$team/Nash - Developer"

# ---------------------------------------------------------------- S-1
t "S-1: a write to a seat folder that is its own git repo is alerted"
# The writes run from a script file, so the command names no protected file
# and the pre-check allows it; only the outcome detector can catch them.
echo 'printf x >> "../Mercer - Media/INBOX.md"' > "$tmp/w1.sh"
out=$(twinrun "" "$seat" "sh '$tmp/w1.sh'" s1a)
case $out in *'protected file changed during twin command: Mercer - Media/INBOX.md'*) pass ;; *) fail "got: ${out:0:200}" ;; esac

t "S-1: that seat's .git itself is still pruned, and a clone without BOOT.md still is"
echo 'printf x >> "../Mercer - Media/.git/HANDOFF.md"; printf x >> ../clone/CLAUDE.md' > "$tmp/w2.sh"
out=$(twinrun "" "$seat" "sh '$tmp/w2.sh'" s1b)
[ -z "$out" ] && grep -q x "$team/clone/CLAUDE.md" && pass || fail "got: ${out:0:200}"

# ---------------------------------------------------------------- S-2
t "S-2: commands and writes naming ovm-twin-guard are denied for a twin"
bad=0
for c in 'rm -rf /tmp/ovm-twin-guard' 'echo noroot > /tmp/ovm-twin-guard/a.t.ok' 'cp /dev/null "$TMPDIR/ovm-twin-guard/a.t.snap"' 'touch OVM-TWIN-GUARD/x'; do
  r=$(gk "" PreToolUse "$seat" "$c" s2a)
  case $r in *'"permissionDecision":"deny"'*) ;; *) bad=1; echo "    allowed: $c" ;; esac
done
r=$(printf '{"session_id":"s1","cwd":"%s","hook_event_name":"PreToolUse","agent_id":"a","agent_type":"%s","tool_name":"Write","tool_input":{"file_path":"%s","content":"noroot"},"tool_use_id":"w1"}' \
  "$(js "$seat")" "$TWIN" "$(js "$tmp/snaps/ovm-twin-guard/agentr.s2b.ok")" | TMPDIR="$tmp/snaps" "$B" "$GUARD")
case $r in *'"permissionDecision":"deny"'*) ;; *) bad=1; echo "    Write allowed" ;; esac
[ $bad -eq 0 ] && pass || fail "see above"

t "S-2: a noroot marker with a team root resolvable at Post is alerted"
lone="$tmp/lone"; mkdir -p "$lone/a/b"
pre=$(gk "" PreToolUse "$lone/a/b" true s2c)
printf '# MISSION BOARD\n' > "$lone/MISSION_BOARD.md"
out=$(gk "" PostToolUse "$lone/a/b" true s2c)
case $out in *'TWIN-GUARD ALERT: no team root at PreToolUse but one resolves now'*) [ -z "$pre" ] && pass || fail "pre spoke: $pre" ;; *) fail "got: ${out:0:200}" ;; esac
rm -f "$lone/MISSION_BOARD.md"

t "S-2: a marker rewritten to noroot during the call does not hide a change"
gk "" PreToolUse "$seat" true s2d > /dev/null
printf 'noroot\n' > "$tmp/snaps/ovm-twin-guard/agentr.s2d.ok"
printf 'changed\n' >> "$seat/INBOX.md"
out=$(gk "" PostToolUse "$seat" true s2d)
case $out in *'TWIN-GUARD ALERT'*) pass ;; *) fail "silent: ${out:0:200}" ;; esac

t "S-2: with no team root at Pre or Post, Post stays quiet"
out=$(gk "" PreToolUse "$lone/a/b" true s2e; gk "" PostToolUse "$lone/a/b" true s2e)
[ -z "$out" ] && pass || fail "got: ${out:0:200}"

# ---------------------------------------------------------------- S-3
pad=$(printf '%*s' 600000 '' | tr ' ' 'x')
t "S-3: agent_type after a huge tool_input is denied (Write, Edit and Bash)"
bad=0
for tool in Write Edit Bash; do
  case $tool in
    Write) ti="{\"file_path\":\"$(js "$seat/INBOX.md")\",\"content\":\"$pad\"}" ;;
    Edit) ti="{\"file_path\":\"$(js "$seat/INBOX.md")\",\"old_string\":\"a\",\"new_string\":\"$pad\"}" ;;
    Bash) ti="{\"command\":\"echo x >> INBOX.md # $pad\"}" ;;
  esac
  r=$(printf '{"session_id":"s1","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":%s,"tool_use_id":"c1","agent_id":"a","agent_type":"%s"}' \
    "$(js "$seat")" "$tool" "$ti" "$TWIN" | TMPDIR="$tmp/snaps" "$B" "$GUARD")
  case $r in *'"permissionDecision":"deny"'*) ;; *) bad=1; echo "    $tool allowed" ;; esac
done
[ $bad -eq 0 ] && pass || fail "see above"

t "S-3 (round 2): over the cap, a twin is denied and a main session allowed, each within 2 s"
bad=0
for who in twin main; do
  for tool in Write Bash; do
    case $tool in
      Write) ti="{\"file_path\":\"$(js "$seat/notes.md")\",\"content\":\"$pad\"}" ;;
      Bash) ti="{\"command\":\"echo x # $pad\"}" ;;
    esac
    tail_f=""; [ $who = twin ] && tail_f=",\"agent_id\":\"a\",\"agent_type\":\"$TWIN\""
    printf '{"session_id":"s1","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":%s,"tool_use_id":"c2"%s}' \
      "$(js "$seat")" "$tool" "$ti" "$tail_f" > "$tmp/big.json"
    s0=$SECONDS
    r=$(TMPDIR="$tmp/snaps" "$B" "$GUARD" < "$tmp/big.json")
    el=$((SECONDS - s0))
    case $who:$r in
      twin:*'"permissionDecision":"deny"'*|main:) ;;
      *) bad=1; echo "    $who $tool: ${r:0:120}" ;;
    esac
    [ $el -le 2 ] || { bad=1; echo "    $who $tool took $el s"; }
  done
done
[ $bad -eq 0 ] && pass || fail "see above"

t "S-3 (round 2): a main session over the cap whose content quotes a twin's agent_type is allowed"
printf '{"session_id":"s1","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"x.md","content":"%s \\"agent_type\\":\\"%s\\""},"tool_use_id":"c3"}' \
  "$(js "$seat")" "$pad" "$TWIN" > "$tmp/big2.json"
r=$(TMPDIR="$tmp/snaps" "$B" "$GUARD" < "$tmp/big2.json")
[ -z "$r" ] && pass || fail "got: ${r:0:120}"

t "S-3: a PostToolUse over the cap is alerted for a twin and quiet for a main session"
gk "" PreToolUse "$seat" true s3p > /dev/null
o1=$(printf '{"session_id":"s1","cwd":"%s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"true"},"tool_response":{"stdout":"%s"},"tool_use_id":"s3p","agent_id":"agentr","agent_type":"%s"}' \
  "$(js "$seat")" "$pad" "$TWIN" | TMPDIR="$tmp/snaps" "$B" "$GUARD")
o2=$(printf '{"session_id":"s1","cwd":"%s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"true"},"tool_response":{"stdout":"%s \\"agent_type\\":\\"%s\\""},"tool_use_id":"m1"}' \
  "$(js "$seat")" "$pad" "$TWIN" | TMPDIR="$tmp/snaps" "$B" "$GUARD")
case $o1 in *'TWIN-GUARD ALERT: hook input over the 512 KiB cap'*) [ -z "$o2" ] && pass || fail "main session: ${o2:0:160}" ;; *) fail "twin: ${o1:0:160}" ;; esac

# ---------------------------------------------------------------- quoted dot
t "round 2: a quoted ' . ' (perl concatenation) is not a source; a real . still is"
bad=0
for c in "perl -e 'print q(a) . q(b)'" "echo 'a; . b'" "awk 'BEGIN { x = \"a\" \" . \" }'"; do
  r=$(gk "" PreToolUse "$seat" "$c" qd1)
  case $r in *'"permissionDecision":"deny"'*) bad=1; echo "    denied: $c" ;; esac
done
for c in ". ./x.sh" "true; . ./x.sh" "x=1 . ./y" "(. ./z)"; do
  r=$(gk "" PreToolUse "$seat" "$c" qd2)
  case $r in *'"permissionDecision":"deny"'*) ;; *) bad=1; echo "    allowed: $c" ;; esac
done
[ $bad -eq 0 ] && pass || fail "see above"

# ---------------------------------------------------------------- A-31
# Shims count every run of the hash programs the guard may pick.
shim="$tmp/shim"; mkdir -p "$shim"; HASHLOG="$tmp/hashlog"; : > "$HASHLOG"
for h in sha256sum shasum cksum; do
  real=$(command -v "$h" 2>/dev/null) || continue
  case $real in /*) ;; *) continue ;; esac
  printf '#!/bin/sh\necho %s >> "%s"\nexec "%s" "$@"\n' "$h" "$HASHLOG" "$real" > "$shim/$h"; chmod +x "$shim/$h"
done
ck() { PATH="$shim:$PATH" gk "" "$@"; }
hashes() { local n; n=$(wc -l < "$HASHLOG"); printf '%s' "${n// /}"; }
team2="$tmp/team2"; mkteam "$team2"; seat2="$team2/Nash - Developer"
rm -rf "$tmp/snaps"; mkdir -p "$tmp/snaps"
sleep 3   # every fixture file is now over a second older than the next snapshot

t "A-31: the first call hashes; a quiet second call hashes nothing at Pre or Post"
ck PreToolUse "$seat2" true c1 > /dev/null; ck PostToolUse "$seat2" true c1 > /dev/null
first=$(hashes); : > "$HASHLOG"
t0=$SECONDS
ck PreToolUse "$seat2" true c2 > /dev/null; out=$(ck PostToolUse "$seat2" true c2)
second=$(hashes)
[ "$first" -ge 1 ] && [ "$second" -eq 0 ] && [ -z "$out" ] && pass || fail "first=$first second=$second out=${out:0:120}"

t "A-31: an edit that keeps size and restores mtime during the call is alerted"
f="$seat2/INBOX.md"; cp -p "$f" "$tmp/ref"
ck PreToolUse "$seat2" true c3 > /dev/null
printf '## 2026-10-05 - note - UNRE\n' > "$f"; touch -r "$tmp/ref" "$f"
out=$(ck PostToolUse "$seat2" true c3)
case $out in *'protected file changed during twin command: Nash - Developer/INBOX.md'*) pass ;; *) fail "got: ${out:0:200}" ;; esac

t "A-31: an mtime-preserving edit between calls is re-hashed, so undoing it in a call is alerted"
sleep 2
cp -p "$f" "$tmp/ref2"; printf '## 2026-10-05 - note - XXXX\n' > "$f"; touch -r "$tmp/ref2" "$f"
sleep 2
ck PreToolUse "$seat2" true c4 > /dev/null
cp "$tmp/ref2" "$f"; touch -r "$tmp/ref2" "$f"
out=$(ck PostToolUse "$seat2" true c4)
case $out in *'protected file changed during twin command: Nash - Developer/INBOX.md'*) pass ;; *) fail "got: ${out:0:200}" ;; esac

t "A-31: a file whose ctime is within a second of the cache's time is re-hashed, not trusted"
sleep 2
ck PreToolUse "$seat2" true c5 > /dev/null; ck PostToolUse "$seat2" true c5 > /dev/null
printf '## 2026-10-05 - note - YYYY\n' > "$f"; touch -r "$tmp/ref2" "$f"
: > "$HASHLOG"
ck PreToolUse "$seat2" true c7 > /dev/null; ck PostToolUse "$seat2" true c7 > /dev/null
[ "$(hashes)" -ge 1 ] && pass || fail "a just-changed file was taken from the cache"

t "informational: warm Pre + Post cost on the fixture team"
ck PreToolUse "$seat2" true c6 > /dev/null; ck PostToolUse "$seat2" true c6 > /dev/null
s=$SECONDS
for i in 1 2 3; do gk "" PreToolUse "$seat2" true "w$i" > /dev/null; gk "" PostToolUse "$seat2" true "w$i" > /dev/null; done
echo "  three warm Pre+Post pairs: $((SECONDS - s)) s"
pass

finish
