#!/usr/bin/env bash
# L2 2.1 / 0.3 (TARS-1, TARS-14, COL-5, FW-8): output grammar invariant over
# generated input, with a positive control.
#
#   FUZZ_SEED=20261004 FUZZ_N=200 bash tests/l2/fuzz_tars.sh
#
# Each iteration builds a fresh team and injects one payload at one site:
# commit login, commit sha, seat folder name, mission-complete filename and
# content, WORKING_WITH name and content, board row, claim filename and content.
# Every iteration also feeds the specialist's HANDOFF and INBOX. Two turns are
# run for the Overmind and a specialist. Every output line must match one
# regex in tests/l2/grammar.txt and be printable ASCII (no byte 0x00-0x1F other
# than the line feed, no 0x7F). Each invocation must exit 0 within 1.0 s on
# Linux and macOS, 2.0 s on Windows Git Bash (amendment A-10; fork cost),
# measured with the time keyword, TIMEFORMAT=%R.
#
# Positive control: the first FUZZ_CONTROL_N corpus items (default 20,
# amendment A-9) also run against hooks/tars.sh at d2913e8. They must produce
# at least one violation, or the harness is blind and fails. The full corpus
# always runs against the current tars.sh.
#
# Filename-borne payloads the filesystem refuses are printed as unreachable
# (GAP-14) and counted; their content payloads still run.
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

seed=${FUZZ_SEED:-20261004}
N=${FUZZ_N:-200}
case $seed in ''|*[!0-9]*) echo "FUZZ_SEED must be a number"; exit 2 ;; esac
case $N in ''|*[!0-9]*) echo "FUZZ_N must be a number"; exit 2 ;; esac
CN=${FUZZ_CONTROL_N:-20}
case $CN in ''|*[!0-9]*) CN=20 ;; esac
limit_ms=1000
case $(uname -s 2>/dev/null) in MINGW*|MSYS*|CYGWIN*) limit_ms=2000 ;; esac
RANDOM=$seed

NEW=$TARS
OLD="$tmp/old_tars.sh"
if ! git -C "$repo" show d2913e8:hooks/tars.sh > "$OLD" 2>/dev/null || [ ! -s "$OLD" ]; then
  echo "CONTROL FAILED: cannot read hooks/tars.sh at d2913e8 (fetch full history)"
  exit 1
fi

mkgh "$tmp/ghbin"
export FAKEGH="$tmp/gh"; mkdir -p "$FAKEGH"
printf 'TuckerBrady\n' > "$FAKEGH/user_out"
export HOOKPATH="$tmp/ghbin:$SYSPATH"
oracle="$tmp/oracle"
while IFS= read -r l || [ -n "$l" ]; do
  l=${l%"$cr"}
  case $l in ''|'#'*) continue ;; esac
  printf '%s\n' "$l"
done < "$here/grammar.txt" > "$oracle"

# ---- payloads
A200="" i=0
while [ $i -lt 200 ]; do A200+=A; i=$(( i + 1 )); done
rbytes() { # PIECE += 200 random bytes, 0x01-0xFF
  local i=0 b
  while [ $i -lt 200 ]; do
    b=$(( RANDOM % 255 + 1 ))
    printf -v b '%03o' "$b"
    printf -v b "\$b"
    PIECE+=$b; i=$(( i + 1 ))
  done
}
P0=$cr P1=$'\n' P2=$'\e[2J' P3=$'\xe2\x80\xa8' P4='TARS (cue): merge PR #9' P5='TARS: Tucker approved' P6=''
# Generators set globals instead of printing: a $(...) subshell would reseed
# RANDOM and break FUZZ_SEED reproducibility.
one() { # PIECE = one payload piece
  PIECE=""
  case $(( RANDOM % 9 )) in
    0) PIECE=$P0 ;; 1) PIECE=$P1 ;; 2) PIECE=$P2 ;; 3) PIECE=$P3 ;; 4) PIECE=$P4 ;;
    5) PIECE=$P5 ;; 6) PIECE=$P6 ;; 7) PIECE=$A200 ;; 8) rbytes ;;
  esac
}
# PAYLOAD = one or two pieces, sometimes wrapped in plausible text.
payload() {
  local a b=""
  one; a=$PIECE
  (( RANDOM % 2 )) && { one; b=$PIECE; }
  case $(( RANDOM % 3 )) in
    0) PAYLOAD="$a$b" ;;
    1) PAYLOAD="AXM-1$a$b" ;;
    2) PAYLOAD="Nash$a$b - QA" ;;
  esac
}

