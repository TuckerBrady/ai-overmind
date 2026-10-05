#!/usr/bin/env bash
# L2b (amendment A-13): TARS hardening.
#   MUST 1  a claimed line is printed right after its claim (kill-after-claim)
#   MUST 2  untrusted reads are bounded (1 MB INBOX, 1 MB claim file, 1 MB
#           hook input each finish within 2 s; the excess is ignored)
#   MUST 3  the board scan has no fork per row (a 400-row board within 3.0 s)
#   SHOULD  new inbox headers, not the net count; "." and ".." repo segments;
#           a builtin watchdog without timeout; the collective lock; the
#           physical team root in claim keys; a symlinked _claims refused
# Timed runs are stopped after 15 s, so a slow script fails fast.
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

# ms FILE: the time keyword's %R output (seconds.millis) as milliseconds.
ms() {
  local v i f
  v=$(cat "$1"); v=${v//[!0-9.]/}
  i=${v%%.*}; f=${v#*.}; [ "$f" = "$v" ] && f=0
  f=${f}000; f=${f:0:3}
  printf '%s' $(( 10#${i:-0} * 1000 + 10#$f ))
}
# timed OUT SID CWD [STDIN-FILE]: one turn, stopped after 15 s. Sets T (ms).
timed() {
  local o=$1 sid=$2 cwd=$3 in=${4:-} p s
  TIMEFORMAT=%R
  {
    time {
      if [ -n "$in" ]; then
        PATH=${HOOKPATH:-$SYSPATH} TARS_HOME="$TH" "$B" "$TARS" < "$in" > "$o" 2>/dev/null &
      else
        hook "$sid" "$cwd" > "$o" 2>/dev/null &
      fi
      p=$! s=0
      while kill -0 "$p" 2>/dev/null; do
        if [ "$s" -ge 150 ]; then kill -9 "$p" 2>/dev/null; break; fi
        s=$(( s + 1 )); sleep 0.1
      done
      wait "$p" 2>/dev/null
    }
  } 2> "$tmp/time"
  T=$(ms "$tmp/time")
}

root="$tmp/team"; mkteam "$root"
om="$root/T-Bot - The Overmind"; dev="$root/Nash - Developer"
export TARS_NOW=5000

# ---------------------------------------------------------------- MUST 1
# The kill shim is mkdir: the call that makes the mission-complete claim
# succeeds and arms it; the next mkdir (the watch cue's claim, later in the
# same turn) kills the hook with SIGKILL before doing anything.
kd="$tmp/killshim"; mkdir -p "$kd"
realmkdir=$(PATH=$SYSPATH command -v mkdir)
cat > "$kd/mkdir" <<EOF
#!/bin/sh
if [ -f "\$KILLFLAG" ]; then kill -9 \$PPID; exit 1; fi
case "\$*" in
  */claims/mc.*) "$realmkdir" "\$@"; rc=\$?; [ \$rc = 0 ] && : > "\$KILLFLAG"; exit \$rc ;;
esac
exec "$realmkdir" "\$@"
EOF
chmod +x "$kd/mkdir"
export KILLFLAG="$tmp/killflag"
printf '# B\n\n## Active\n\n| ID | Mission | Status | Priority |\n|---|---|---|---|\n| AXM-9 | x | ACTIVE | STANDARD |\n' > "$root/MISSION_BOARD.md"
hook k1 "$om" >/dev/null; backdate k1
printf 'MISSION: AXM-5\nRESULT: PASS\n' > "$dev/mission-complete-AXM-5.md"
HOOKPATH="$kd:$SYSPATH" TARS_NOW=5600 hook k1 "$om" > "$tmp/kout" 2>/dev/null
kout=$(cat "$tmp/kout")
set -- "$TH"/claims/mc.*
held=0; [ -d "$1" ] && held=1
t "kill-after-claim: the line is printed or the claim is released"
if [ ! -f "$KILLFLAG" ] || [ "$(count 'mission watch due' "$kout")" != 0 ]; then
  fail "the kill did not land after the claim (output: '$kout')"
elif [ "$(count 'TARS: Nash - Developer wrote mission-complete for AXM-5.' "$kout")" = 1 ] || [ "$held" = 0 ]; then pass
else fail "claim held ($1) and nothing printed: '$kout'"; fi
rm -f "$KILLFLAG" "$dev/mission-complete-AXM-5.md"

# ---------------------------------------------------------------- MUST 3
# 400 rows shaped like the real board: eight columns, slashes, commas and
# status words in titles, a long Blocker cell. 300 rows are live.
{
  printf '# B\n\n## Active\n\n| ID | Mission | Owner | Assignee | Status | Priority | Blocker | Last Touched |\n|---|---|---|---|---|---|---|---|\n'
  i=0
  while [ $i -lt 400 ]; do
    i=$(( i + 1 ))
    case $(( i % 4 )) in 0) s=ACTIVE ;; 1) s=QUEUED ;; 2) s='REVIEW / BLOCKED' ;; 3) s=COMPLETE ;; esac
    printf '| AXM-%s | Mission %s, with a / slash; ACTIVE QUEUED words in its title | T-Bot | Nash | %s | STANDARD | **2026-09-26 14:46: a blocker note that runs on, as the real ones do, naming PR #66 and a file path or two** | 2026-09-26 14:46 |\n' "$i" "$i" "$s"
  done
  printf '\n## Archive\n'
} > "$root/MISSION_BOARD.md"
hook b400 "$om" >/dev/null
touch "$root/MISSION_BOARD.md"; old "$TH/sessions/b400/boardscan"
TARS_NOW=5400 timed "$tmp/bout" b400 "$om"
bout=$(cat "$tmp/bout")
t "a 400-row board scans in at most 3.0 s and counts its 300 live rows (took ${T} ms)"
r=no; [ "$T" -le 3000 ] && [ "$bout" = "TARS (cue): mission watch due: 300 in flight, highest priority STANDARD. Run the watch rules and report only what you find." ] && r=yes
expect "took $T ms, got: $bout" test "$r" = yes
printf '# B\n\n## Active\n\n| ID | Mission | Status | Priority |\n|---|---|---|---|\n' > "$root/MISSION_BOARD.md"

