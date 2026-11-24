#!/usr/bin/env bash
# tests/rel/test_twin_guard_parallel.sh -- the 5.1.1 fixes to
# hooks/twin-guard.sh, for several splinter twins running at once in one
# session (live, 2026-11-23: four to six twins, almost every Bash call alerted
# or denied with no team file changed).
#   LOG   the root's own _twin-guard.log is append-only to the detector: other
#         twins' hook lines never alert; truncating, rewriting or deleting it
#         still does.
#   PAR   busy markers and records are per agent and per call: interleaved
#         Pre/Post from several twins stay quiet, and one twin's cut-off check
#         never blocks another.
#   STALE a stale marker of the same twin is settled from its record: quiet
#         when nothing changed, denied and reported when a protected file did,
#         or when the record is gone.
#   COST  Python package trees are pruned from the walk.
#   VAR   a $VARIABLE target that the command gives literal values reads
#         through to them: scratch writes pass, every team-state write is
#         still denied, through $VAR, redirects, cd, links and relative paths.
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

# hk AGENT EVENT CWD COMMAND TUID [GUARD]: one twin Bash hook event.
hk() {
  printf '{"session_id":"s1","cwd":"%s","hook_event_name":"%s","agent_id":"%s","agent_type":"%s","tool_name":"Bash","tool_input":{"command":"%s"},"tool_use_id":"%s"}' \
    "$(js "$3")" "$2" "$1" "$TWIN" "$(js "$4")" "$5" | TMPDIR="$tmp/snaps" "$B" "${6:-$GUARD}" 2>/dev/null
}
# hw AGENT TOOL PATH: a twin Write or Edit PreToolUse on PATH.
hw() {
  printf '{"session_id":"s1","cwd":"%s","hook_event_name":"PreToolUse","agent_id":"%s","agent_type":"%s","tool_name":"%s","tool_input":{"file_path":"%s","content":"x","old_string":"a","new_string":"b"},"tool_use_id":"w1"}' \
    "$(js "$seat")" "$1" "$TWIN" "$2" "$(js "$3")" | TMPDIR="$tmp/snaps" "$B" "$GUARD" 2>/dev/null
}
isdeny() { case $1 in *'"permissionDecision":"deny"'*) return 0 ;; esac; return 1; }
G="$tmp/snaps/ovm-twin-guard"
# mkab ROOT: a plain team, seats Seat and Other with BOOT.md and INBOX.md.
mkab() {
  mkdir -p "$1/Seat" "$1/Other" "$1/_Team"; printf '# MB\n' > "$1/MISSION_BOARD.md"
  for s in Seat Other; do printf 'b\n' > "$1/$s/BOOT.md"; printf '## x - READ\n' > "$1/$s/INBOX.md"; done
  printf 'db\n' > "$1/_Team/team.db"; printf '| A |\n' > "$1/GOPHER_REGISTRY.md"
}
team="$tmp/team"; mkab "$team"; seat="$team/Seat"; log="$team/_twin-guard.log"
printf '2026-11-23 earlier line\n' > "$log"
budget="$tmp/guard-budget.sh"; sed 's/^BUDGET=5$/BUDGET=-1/' "$GUARD" > "$budget"

# ---------------------------------------------------------------- LOG
t "LOG: other twins' hook lines in the log during a call never alert"
hk A PreToolUse "$seat" true a1 > /dev/null
hk B PreToolUse "$seat" true b1 "$budget" > /dev/null      # logs a budget NOTE
printf '2026-11-23 another twin alert line\n' >> "$log"
hk B PostToolUse "$seat" true b1 > /dev/null
out=$(hk A PostToolUse "$seat" true a1)
[ -z "$out" ] && pass || fail "got: ${out:0:200}"

t "LOG: a real change in the same window is alerted, the log churn is not"
hk A PreToolUse "$seat" true a2 > /dev/null
printf 'more churn\n' >> "$log"; printf 'twin\n' >> "$team/Other/INBOX.md"
out=$(hk A PostToolUse "$seat" true a2)
case $out in
  *'_twin-guard.log'*) fail "log churn alerted: ${out:0:200}" ;;
  *'protected file changed during twin command: Other/INBOX.md'*) pass ;;
  *) fail "got: ${out:0:200}" ;;
esac

