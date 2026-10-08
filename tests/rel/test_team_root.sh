#!/usr/bin/env bash
# tests/rel/test_team_root.sh -- the team root under retired bridge copies
# (OPS-030 release lane). Every live seat folder keeps a MISSION_BOARD.md
# headed "RETIRED BRIDGE COPY" as a pointer. TARS and /go's claim.sh must take
# the NEAREST live board (A-37 P2: cwd plus two parents for TARS; the seat
# folder's parent and grandparent for claim.sh), never a seat folder's stub,
# and never a board planted above the team root.
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
TH="$tmp/tarshome"

stub='# MISSION BOARD \342\200\224 RETIRED BRIDGE COPY\n\nThe board lives at the team root.\n'
mkteam() {
  local r=$1
  mkdir -p "$r/Nash - Developer/work/deep" "$r/T-Bot - The Overmind"
  cat > "$r/MISSION_BOARD.md" <<'EOF'
# MISSION BOARD

## Active

| ID | Mission | Owner | Assignee | Status | Priority | Blocker | Last Touched |
|----|---------|-------|----------|--------|----------|---------|--------------|
| AXM-046 | Level deep dive | T-Bot | Nash | ACTIVE | HIGH | | 2026-10-05 |
EOF
  for s in "Nash - Developer" "T-Bot - The Overmind"; do
    printf '# BOOT\n' > "$r/$s/BOOT.md"; printf "$stub" > "$r/$s/MISSION_BOARD.md"
  done
}
team="$tmp/team"; mkteam "$team"

# jpath PATH: the path as a JSON string body (Windows form under Git Bash).
jpath() {
  local w=$1
  if command -v cygpath >/dev/null 2>&1; then w=$(cygpath -w "$1"); fi
  w=${w//\\/\\\\}
  printf '%s' "$w"
}
turn() { # SID CWD: one UserPromptSubmit turn
  printf '{"session_id":"%s","transcript_path":"","cwd":"%s","permission_mode":"default","hook_event_name":"UserPromptSubmit","prompt":"hi"}' "$1" "$(jpath "$2")" |
    TARS_HOME="$TH" "$B" "$TARS" 2>/dev/null
}
pin() { tr -d '\r' < "$TH/sessions/$1/seat" 2>/dev/null | sed -n "${2}p"; }

# ---------------------------------------------------------------- TARS
t "TARS: a seat folder holding a stub board pins the team root, as a specialist"
turn nash1 "$team/Nash - Developer" > /dev/null
r=$(pin nash1 2); s=$(pin nash1 3)
[ "$(pin nash1 1)" = specialist ] && [ "${r##*/}" = team ] && [ "${s##*/}" = "Nash - Developer" ] && pass || fail "pin: $(pin nash1 1) | $r | $s"

t "TARS: the Overmind's seat folder pins the team root and hears a seat's mission-complete"
turn tb1 "$team/T-Bot - The Overmind" > /dev/null
touch -t 200001010000 "$TH/sessions/tb1/marker"
printf '# Mission complete\n\nAXM-046 done.\n' > "$team/Nash - Developer/mission-complete.md"
out=$(turn tb1 "$team/T-Bot - The Overmind")
r=$(pin tb1 2)
case $out in *'TARS: Nash - Developer wrote mission-complete for AXM-046.'*) [ "${r##*/}" = team ] && pass || fail "root $r" ;; *) fail "pin $(pin tb1 1) $r; out: $out" ;; esac
rm -f "$team/Nash - Developer/mission-complete.md"

t "TARS: a cwd one level below a seat still finds the team root (two parents)"
turn nash2 "$team/Nash - Developer/work" > /dev/null
r=$(pin nash2 2); s=$(pin nash2 3)
[ "${r##*/}" = team ] && [ "${s##*/}" = "Nash - Developer" ] && pass || fail "pin: $r | $s"