# ---------------------------------------------------------------- MUST 2
# A 1 MB INBOX: entries of about 2 KB each. Only the first 512 KiB counts.
ib="$om/INBOX.md"
: > "$ib"
hook ib1 "$om" >/dev/null; backdate ib1
body=""; i=0
while [ $i -lt 20 ]; do body+="body line $i of an entry, long enough to look like the real thing in a team inbox"$'\n'; i=$(( i + 1 )); done
{ i=0; while [ $i -lt 640 ]; do printf '## 2026-10-%02d - From T-Bot - UNREAD - entry %s\n%s' $(( i % 28 + 1 )) "$i" "$body"; i=$(( i + 1 )); done; } > "$ib"
size=$(wc -c < "$ib")
want=$(head -c 524288 "$ib" | grep -c '^## ')
timed "$tmp/iout" ib1 "$om"
iout=$(cat "$tmp/iout")
t "a 1 MB INBOX ($size bytes) finishes within 2 s, read 512 KiB at most: $want entries, not 640 (took ${T} ms)"
r=no; [ "$T" -le 2000 ] && [ "$size" -ge 1048576 ] && [ "$iout" = "TARS: $want unread inbox entries (was 0)." ] && r=yes
expect "took $T ms, got: $iout" test "$r" = yes
: > "$ib"; old "$ib"