t "LOG: truncating, rewriting or deleting the log is still alerted"
bad=""
for how in truncate rewrite delete; do
  hk A PreToolUse "$seat" true "l$how" > /dev/null
  case $how in
    truncate) : > "$log" ;;
    rewrite) { printf 'forged history line one\n'; cat "$log"; } > "$tmp/forged"; cat "$tmp/forged" > "$log" ;;
    delete) rm -f "$log" ;;
  esac
  out=$(hk A PostToolUse "$seat" true "l$how")
  case $out in *'protected file changed during twin command: _twin-guard.log'*) ;; *) bad="$bad $how" ;; esac
  printf 'restored\n' >> "$log"
done
[ -z "$bad" ] && pass || fail "silent:$bad"

t "LOG: a log first created during the call (by a Post's own line) does not alert"
rm -f "$log"
hk A PreToolUse "$seat" true lnew > /dev/null
printf 'created by another hook\n' >> "$log"
out=$(hk A PostToolUse "$seat" true lnew)
[ -z "$out" ] && pass || fail "got: ${out:0:200}"

t "LOG: only the root's own log is append-only; a _twin-guard.log elsewhere is ordinary"
printf 'x\n' > "$team/Other/_twin-guard.log"
hk A PreToolUse "$seat" true lother > /dev/null
printf 'y\n' >> "$team/Other/_twin-guard.log"
out=$(hk A PostToolUse "$seat" true lother)
case $out in *'changed during twin command: Other/_twin-guard.log'*) pass ;; *) fail "got: ${out:0:200}" ;; esac
rm -f "$team/Other/_twin-guard.log"

# ---------------------------------------------------------------- PAR
t "PAR: four twins with interleaved Pre and Post, all clean, are all quiet"
rm -rf "$tmp/snaps"; mkdir -p "$tmp/snaps"
all=""
for a in P Q R S; do all="$all$(hk "$a" PreToolUse "$seat" true "${a}1" "$budget")"; done
printf 'line\n' >> "$log"
for a in R P S Q; do all="$all$(hk "$a" PostToolUse "$seat" true "${a}1")"; done
for a in Q S; do all="$all$(hk "$a" PreToolUse "$seat" true "${a}2")"; done
printf 'line\n' >> "$log"
for a in S Q; do all="$all$(hk "$a" PostToolUse "$seat" true "${a}2")"; done
[ -z "$all" ] && pass || fail "got: ${all:0:240}"

t "PAR: one twin's cut-off check never touches another twin's next call"
hk X PreToolUse "$seat" true x1 > /dev/null
printf 'post %s\n' $(( $(date +%s) - 60 )) > "$G/X.x1.busy"     # X's Post was cut off a minute ago
out=$(hk Y PreToolUse "$seat" true y1); out2=$(hk Y PostToolUse "$seat" true y1)
[ -z "$out$out2" ] && [ -s "$G/X.x1.busy" ] && pass || fail "Y: ${out:0:160} ${out2:0:160}"

t "PAR: records are keyed by agent and tool_use"
ls "$G" | grep -q '^X\.x1\.snap$' && ls "$G" | grep -q '^X\.x1\.ok$' && pass || fail "$(ls "$G" | head)"

# ---------------------------------------------------------------- STALE
t "STALE: a clean cut-off check of the same twin is settled quietly, with a NOTE in the log"
out=$(hk X PreToolUse "$seat" true x2); hk X PostToolUse "$seat" true x2 > /dev/null
if isdeny "$out" || [ -n "$out" ]; then fail "denied or spoke: ${out:0:200}"
elif [ -s "$G/X.x1.busy" ]; then fail "marker not cleared"
elif ! grep -q 'NOTE: previous check did not finish (X.x1.busy: post, [0-9]*s ago); re-checked from its record, no protected file changed' "$log"; then fail "no NOTE: $(tail -2 "$log")"
else pass; fi

t "STALE: a cut-off check whose window changed a protected file denies the next call and names the file"
hk X PreToolUse "$seat" true x3 > /dev/null
printf 'twin\n' >> "$team/Other/INBOX.md"
printf 'post %s\n' $(( $(date +%s) - 30 )) > "$G/X.x3.busy"
out=$(hk X PreToolUse "$seat" true x4)
if ! isdeny "$out"; then fail "not denied: ${out:0:200}"
else case $out in *'previous check did not finish'*'protected file changed since that command started: Other/INBOX.md'*)
  grep -q 'previous check did not finish (X.x3.busy: post, [0-9]*s ago); protected file changed since that command started: Other/INBOX.md' "$log" && pass || fail "not logged" ;;
  *) fail "got: ${out:0:240}" ;; esac