t "TARS: a stale pin naming a seat folder as the root is re-derived"
turn nash3 "$team/Nash - Developer" > /dev/null
printf 'overmind\n%s\n%s\n' "$(pin nash3 3)" "$(pin nash3 3)" > "$TH/sessions/nash3/seat"
turn nash3 "$team/Nash - Developer" > /dev/null
r=$(pin nash3 2)
[ "$(pin nash3 1)" = specialist ] && [ "${r##*/}" = team ] && pass || fail "pin: $(pin nash3 1) | $r"

t "TARS: a lone seat whose only board is a stub has no team root"
lone="$tmp/lone/Seat"; mkdir -p "$lone"; printf "$stub" > "$lone/MISSION_BOARD.md"; printf '# BOOT\n' > "$lone/BOOT.md"
turn lone1 "$lone" > /dev/null
[ -z "$(pin lone1 2)" ] && [ "$(pin lone1 1)" = specialist ] && pass || fail "pin: $(pin lone1 1) | $(pin lone1 2)"

t "TARS: a team root's own cwd is still the Overmind's"
turn root1 "$team" > /dev/null
r=$(pin root1 2); s=$(pin root1 3)
[ "$(pin root1 1)" = overmind ] && [ "${r##*/}" = team ] && [ "${s##*/}" = "T-Bot - The Overmind" ] && pass || fail "pin: $(pin root1 1) | $r | $s"

# ---------------------------------------------------------------- claim.sh
brief() { # FILE TYPE SEAT MISSION WRITTEN
  printf 'SESSION HANDOFF\n\nTYPE: %s\nSEAT: %s\nMISSION: %s\nWRITTEN: %s\nDISPATCHED BY: T-Bot\n\n## NEXT STEPS\n\n1. Do it.\n' "$2" "$3" "$4" "$5" > "$1"
}
t "claim.sh: a seat folder under a seat that holds a stub board reads the team root's board"
work="$team/Nash - Developer/work"
brief "$work/HANDOFF.md" DISPATCH Nash AXM-046 "2026-10-05 09:00"
out=$("$B" "$CLAIM" --check "$work" "$work/HANDOFF.md" s1 Nash 2>&1; echo "rc=$?")
case $out in *CLAIMABLE*"rc=0") pass ;; *) fail "$(printf '%s' "$out" | tr '\n' ' ')" ;; esac

t "claim.sh: an ordinary seat folder still reads the team root's board"
brief "$team/Nash - Developer/HANDOFF.md" DISPATCH Nash AXM-046 "2026-10-05 09:00"
out=$("$B" "$CLAIM" --check "$team/Nash - Developer" "$team/Nash - Developer/HANDOFF.md" s1 Nash 2>&1; echo "rc=$?")
case $out in *CLAIMABLE*"rc=0") pass ;; *) fail "$(printf '%s' "$out" | tr '\n' ' ')" ;; esac

# ---------------------------------------------------------------- A-37 P2
# A live board planted above the team root must not take it over: TARS and
# claim.sh take the NEAREST live board (only the twin guard takes the outermost).
printf '# MISSION BOARD

## Active

| ID | Mission | Owner | Assignee | Status |
|----|---------|-------|----------|--------|
' > "$tmp/MISSION_BOARD.md"

t "A-37 P2: TARS keeps the team root when a live board is planted above it"
turn plant1 "$team/Nash - Developer" > /dev/null
r=$(pin plant1 2)
[ "${r##*/}" = team ] && pass || fail "root moved to $r"

t "A-37 P2: claim.sh's verdict doesn't change when a live board is planted above the team root"
out=$("$B" "$CLAIM" --check "$team/Nash - Developer" "$team/Nash - Developer/HANDOFF.md" s1 Nash 2>&1; echo "rc=$?")
case $out in *CLAIMABLE*"rc=0") pass ;; *) fail "$(printf '%s' "$out" | tr '\n' ' ')" ;; esac
rm -f "$tmp/MISSION_BOARD.md"

finish