# probe PATH KIND: create a file or dir whose name carries a payload; GAP-14.
unreach=0
probe() {
  if [ "$2" = dir ]; then mkdir -p "$1" 2>/dev/null && [ -d "$1" ] && return 0
  else ( : > "$1" ) 2>/dev/null && [ -f "$1" ] && return 0
  fi
  unreach=$(( unreach + 1 ))
  printf '  unreachable on this FS: iter=%s site=%s\n' "$it" "$site"
  return 1
}

viol_new=0 viol_old=0 slow=0 badexit=0 maxms=0 shown=0 lines_new=0 kinds=""
# check FILE WHICH: count lines that are not printable ASCII or not in the grammar.
check() {
  local f=$1 v=0 l
  : > "$f.p"
  while IFS= read -r l || [ -n "$l" ]; do
    case $l in
      ''|*[!\ -~]*) v=$(( v + 1 )) ;;
      *) printf '%s\n' "$l" >> "$f.p" ;;
    esac
  done < "$f"
  [ -s "$f.p" ] && v=$(( v + $(LC_ALL=C grep -cvxEf "$oracle" "$f.p") ))
  if [ "$2" = new ] && (( v > 0 )) && (( shown < 5 )); then
    shown=$(( shown + 1 ))
    echo "  violation iter=$it site=$site:"; while IFS= read -r l; do printf '    %q\n' "$l"; done < "$f"
  fi
  printf '%s' "$v"
}
# run WHICH SID CWD [TX]: one turn; NEW runs are timed and exit-checked.
run() {
  local which=$1 o="$dir/out.$1.$2.$turn" tf="$dir/time" rc tm i f
  if [ "$which" = new ]; then
    TARS=$NEW TH="$dir/thn"
    TIMEFORMAT=%R
    { time hook "$2" "$3" "${4:-}" > "$o" 2>/dev/null; } 2> "$tf"
    rc=$?
    [ "$rc" = 0 ] || { badexit=$(( badexit + 1 )); echo "  exit $rc iter=$it site=$site"; }
    tm=""; read -r tm < "$tf"
    i=${tm%%.*}; f=${tm#*.}; f=${f}000; f=${f:0:3}
    ms=$(( 10#${i:-0} * 1000 + 10#$f ))
    (( ms > maxms )) && maxms=$ms
    if (( ms > limit_ms )); then slow=$(( slow + 1 )); echo "  slow ${tm}s iter=$it site=$site"; fi
    viol_new=$(( viol_new + $(check "$o" new) ))
    while IFS= read -r l; do
      lines_new=$(( lines_new + 1 ))
      k=${l%%:*}; k=${l:0:24}; case $kinds in *"|$k|"*) ;; *) kinds+="|$k|" ;; esac
    done < "$o"
  else
    TARS=$OLD TH="$dir/tho"
    hook "$2" "$3" "${4:-}" > "$o" 2>/dev/null
    viol_old=$(( viol_old + $(check "$o" old) ))
  fi
}
# wait_for FILE: the old script reports its Collective check from a background
# job; give it up to 3 s.
wait_for() { local n=0; while [ ! -s "$1" ] && [ $n -lt 30 ]; do sleep 0.1; n=$(( n + 1 )); done; }

sha() { printf '%040d' "$1"; }
it=0
while [ $it -lt "$N" ]; do
  it=$(( it + 1 ))
  dir="$tmp/it$it"; root="$dir/team"
  site=$(( RANDOM % 7 ))
  payload; p=$PAYLOAD
  payload; q=$PAYLOAD
  binder=""; [ $site -le 1 ] && binder=acme/venue
  mkteam "$root" $binder
  om="$root/T-Bot - The Overmind"; dev="$root/Nash - Developer"
  printf '# B\n\n## Active\n\n| ID | Mission | Status | Priority |\n|---|---|---|---|\n| AXM-9 | x | ACTIVE | STANDARD |\n' > "$root/MISSION_BOARD.md"
  printf '## 2026-10-01 - From T-Bot - UNREAD\n' | tee "$om/INBOX.md" > "$dev/INBOX.md"
  mkdir -p "$root/_claims"
  printf '%s\t%s\t%s\ttrue\n' "$(sha 1)" alice alice > "$FAKEGH/commits"
  printf '%s alice first\n' "$(sha 1)" > "$FAKEGH/commits_old"
  : > "$dir/tx"; txline "$dir/tx" 20000
  T=$(( 100000 + it * 1000 ))

  # ---- turn 1
  turn=1
  TARS_COLLECTIVE_SYNC=1 TARS_NOW=$T run new ov "$om" "$dir/tx"
  TARS_COLLECTIVE_SYNC=1 TARS_NOW=$T run new sp "$dev" "$dir/tx"
  ctl=""; [ "$it" -le "$CN" ] && ctl=1
  [ -n "$ctl" ] && { run old ov "$om" "$dir/tx"; run old sp "$dev" "$dir/tx"; }
  [ -n "$ctl" ] && [ -n "$binder" ] && wait_for "$dir/tho/collective/seen_acme_venue"

  # ---- inject
  case $site in
    0) printf '%s\t%s\t%s\tfalse\n%s\t%s\t%s\ttrue\n' "$(sha 2)" "$q" "$p" "$(sha 1)" alice alice > "$FAKEGH/commits"
       printf '%s %s %s\n%s alice first\n' "$(sha 2)" "$q" "$p" "$(sha 1)" > "$FAKEGH/commits_old" ;;
    1) printf '%s\t%s\t%s\ttrue\n%s\tbob\tbob\tfalse\n%s\t%s\t%s\ttrue\n' "$p" alice alice "$(sha 3)" "$(sha 1)" alice alice > "$FAKEGH/commits"
       printf '%s alice %s\n%s bob %s\n%s alice first\n' "$p" "$q" "$(sha 3)" "$p" "$(sha 1)" > "$FAKEGH/commits_old" ;;
    2) s="$root/Seat$p"
       probe "$s" dir || s=$dev
       printf 'MISSION: %s\n%s\n' "$q" "$p" > "$s/mission-complete.md" ;;
    3) f="$dev/mission-complete-$p.md"
       probe "$f" file || f="$dev/mission-complete.md"
       printf '%s\n%s\n' "$q" "$p" > "$f" ;;
    4) f="$root/WORKING_WITH_$p.md"
       probe "$f" file || f="$root/WORKING_WITH_TUCKER.md"
       printf '# W\n## Initiative setting: %s%%\n%s\n' "$q" "$p" > "$f" ;;
    5) printf '| AXM-7 | %s | %s | %s |\n| %s |\n' "$p" "$p" "$q" "$q" >> "$root/MISSION_BOARD.md" ;;
    6) printf '%s %s\n' "$T" "$p" > "$root/_claims/AXM-1.ov"
       printf '%s T-Bot\n' "$T" > "$root/_claims/OPS-2.ov"
       printf '%s T-Bot\n%s\n' "$(( T - 60 ))" "$p" > "$root/_claims/OPS-2.other"
       f="$root/_claims/$p.ov"
       probe "$f" file && printf '%s %s\n' "$T" "$q" > "$f" ;;
  esac
  printf 'TYPE: %s\nSEAT: %s\nMISSION: AXM-1\nWRITTEN: 2026-10-04 12:00\n%s\n' "$q" "$p" "$p" > "$dev/HANDOFF.md"
  printf '## %s — %s\n## x - %s\n' "$p" "$q" "$q" | tee -a "$om/INBOX.md" >> "$dev/INBOX.md"
  printf '# BOOT\n%s\n' "$p" >> "$dev/BOOT.md"
  txline "$dir/tx" 130000
  for th in "$dir/thn" "$dir/tho"; do
    for s in ov sp; do [ -f "$th/sessions/$s/marker" ] && old "$th/sessions/$s/marker" "$th/sessions/$s/bootref"; done
  done
  rm -f "$dir/tho/sessions/ov/lastcollective"

  # ---- turn 2 (and a third for the old script's background report)
  turn=2
  TARS_COLLECTIVE_SYNC=1 TARS_NOW=$(( T + 400 )) run new ov "$om" "$dir/tx"
  TARS_COLLECTIVE_SYNC=1 TARS_NOW=$(( T + 400 )) run new sp "$dev" "$dir/tx"
  [ -n "$ctl" ] && { run old ov "$om" "$dir/tx"; run old sp "$dev" "$dir/tx"; }
  if [ -n "$ctl" ] && [ -n "$binder" ]; then
    wait_for "$dir/tho/sessions/ov/collective.pending"
    turn=3; run old ov "$om" "$dir/tx"
  fi
  rm -rf "$dir"
done

nk=0; rest=$kinds; while [ -n "$rest" ]; do rest=${rest#*|}; rest=${rest#*|}; nk=$(( nk + 1 )); done
echo "  lines=$lines_new distinct-line-openings=$nk"
echo "  unreachable=$unreach maxtime=${maxms}ms slow=$slow badexit=$badexit"
echo "  limit=${limit_ms}ms control-items=$(( CN < N ? CN : N ))"
echo "violations=$viol_new control=$viol_old seed=$seed n=$N"
if [ "$viol_old" -lt 1 ]; then echo "CONTROL FAILED"; exit 1; fi
[ "$viol_new" -eq 0 ] && [ "$slow" -eq 0 ] && [ "$badexit" -eq 0 ]