fi
out=$(hk X PreToolUse "$seat" true x5); hk X PostToolUse "$seat" true x5 > /dev/null
[ -z "$out" ] && pass || fail "reported twice: ${out:0:160}"

t "STALE: a stale marker whose record is gone is still reported"
hk X PreToolUse "$seat" true x6 > /dev/null
: > "$G/X.x6.snap"; printf 'post %s\n' $(( $(date +%s) - 30 )) > "$G/X.x6.busy"
out=$(hk X PreToolUse "$seat" true x7); hk X PostToolUse "$seat" true x7 > /dev/null
case $out in *'previous check did not finish'*'record is gone'*) isdeny "$out" && pass || fail "not denied" ;; *) fail "got: ${out:0:200}" ;; esac

t "STALE: a Post that never ran (pre marker over 11 minutes) is settled from its record"
hk X PreToolUse "$seat" true x8 > /dev/null
printf 'pre %s\n' $(( $(date +%s) - 700 )) > "$G/X.x8.busy"
out=$(hk X PreToolUse "$seat" true x9); hk X PostToolUse "$seat" true x9 > /dev/null
[ -z "$out" ] && [ ! -s "$G/X.x8.busy" ] && pass || fail "got: ${out:0:200}"

t "STALE: a fresh pre marker (a parallel call of the same twin still running) is left alone"
hk X PreToolUse "$seat" true xa > /dev/null
out=$(hk X PreToolUse "$seat" true xb); hk X PostToolUse "$seat" true xb > /dev/null
out2=$(hk X PostToolUse "$seat" true xa)
[ -z "$out$out2" ] && pass || fail "got: ${out:0:160} ${out2:0:160}"

t "STALE: a Post cut off by a hanging walk leaves its record whole for the next Pre"
mkdir -p "$tmp/slowbin"; printf '#!/bin/sh\nsleep 30\n' > "$tmp/slowbin/find"; chmod +x "$tmp/slowbin/find"
hk X PreToolUse "$seat" true xc > /dev/null
printf '{"session_id":"s1","cwd":"%s","hook_event_name":"PostToolUse","agent_id":"X","agent_type":"%s","tool_name":"Bash","tool_input":{"command":"true"},"tool_use_id":"xc"}' \
  "$(js "$seat")" "$TWIN" > "$tmp/xc.json"
{ PATH="$tmp/slowbin:$PATH" TMPDIR="$tmp/snaps" "$B" "$GUARD" < "$tmp/xc.json" > /dev/null 2>&1 & } 2>/dev/null; p=$!
sleep 4; kill -9 "$p" 2>/dev/null; wait "$p" 2>/dev/null
[ -s "$G/X.xc.snap" ] && [ -s "$G/X.xc.ok" ] && grep -q '^post ' "$G/X.xc.busy" && pass || fail "record or marker gone"
: > "$G/X.xc.busy"

