#!/usr/bin/env bash
# tests/rel/test_twin_guard_rel.sh -- the OPS-030 release fixes to
# hooks/twin-guard.sh (AMENDMENTS A-33 S-1, S-2, S-3; A-37; A-38).
#   S-1  a folder that holds a BOOT.md is walked even when it holds a .git;
#        only the .git itself is pruned (live: a seat folder that is a repo).
#   S-2  ovm-twin-guard is a protected name; Post alerts when the marker says
#        noroot but a team root resolves.
#   S-3  the 512 KiB cap is checked before the twin test: agent_type placed
#        after a huge tool_input can't slip a write through.
#   A-37 no snapshot cache: every protected file is hashed on every Pre and
#        Post, so restoring mtime and ctime can't hide an edit; the root skips
#        RETIRED BRIDGE COPY stubs; the JSON reader is linear in every awk.
#   A-38 bash < 4.1 saves its input to a file (head can't read past the cap);
#        Post re-hashes Pre's files before it walks, and an unfinished check is
#        reported; every live root of both walks is watched; the command word
#        is read without quotes or backslashes.
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

# ---------------------------------------------------------------- A-38
# tmo10 CMD...: run CMD with a 10 s limit, like the hook timeout (no timeout(1)
# on stock macOS). Prints CMD's output; returns 124 when it was cut off.
tmo10() {
  local o="$tmp/tmo.out" p w rc
  { "$@" > "$o" 2>/dev/null & } 2>/dev/null; p=$!
  ( sleep 10; kill -9 "$p" 2>/dev/null ) & w=$!
  wait "$p" 2>/dev/null; rc=$?
  kill "$w" 2>/dev/null; wait "$w" 2>/dev/null
  cat "$o"; [ $rc -gt 128 ] && return 124; return $rc
}
mkab() { # mkab ROOT: a plain team, seats Seat and Other with BOOT.md and INBOX.md
  mkdir -p "$1/Seat" "$1/Other"; printf '# MB\n' > "$1/MISSION_BOARD.md"
  for s in Seat Other; do printf 'b\n' > "$1/$s/BOOT.md"; printf '## x - READ\n' > "$1/$s/INBOX.md"; done
}

t "A-38 D-1: agent_type at CAP+100 is found (this bash's read path), and the bash < 4.1 path with a block-reading head"
d1="$tmp/d1"; mkab "$d1"
pre='{"session_id":"s","cwd":"'"$d1/Seat"'","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"'"$d1/Seat/INBOX.md"'","content":"'
post='"},"tool_use_id":"t","agent_id":"a","agent_type":"'"$TWIN"'"}'
need=$(( 524288 + 100 - ${#pre} - ${#post} + 40 ))
printf '%s%s%s' "$pre" "$(printf '%*s' $need '' | tr ' ' 'x')" "$post" > "$tmp/d1.json"
sed 's/^if (( BASH_VERSINFO\[0\] > 4 .*then$/if false; then/' "$GUARD" > "$tmp/g32.sh"
mkdir -p "$tmp/blkbin"
dd_ok=0; printf 'abc' | dd bs=2 count=1 iflag=fullblock >/dev/null 2>&1 && dd_ok=1
if [ $dd_ok -eq 1 ]; then
  printf '#!/usr/bin/env bash\nn=$2; blk=16384; cnt=$(( (n + blk - 1) / blk ))\ndd bs=$blk count=$cnt iflag=fullblock 2>/dev/null | %s -c "$n"\n' "$(command -v head)" > "$tmp/blkbin/head"
else
  printf '#!/usr/bin/env bash\nn=$2; blk=16384; cnt=$(( (n + blk - 1) / blk ))\ndd bs=$blk count=$cnt 2>/dev/null | %s -c "$n"\n' "$(command -v head)" > "$tmp/blkbin/head"
fi
chmod +x "$tmp/blkbin/head"
echo "  bash $BASH_VERSION; agent_type at byte $(grep -bo '"agent_type"' "$tmp/d1.json" | cut -d: -f1)"
r1=$(TMPDIR="$tmp/snaps" "$B" "$GUARD" < "$tmp/d1.json")
r2=$(cat "$tmp/d1.json" | TMPDIR="$tmp/snaps" "$B" "$GUARD")
r3=$(cat "$tmp/d1.json" | PATH="$tmp/blkbin:$PATH" TMPDIR="$tmp/snaps" "$B" "$tmp/g32.sh")
bad=""
case $r1 in *'"permissionDecision":"deny"'*) ;; *) bad="$bad file" ;; esac
case $r2 in *'"permissionDecision":"deny"'*) ;; *) bad="$bad pipe" ;; esac
grep -q '^if false; then' "$tmp/g32.sh" || bad="$bad patch"
case $r3 in *'"permissionDecision":"deny"'*) ;; *) bad="$bad bash<4.1-blockhead" ;; esac
[ -z "$bad" ] && pass || fail "allowed:$bad"

t "A-38 P1: Post re-hashes Pre's files first, so a change is logged even when the walk is cut off"
p1="$tmp/p1"; mkab "$p1"; rm -rf "$tmp/snaps"; mkdir -p "$tmp/snaps"
gk "" PreToolUse "$p1/Seat" true p1a > /dev/null
printf 'twin\n' >> "$p1/Other/INBOX.md"
# A find that hangs stands for a walk that outruns the hook's 10 s.
mkdir -p "$tmp/slowbin"; printf '#!/bin/sh\nsleep 30\n' > "$tmp/slowbin/find"; chmod +x "$tmp/slowbin/find"
s0=$SECONDS
PATH="$tmp/slowbin:$PATH" tmo10 gk "" PostToolUse "$p1/Seat" true p1a > /dev/null; rc=$?
echo "  Post with a hanging walk: rc $rc after $((SECONDS - s0)) s"
grep -q 'protected file changed during twin command: Other/INBOX.md' "$p1/_twin-guard.log" 2>/dev/null && pass || fail "nothing logged"

