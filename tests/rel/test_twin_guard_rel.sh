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


t "A-37 P3: a twin Write just under the cap is parsed and denied within 5 s (linear-time JSON reader; macOS awk too)"
under=$(printf '%*s' 520000 '' | tr ' ' 'y')
printf '{"session_id":"s1","cwd":"%s","hook_event_name":"PreToolUse","agent_id":"a","agent_type":"%s","tool_name":"Write","tool_input":{"file_path":"%s","content":"%s\\n\\"%s"},"tool_use_id":"u1"}' \
  "$(js "$seat")" "$TWIN" "$(js "$seat/INBOX.md")" "$under" "$under" | head -c 524000 > "$tmp/under.json"
printf '"},"tool_use_id":"u1"}' >> "$tmp/under.json"
s0=$SECONDS
r=$(TMPDIR="$tmp/snaps" "$B" "$GUARD" < "$tmp/under.json")
el=$((SECONDS - s0))
echo "  twin Write of $(wc -c < "$tmp/under.json" | tr -d ' ') bytes: ${el} s"
case $r in *'Write on INBOX.md'*) [ $el -le 5 ] && pass || fail "took $el s" ;; *) fail "not denied by path: ${r:0:160}" ;; esac

t "A-37 P3: a main session's malformed JSON with no agent_type exits 0 silently"
out=$(printf '{"session_id":"s1","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"INBOX.md","content":"about splinter-twin' | "$B" "$GUARD"); rc=$?
[ -z "$out" ] && [ $rc -eq 0 ] && pass || fail "rc=$rc out=${out:0:120}"

t "round 3: if the JSON reader itself fails, a twin's write is denied and a main session's passes"
ab="$tmp/awkbin"; mkdir -p "$ab"; printf '#!/bin/sh\nexit 2\n' > "$ab/awk"; chmod +x "$ab/awk"
r1=$(printf '{"agent_id":"a","agent_type":"%s","tool_name":"Write","tool_input":{"file_path":"/x/notes.md","content":"x"}}' "$TWIN" | PATH="$ab:$PATH" "$B" "$GUARD")
r2=$(printf '{"tool_name":"Write","tool_input":{"file_path":"/x/notes.md","content":"splinter-twin"}}' | PATH="$ab:$PATH" "$B" "$GUARD")
case $r1 in *'"permissionDecision":"deny"'*) [ -z "$r2" ] && pass || fail "main: ${r2:0:100}" ;; *) fail "twin allowed: ${r1:0:100}" ;; esac

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

t "A-37 P3: \$'..', escaped quotes, if/while/until/elif and backticks can't hide source, eval or ."
bad=0
while IFS= read -r c; do
  [ -n "$c" ] || continue
  r=$(gk "" PreToolUse "$seat" "$c" qd3)
  case $r in *'"permissionDecision":"deny"'*) ;; *) bad=1; echo "    allowed: $c" ;; esac
done <<'CORPUS'
echo $'\''; . ./x.sh
echo \"; . ./x.sh; echo \"
echo "a'b"; . ./x.sh
echo 'unbalanced; . ./x.sh
if . ./x.sh; then :; fi
while . ./x.sh; do break; done
until . ./x.sh; do break; done
if false; then :; elif . ./x.sh; then :; fi
echo `. ./x.sh`
echo "$(. ./x.sh)"
if source ./x.sh; then :; fi
if eval "echo hi"; then :; fi
echo `source ./x.sh`
echo `eval true`
CORPUS
[ $bad -eq 0 ] && pass || fail "see above"

# ---------------------------------------------------------------- A-37 B1
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
sleep 3   # every fixture file is now well over a second old

t "A-37 B1: no cache: a quiet call still hashes at Pre and at Post"
ck PreToolUse "$seat2" true c1 > /dev/null; ck PostToolUse "$seat2" true c1 > /dev/null
: > "$HASHLOG"; ck PreToolUse "$seat2" true c2 > /dev/null; pre=$(hashes)
: > "$HASHLOG"; out=$(ck PostToolUse "$seat2" true c2); post=$(hashes)
[ "$pre" -ge 1 ] && [ "$post" -ge 1 ] && [ -z "$out" ] && pass || fail "pre=$pre post=$post out=${out:0:120}"