# ---------------------------------------------------------------- COST
t "COST: Python package trees are pruned from the walk: 30k venv files add next to nothing to a check"
py=""; for c in python3 python; do command -v "$c" >/dev/null 2>&1 && "$c" -c 'import os' >/dev/null 2>&1 && { py=$c; break; }; done
if [ -z "$py" ]; then echo "  SKIP: no python to build 30k files quickly"; pass
else
  # The same team without the venvs is the baseline: on a loaded machine
  # process start-up, not the walk, sets the floor, so time is compared.
  bteam="$tmp/bteam"; mkab "$bteam"
  s0=$SECONDS
  hk C PreToolUse "$bteam/Seat" true c0 > /dev/null; hk C PostToolUse "$bteam/Seat" true c0 > /dev/null
  base=$(( SECONDS - s0 ))
  cteam="$tmp/cteam"; mkab "$cteam"
  ( cd "$cteam" && "$py" - <<'PY'
import os
for v in ('proj/a/Lib/site-packages', 'proj/b/lib/python3.12/site-packages', 'proj/c/.venv', 'proj/d/venv', 'proj/e/__pycache__'):
    for i in range(6000):
        d = os.path.join(v, 'p%03d' % (i // 100))
        os.makedirs(d, exist_ok=True)
        open(os.path.join(d, 'm%05d.py' % i), 'w').write('x')
open(os.path.join('proj/a/Lib/site-packages', 'HANDOFF.md'), 'w').write('pkg doc')
PY
  )
  s0=$SECONDS
  hk C PreToolUse "$cteam/Seat" true c1 > /dev/null
  cp "$G/C.c1.snap" "$tmp/c1.snap" 2>/dev/null
  out=$(hk C PostToolUse "$cteam/Seat" true c1)
  big=$(( SECONDS - s0 ))
  # For scale only: the 5.1.0 guard walks all of it.
  oldg="$tmp/guard-a7f9693-cost.sh"; oldt=""
  if git -C "$repo" show a7f9693:hooks/twin-guard.sh > "$oldg" 2>/dev/null; then
    s0=$SECONDS; hk C PreToolUse "$cteam/Seat" true c2 "$oldg" > /dev/null; hk C PostToolUse "$cteam/Seat" true c2 "$oldg" > /dev/null
    oldt=" (the 5.1.0 guard: $(( SECONDS - s0 ))s)"
  fi
  echo "  Pre+Post: ${base}s without the venvs, ${big}s with 30k venv files$oldt"
  if grep -q 'site-packages' "$tmp/c1.snap" 2>/dev/null; then fail "site-packages walked"
  elif ! grep -q 'Other/INBOX.md' "$tmp/c1.snap" 2>/dev/null; then fail "seat files not recorded"
  elif [ "$big" -gt $(( base * 2 + 3 )) ]; then fail "${big}s against a ${base}s baseline"
  else [ -z "$out" ] && pass || fail "post: ${out:0:160}"; fi
fi

t "COST: a seat file is still found at any depth outside the pruned trees"
mkdir -p "$team/Seat/archive/2026/11/old"; printf 'old\n' > "$team/Seat/archive/2026/11/old/HANDOFF.md"
hk A PreToolUse "$seat" true cd1 > /dev/null
printf 'x\n' >> "$team/Seat/archive/2026/11/old/HANDOFF.md"
out=$(hk A PostToolUse "$seat" true cd1)
case $out in *'Seat/archive/2026/11/old/HANDOFF.md'*) pass ;; *) fail "got: ${out:0:200}" ;; esac

# ---------------------------------------------------------------- VAR
old="$tmp/guard-a7f9693.sh"
git -C "$repo" show a7f9693:hooks/twin-guard.sh > "$old" 2>/dev/null || old=""
scratch="$tmp/scratchpad"; mkdir -p "$scratch/src"; printf 'a\n' > "$scratch/f.txt"; printf 's\n' > "$scratch/src/s.txt"
printf 'q\n' > "$tmp/qa.md"
sw=$(cygpath -w "$scratch" 2>/dev/null || printf '%s' "$scratch")

t "VAR: scratch-folder writes through a variable, and cd then copy, pass (the 5.1.0 guard denied each)"
bad=0 olddeny=0 n=0
while IFS= read -r c; do
  [ -n "$c" ] || continue
  c=${c//@S@/$scratch}; c=${c//@W@/$sw}; c=${c//@Q@/$tmp/qa.md}
  n=$((n + 1))
  r=$(hk V PreToolUse "$seat" "$c" v1)
  isdeny "$r" && { bad=1; echo "    denied: $c"; }
  if [ -n "$old" ]; then r=$(hk V PreToolUse "$seat" "$c" v1 "$old"); isdeny "$r" && olddeny=$((olddeny + 1)); fi
done <<'CORPUS'
SP="@S@"; mkdir -p "$SP"
SP="@S@"; mkdir -p "$SP" && sed -i s/a/b/ "$SP/f.txt"
SP='@W@'; mkdir -p "$SP"
SP=@S@ && touch "$SP"/new.txt && rm -f "$SP"
D="@S@/out"; mkdir -p "$D" && echo hi > "$D/o.txt"
SP="@S@"; OUT="$SP/o.txt"; printf x > "$OUT"
SP="@S@"; cp -r "$SP/src/." "${SP}"
cd "@S@" && cp "@Q@" .
cd "@S@" && cp -r src/. . && ls | head -3
export SP="@S@"; tee "$SP/t.txt" < /dev/null
CORPUS
echo "  $n scratch commands; the 5.1.0 guard denied $olddeny of them"
[ $bad -eq 0 ] && pass || fail "see above"

t "VAR: the scratch commands run quietly through Pre and Post"
out=$(hk V PreToolUse "$seat" "SP=\"$scratch\"; mkdir -p \"\$SP/run\" && printf x > \"\$SP/run/o.txt\"" v2)
(cd "$seat" && SP="$scratch" bash -c 'mkdir -p "$SP/run" && printf x > "$SP/run/o.txt"')
out="$out$(hk V PostToolUse "$seat" "SP=\"$scratch\"; mkdir -p \"\$SP/run\" && printf x > \"\$SP/run/o.txt\"" v2)"
[ -z "$out" ] && [ -f "$scratch/run/o.txt" ] && pass || fail "got: ${out:0:200}"