# A 1 MB single-line claim file from another session of the same mission, one
# on this session's own claim name, and one fresh foreign claim that must
# still report.
mkdir -p "$root/_claims"
printf '100 T-Bot\n' > "$root/_claims/OPS-1.cl1"
hook cl1 "$om" >/dev/null
a=""; i=0; while [ $i -lt 1024 ]; do a+=A; i=$(( i + 1 )); done
{ i=0; while [ $i -lt 1024 ]; do printf '%s' "$a"; i=$(( i + 1 )); done; } > "$root/_claims/OPS-1.big"
cp "$root/_claims/OPS-1.big" "$root/_claims/OPS-2.cl1"
printf '5000 T-Bot\n' > "$root/_claims/OPS-1.fresh"
TARS_NOW=5060 timed "$tmp/cout" cl1 "$om"
cout=$(cat "$tmp/cout")
t "1 MB claim files finish within 2 s; the fresh claim reports; the 1 MB own-name file is untouched (took ${T} ms)"
r=no; [ "$T" -le 2000 ] && [ "$cout" = "TARS: another session also holds OPS-1 (last active 1 min ago). /consolidate folds it in." ] && [ "$(wc -c < "$root/_claims/OPS-2.cl1")" -eq 1048576 ] && r=yes
expect "took $T ms, got: $cout" test "$r" = yes
rm -rf "$root/_claims"

# 1 MB of hook input: the fields come first, as Claude Code writes them, then
# a 1 MB prompt. Read 512 KiB at most.
c=$(jpath "$dev")
{ printf '{"session_id":"in1","transcript_path":"","cwd":"%s","prompt":"' "$c"
  i=0; while [ $i -lt 1024 ]; do printf '%s' "$a"; i=$(( i + 1 )); done
  printf '"}'; } > "$tmp/bigin.json"
timed "$tmp/inout" in1 "$dev" "$tmp/bigin.json"
t "1 MB of hook input finishes within 2 s and still names the session (took ${T} ms)"
r=no; [ "$T" -le 2000 ] && [ -f "$TH/sessions/in1/seat" ] && r=yes
expect "took $T ms" test "$r" = yes

# ---------------------------------------------------------------- SHOULD
# New inbox headers, not the net count: one entry is marked READ while a new
# one arrives.
printf '## 2026-10-01 - From Nash - UNREAD - one\n## 2026-10-02 - From Nash - UNREAD - two\n' > "$ib"
hook nh1 "$om" >/dev/null; backdate nh1
printf '## 2026-10-01 - From Nash - READ - one\n## 2026-10-02 - From Nash - UNREAD - two\n## 2026-10-03 - From Vaughn - UNREAD - three\n' > "$ib"
o1=$(hook nh1 "$om"); backdate nh1
printf '## 2026-10-01 - From Nash - READ - one\n## 2026-10-02 - From Nash - READ - two\n## 2026-10-03 - From Vaughn - UNREAD - three\n' > "$ib"
o2=$(hook nh1 "$om")
t "a new unread entry speaks though another was marked READ; marking READ alone is quiet"
r=no; [ "$o1" = "TARS: 2 unread inbox entries (was 2)." ] && [ -z "$o2" ] && r=yes
expect "got: '$o1' / '$o2'" test "$r" = yes
: > "$ib"; old "$ib"

# Repo names with a "." or ".." segment are never queried.
root3="$tmp/team3"; mkteam "$root3"
printf '# BOOT\n\nBinder roots (GitHub):\n   - `../evil` - one\n   - `acme/..` - two\n   - `./x` - three\n   - `acme/ok` - four\n' > "$root3/T-Bot - The Overmind/BOOT.md"
mkgh "$tmp/ghbin"; export FAKEGH="$tmp/gh"; mkdir -p "$FAKEGH"
printf 'TuckerBrady\n' > "$FAKEGH/user_out"
HOOKPATH="$tmp/ghbin:$SYSPATH" TARS_COLLECTIVE_SYNC=1 hook dot1 "$root3/T-Bot - The Overmind" >/dev/null
calls=$(cat "$FAKEGH/calls" 2>/dev/null)
t "\".\" and \"..\" repo segments are never queried"
r=no; [ "$(count 'repos/acme/ok/' "$calls")" = 1 ] && [ "$(count '..' "$calls")" = 0 ] && [ "$(count 'repos/./' "$calls")" = 0 ] && r=yes
expect "calls: $calls" test "$r" = yes