t "an edit that keeps size and restores mtime during the call is alerted"
f="$seat2/INBOX.md"; cp -p "$f" "$tmp/ref"
ck PreToolUse "$seat2" true c3 > /dev/null
printf '## 2026-10-05 - note - UNRE\n' > "$f"; touch -r "$tmp/ref" "$f"
out=$(ck PostToolUse "$seat2" true c3)
case $out in *'protected file changed during twin command: Nash - Developer/INBOX.md'*) pass ;; *) fail "got: ${out:0:200}" ;; esac

t "A-37 B1: an edit that restores both mtime and ctime (NTFS) is alerted"
py=""
for p in python3 python py; do command -v "$p" >/dev/null 2>&1 && "$p" -c 'import ctypes; ctypes.WinDLL' >/dev/null 2>&1 && { py=$p; break; }; done
if [ -z "$py" ]; then
  echo "  SKIP: no Windows python here (SetFileInformationByHandle, which sets the NTFS ChangeTime, exists only on Windows)"
  pass
else
  sleep 2
  ck PreToolUse "$seat2" true c9 > /dev/null; ck PostToolUse "$seat2" true c9 > /dev/null
  pyf=$(cygpath -w "$here/fixtures/ctime_restore.py"); sw=$(cygpath -w "$seat2")
  c="$py '$pyf' '$sw'"
  st0=$(find "$f" -printf '%T@ %C@ %s'); h0=$(cksum < "$f")
  out=$(twinrun "" "$seat2" "$c" c10)
  st1=$(find "$f" -printf '%T@ %C@ %s'); h1=$(cksum < "$f")
  echo "  stat before/after: [$st0] [$st1]; content changed: $([ "$h0" != "$h1" ] && echo yes || echo no)"
  if [ "$h0" = "$h1" ]; then fail "the attack did not change the file"
  else case $out in *'protected file changed during twin command: Nash - Developer/INBOX.md'*) pass ;; *) fail "silent: ${out:0:200}" ;; esac
  fi
fi

# ---------------------------------------------------------------- A-37 B2
t "A-37 B2: real Morph layout (cwd seat/drafts/MORPH/X, project dir the seat, stubs in every seat): a write to another seat's INBOX is alerted"
t3="$tmp/team3"; mkteam "$t3"; tb="$t3/T-Bot - The Overmind"; mkdir -p "$tb/drafts/MORPH/OPS-030"
printf '# BOOT\n' > "$tb/BOOT.md"
for s in "$t3/Nash - Developer" "$t3/Mercer - Media" "$tb"; do printf '# MISSION BOARD \342\200\224 RETIRED BRIDGE COPY\n' > "$s/MISSION_BOARD.md"; done
echo 'printf "twin was here\n" >> "../../../../Nash - Developer/IN""BOX.md"' > "$tmp/w3.sh"
out=$(CLAUDE_PROJECT_DIR="$tb" twinrun "" "$tb/drafts/MORPH/OPS-030" "sh '$tmp/w3.sh'" b2a)
case $out in *'protected file changed during twin command: Nash - Developer/INBOX.md'*) pass ;; *) fail "got: ${out:0:200}" ;; esac

t "A-37 B2: a seat holding only a stub, with no live board in reach, has no team root"
lone2="$tmp/lone2/Seat/drafts/X"; mkdir -p "$lone2"; printf '# MISSION BOARD \342\200\224 RETIRED BRIDGE COPY\n' > "$tmp/lone2/Seat/MISSION_BOARD.md"
gk "" PreToolUse "$lone2" true b2b > /dev/null
[ "$(cat "$tmp/snaps/ovm-twin-guard/agentr.b2b.ok" 2>/dev/null)" = noroot ] && pass || fail "a stub became a root"

t "informational: Pre + Post cost on the fixture team (every file hashed)"
s=$SECONDS
for i in 1 2 3; do gk "" PreToolUse "$seat2" true "w$i" > /dev/null; gk "" PostToolUse "$seat2" true "w$i" > /dev/null; done
echo "  three Pre+Post pairs: $((SECONDS - s)) s"
pass

finish