t "VAR: every team-state file is still denied through a variable, in every write form"
bad=0 n=0
asgs=("F=\"@F@\"; " "F='@F@'; " "F=@F@ && " "export F=\"@F@\"; " "G=\"@F@\"; F=\"\$G\"; " "F=/tmp/ok; if [ -n x ]; then F=\"@F@\"; fi; ")
for f in "INBOX.md" "../Other/INBOX.md" "HANDOFF.md" "HANDOFF-OPS-9.md" "mission-complete-OPS-9.md" "BOOT.md" "CLAUDE.md" \
         "../GOPHER_REGISTRY.md" "../MISSION_BOARD.md" "../_Team/team.db" "../WORKING_WITH_T.md" "../_twin-guard.log" \
         "$team/Other/INBOX.md" "../_claims/x" "../Other/.go-claim/x" "../_ids/OPS-1"; do
  for form in 'touch "$F"' 'echo x > "$F"' 'echo x >> "$F"' 'cp /tmp/a "$F"' 'sed -i s/a/b/ "$F"' 'rm -f "$F"' 'echo x | tee -a "$F"' 'dd if=/dev/null of="$F"' 'mv /tmp/a "${F}"' 'ln -sf /tmp/a "$F"'; do
    asg=${asgs[n % 6]}; asg=${asg//@F@/$f}   # every assignment shape, in turn
    c="$asg$form"; n=$((n + 1))
    r=$(hk V PreToolUse "$seat" "$c" v3)
    isdeny "$r" || { bad=$((bad + 1)); echo "    allowed: $c"; }
  done
done
echo "  $n variable-built team-state writes"
[ $bad -eq 0 ] && pass || fail "$bad allowed"

t "VAR: evasions that hide what a variable holds are denied"
bad=0
while IFS= read -r c; do
  [ -n "$c" ] || continue
  r=$(hk V PreToolUse "$seat" "$c" v4)
  isdeny "$r" || { bad=1; echo "    allowed: $c"; }
done <<'CORPUS'
S=../Other/INBOX.m; echo x > "$S"d
S=../Other/INBOX.m; touch "$S"d
S=../Other/INBOX.m; touch "${S}d"
S="/tmp/x ../Other/BOOT.md"; rm $S
S="../Other/BOOT.md /tmp/x"; rm $S
S=/tmp/x touch "$S"
for S in /tmp/x; do touch "$S"; done
read S < list; touch "$S"
S=/tmp/x; S+=y; touch "$S"
touch "${S:-x}"
S=$(pwd); cp -r /tmp/x/. "$S"
S=`pwd`; touch "$S"
IFS=/; S=a/b; touch $S
f() { S=../Other/HANDOFF.md; }; S=/tmp/x; f; touch "$S"
S=/tmp/x; trap 'S=../Other/INBOX.md' EXIT; echo x > "$S"
S=/tmp/x; S[0]=y; touch "$S"
S=~/x; touch "$S"
echo x > "$HOME"
touch "$TMPDIR"
echo x > "$S"
S="../Other"; cp -r /tmp/x/. "$S"
S="../Other"; cp -r /tmp/x/. "$S/"
S="$PWD/../Other"; rsync -r /tmp/x/ "$S"
D=..; cp -r /tmp/x/. "$D/Other"
S='$X'; touch $S
CORPUS
# A nameref, spelled at run time so the bash 3.2 lint never reads it as one.
dcl=declare
r=$(hk V PreToolUse "$seat" "$dcl -n S=T; T=../Other/INBOX.m; touch \"\${S}d\"" v4)
isdeny "$r" || { bad=1; echo "    allowed: a nameref"; }
[ $bad -eq 0 ] && pass || fail "see above"

t "VAR: cd moves the folder only when the chain is sure to have made it"
bad=0
while IFS= read -r c; do
  [ -n "$c" ] || continue
  c=${c//@T@/$team}; c=${c//@S@/$scratch}
  r=$(hk V PreToolUse "$scratch" "$c" v5)
  isdeny "$r" || { bad=1; echo "    allowed: $c"; }
done <<'CORPUS'
cd "@T@/Other" && cp -r /tmp/x/. .
cd "@T@/Other" && cp /tmp/x/qa.md . && cp -r /tmp/y/. .
cd @T@ && cd Other && cp -r /tmp/x/. .
cd /no/such/dir; cp -r src/. "@T@/Other"
cd "@T@/Other"; cp -r src/. .
cd "@S@" && cp -r src/. . || cp -r src/. "@T@/Other"
D="@T@/Other"; cd "$D" && cp -r /tmp/x/. .
D="@T@/Other" && cd "$D" && cp -r /tmp/x/. .
cd "${D:-@T@/Other}" && cp -r /tmp/x/. .
cd "@T@/Other" | cat && cp -r src/. .
cd ../Other && touch BOOT.md
CORPUS
# The hook's cwd is a seat folder: a cd that may not happen leaves it in play.
for c in "cd /no/such/dir; cp -r src/. ." "cd \"\$UNSET_DIR\" && cp -r src/. ." "cd $scratch || true; cp -r src/. ." "(cd $scratch) && cp -r src/. ."; do
  r=$(hk V PreToolUse "$seat" "$c" v6)
  isdeny "$r" || { bad=1; echo "    allowed from the seat: $c"; }
done
[ $bad -eq 0 ] && pass || fail "see above"

t "VAR: links and junctions to team state are denied as write targets (Write, Edit, Bash)"
lk="$scratch/links"; mkdir -p "$lk"
mk() { # mk TARGET LINK: a symlink, or a junction for a folder on Windows; 1 if neither works
  MSYS=winsymlinks:nativestrict ln -s "$1" "$2" 2>/dev/null && [ -L "$2" ] && return 0
  rm -rf "$2"
  if [ -d "$1" ] && command -v cmd >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1; then
    MSYS2_ARG_CONV_EXCL='*' cmd /c mklink /J "$(cygpath -w "$2")" "$(cygpath -w "$1")" > /dev/null 2>&1 && [ -L "$2" ] && return 0
  fi
  rm -rf "$2"; return 1
}
if mk "$team/Other/INBOX.md" "$lk/notes.md"; then
  bad=0
  isdeny "$(hw V Write "$lk/notes.md")" || { bad=1; echo "    Write through a file link allowed"; }
  isdeny "$(hw V Edit "$lk/notes.md")" || { bad=1; echo "    Edit through a file link allowed"; }
  for c in "echo x > notes.md" "echo x >> ./notes.md" "cp /tmp/a notes.md" "touch notes.md" "L=notes.md; echo x > \"\$L\""; do
    isdeny "$(hk V PreToolUse "$lk" "$c" v7)" || { bad=1; echo "    allowed: $c"; }
  done
  isdeny "$(hk V PreToolUse "$seat" "cd $lk && echo x > notes.md" v7)" || { bad=1; echo "    allowed after cd"; }
  [ -z "$(hw V Write "$scratch/plain.md")" ] || { bad=1; echo "    plain Write denied"; }
  [ $bad -eq 0 ] && pass || fail "see above"
else
  echo "  SKIP: this system can't make a symlink here"; pass
fi
if mk "$team/Other" "$lk/od"; then
  bad=0
  for c in "cp -r /tmp/x/. od/" "cp -r /tmp/x/. od" "rsync -r /tmp/x/ ./od"; do
    isdeny "$(hk V PreToolUse "$lk" "$c" v8)" || { bad=1; echo "    allowed: $c"; }
  done
  [ $bad -eq 0 ] && pass || fail "see above"
else
  echo "  SKIP: this system can't make a folder link or junction here"; pass
fi

t "VAR: relative paths into team folders are denied as before"
bad=0
for c in "cp -r /tmp/x/. ../Other" "cp -r /tmp/x/. ../Other/" "rsync -a /tmp/x/ ../Other/" "mv ../Other /tmp/gone" "rm -rf ../Other" "cp /tmp/a ."; do
  isdeny "$(hk V PreToolUse "$seat" "$c" v9)" || { bad=1; echo "    allowed: $c"; }
done
[ $bad -eq 0 ] && pass || fail "see above"

finish