# A held collective lock skips the check; a stale one is broken.
rm -f "$FAKEGH/calls"
mkdir -p "$TH/sessions/lk1/collective/lock"; printf '9000\n' > "$TH/sessions/lk1/collective/lock/at"
HOOKPATH="$tmp/ghbin:$SYSPATH" TARS_COLLECTIVE_SYNC=1 TARS_NOW=9010 hook lk1 "$root3/T-Bot - The Overmind" >/dev/null
t "a fresh collective lock skips the check"
expect "gh was called" test ! -f "$FAKEGH/calls"
printf '8000\n' > "$TH/sessions/lk1/collective/lock/at"
HOOKPATH="$tmp/ghbin:$SYSPATH" TARS_COLLECTIVE_SYNC=1 TARS_NOW=9400 hook lk1 "$root3/T-Bot - The Overmind" >/dev/null
t "a stale collective lock is broken, the check runs, and the lock is released"
if [ -f "$FAKEGH/calls" ] && [ ! -d "$TH/sessions/lk1/collective/lock" ]; then pass
else fail "gh called: $([ -f "$FAKEGH/calls" ] && echo yes || echo no); lock left: $([ -d "$TH/sessions/lk1/collective/lock" ] && echo yes || echo no)"; fi

# The builtin watchdog: no timeout or gtimeout on PATH, and a gh that hangs.
wd="$tmp/wdbin"; mkdir -p "$wd"
for tool in tail grep date mkdir find rm cksum sleep cat mv touch head; do
  real=$(PATH=$SYSPATH command -v "$tool" 2>/dev/null) || continue
  case $real in /*) ;; *) continue ;; esac
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$real" > "$wd/$tool"; chmod +x "$wd/$tool"
done
realsleep=$(PATH=$SYSPATH command -v sleep)
printf '#!/bin/sh\nexec "%s" 30\n' "$realsleep" > "$wd/gh"; chmod +x "$wd/gh"
root4="$tmp/team4"; mkteam "$root4" acme/venue
HOOKPATH="$wd" TARS_COLLECTIVE_SYNC=1 timed "$tmp/wout" wd1 "$root4/T-Bot - The Overmind"
wout=$(cat "$tmp/wout")
t "without timeout or gtimeout a hung gh is stopped and reported as timed out (took ${T} ms)"
r=no; [ "$T" -le 12000 ] && [ "$wout" = "TARS: Collective feed unavailable: timed out." ] && r=yes
expect "took $T ms, got: $wout" test "$r" = yes

# Symlinks: two spellings of one team root share their claims, and a
# symlinked _claims folder is not read. Windows needs native symlinks.
mkln() { MSYS=winsymlinks:nativestrict ln -s "$1" "$2" 2>/dev/null && [ -L "$2" ]; }
root5="$tmp/team5"; mkteam "$root5"
if mkln "$root5" "$tmp/team5link"; then
  hook sp1 "$root5/T-Bot - The Overmind" >/dev/null; backdate sp1
  hook sp2 "$tmp/team5link/T-Bot - The Overmind" >/dev/null; backdate sp2
  printf 'RESULT: PASS\n' > "$root5/Nash - Developer/mission-complete-AXM-7.md"
  o1=$(hook sp1 "$root5/T-Bot - The Overmind"); o2=$(hook sp2 "$tmp/team5link/T-Bot - The Overmind")
  t "two spellings of one team root claim one event once"
  expect "got: $o1 / $o2" test "$(count 'wrote mission-complete for AXM-7' "$o1
$o2")" = 1
else
  echo "  unreachable on this FS: symlinked team root"
fi
mkdir -p "$tmp/elsewhere"
printf '100 T-Bot\n' > "$tmp/elsewhere/OPS-3.sy1"
if mkln "$tmp/elsewhere" "$root5/_claims"; then
  hook sy1 "$root5/T-Bot - The Overmind" >/dev/null
  hook sy1 "$root5/T-Bot - The Overmind" >/dev/null
  read -r ep rest < "$tmp/elsewhere/OPS-3.sy1"
  t "a symlinked _claims folder is not read or written"
  expect "epoch rewritten to $ep" test "$ep" = 100
else
  echo "  unreachable on this FS: symlinked _claims"
fi

finish