t "A-38 P1: the next Pre reports that the previous check did not finish"
sleep 16
out=$(gk "" PreToolUse "$p1/Seat" true p1b)
case $out in *'previous check did not finish'*) grep -q 'previous check did not finish' "$p1/_twin-guard.log" && pass || fail "not logged" ;; *) fail "got: ${out:0:200}" ;; esac
out=$(gk "" PreToolUse "$p1/Seat" true p1c)
case $out in *'previous check did not finish'*) fail "reported twice" ;; *) pass ;; esac

t "A-38 P1: 20k created files plus one edited INBOX are alerted within the hook's 10 s"
py=""; for c in python3 python; do command -v "$c" >/dev/null 2>&1 && "$c" -c 'import os' >/dev/null 2>&1 && { py=$c; break; }; done
if [ -z "$py" ]; then echo "  SKIP: no python to create 20k files quickly"; pass
else
  p2="$tmp/p2"; mkab "$p2"
  cat > "$p2/Seat/w.py" <<'PY'
import os
open(os.path.join('..', 'Other', 'IN' + 'BOX.md'), 'a').write('twin\n')
for i in range(20000):
    d = os.path.join('..', 'work', 'd%03d' % (i // 100), 'e%05d' % i)
    os.makedirs(d, exist_ok=True)
    open(os.path.join(d, 'IN' + 'BOX.md'), 'w').write('x')
PY
  gk "" PreToolUse "$p2/Seat" "$py w.py" p2a > /dev/null
  (cd "$p2/Seat" && "$py" w.py)
  s0=$SECONDS; o=$(tmo10 gk "" PostToolUse "$p2/Seat" "$py w.py" p2a); rc=$?
  echo "  Post over 20k new files: rc $rc after $((SECONDS - s0)) s"
  grep -q 'protected file changed during twin command: Other/INBOX.md' "$p2/_twin-guard.log" 2>/dev/null && pass || fail "nothing logged (rc $rc)"
fi

t "A-38 P2: when the cwd walk and the project-dir walk find different teams, both are watched"
dA="$tmp/p3/deep/er/teamA"; dB="$tmp/p3/tB"; mkab "$dA"; mkab "$dB"
echo 'printf t >> "../Other/IN""BOX.md"' > "$tmp/w4.sh"
out=$(CLAUDE_PROJECT_DIR="$dB/Seat" twinrun "" "$dA/Seat" "sh '$tmp/w4.sh'" p3a)
echo 'printf t >> "'"$dB"'/Other/IN""BOX.md"' > "$tmp/w5.sh"
out2=$(CLAUDE_PROJECT_DIR="$dB/Seat" twinrun "" "$dA/Seat" "sh '$tmp/w5.sh'" p3b)
case $out in *'changed during twin command: Other/INBOX.md'*)
  case $out2 in *'changed during twin command: Other/INBOX.md'*) pass ;; *) fail "project-dir team unwatched: ${out2:0:160}" ;; esac ;;
  *) fail "cwd team unwatched: ${out:0:160}" ;; esac

t "A-38 P3: the command word is read without quotes or backslashes; a coprocess prefix is skipped"
# The corpus is a fixture file, so the bash 3.2 lint never reads its words.
bad=0
while IFS= read -r c || [ -n "$c" ]; do
  [ -n "$c" ] || continue
  r=$(gk "" PreToolUse "$seat" "$c" q38)
  case $r in *'"permissionDecision":"deny"'*) ;; *) bad=1; echo "    allowed: $c" ;; esac
done < "$here/fixtures/cmdword_corpus.txt"
[ $bad -eq 0 ] && pass || fail "see above"

t "A-38 P3: an over-cap input with no agent_type key passes, even when it names splinter-twin"
printf '{"session_id":"s1","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"x.md","content":"splinter-twin %s"},"tool_use_id":"c4"}' "$(js "$seat")" "$pad" > "$tmp/nokey.json"
r=$(TMPDIR="$tmp/snaps" "$B" "$GUARD" < "$tmp/nokey.json")
[ -z "$r" ] && pass || fail "got: ${r:0:120}"

t "A-38 P3: an alert is logged under the Pre snapshot's root too, when Post runs from elsewhere"
p4="$tmp/p4"; mkab "$p4"; lone4="$tmp/lone4"; mkdir -p "$lone4"
rm -f "$tmp/snaps/ovm-twin-guard/"*.busy   # the cut-off Posts above would be reported first
gk "" PreToolUse "$p4/Seat" true p4a > /dev/null
printf 'tampered\n' > "$tmp/snaps/ovm-twin-guard/agentr.p4a.ok"
out=$(gk "" PostToolUse "$lone4" true p4a)
case $out in *'snapshot missing'*) grep -q 'snapshot missing' "$p4/_twin-guard.log" 2>/dev/null && pass || fail "not logged under the Pre root" ;; *) fail "got: ${out:0:160}" ;; esac

t "informational: Pre + Post cost on the fixture team (every file hashed)"
s=$SECONDS
for i in 1 2 3; do gk "" PreToolUse "$seat2" true "w$i" > /dev/null; gk "" PostToolUse "$seat2" true "w$i" > /dev/null; done
echo "  three Pre+Post pairs: $((SECONDS - s)) s"
pass

finish
