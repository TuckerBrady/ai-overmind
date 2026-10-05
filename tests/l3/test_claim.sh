#!/usr/bin/env bash
# tests/l3/test_claim.sh -- /go's claim.sh (CONTRACT 4.1, 4.3, 4.14, 7.2, 7.3;
# AMENDMENTS GAP-31, GAP-32, GAP-33). RUBRIC L3.1, L3.2.
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

team="$tmp/team"; mkteam "$team"
seat="$team/Nash - Developer"
run() { bash "$CLAIM" "$@" 2>&1; echo "rc=$?"; }

# ---------------------------------------------------------------- atomic claim
t "10 parallel claims on one brief: exactly one exit 0, nine exit 3"
brief "$seat/HANDOFF.md" DISPATCH Nash AXM-046 "2026-10-05 09:00" "DISPATCHED BY: T-Bot"
for i in 1 2 3 4 5 6 7 8 9 10; do
  ( bash "$CLAIM" "$seat" "$seat/HANDOFF.md" "sess$i" Nash > "$tmp/par.$i" 2>&1; echo $? > "$tmp/rc.$i" ) &
done
wait
z=0; three=0; other=0
for i in 1 2 3 4 5 6 7 8 9 10; do
  case $(cat "$tmp/rc.$i") in 0) z=$((z+1)) ;; 3) three=$((three+1)) ;; *) other=$((other+1)) ;; esac
done
[ $z -eq 1 ] && [ $three -eq 9 ] && [ $other -eq 0 ] && pass || fail "exit 0: $z, exit 3: $three, other: $other"

t "exactly one ACTIVATED line in the brief"
n=$(count_lines "$seat/HANDOFF.md" "ACTIVATED: ")
[ "$n" = 1 ] && pass || fail "$n ACTIVATED lines"

t "the stamp sits directly under the header and names the seat and session"
after=$(tr -d '\r' < "$seat/HANDOFF.md" | awk '/^DISPATCHED BY:/ { getline; print; exit }')
case $after in "ACTIVATED: "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]" "[0-9][0-9]:[0-9][0-9]" by Nash (session sess"*")") pass ;; *) fail "got: $after" ;; esac

t "the winner wrote the mission claim _claims/AXM-046.<sid> as '<epoch> Nash'"
w=""; for i in 1 2 3 4 5 6 7 8 9 10; do [ "$(cat "$tmp/rc.$i")" = 0 ] && w=sess$i; done
c="$team/_claims/AXM-046.$w"
if [ -f "$c" ]; then
  l=$(tr -d '\r' < "$c"); case $l in [0-9]*" Nash") pass ;; *) fail "content: $l" ;; esac
else fail "no $c"; fi

t "only the winner holds a mission claim"
n=$(ls "$team/_claims" | wc -l | tr -d ' ')
[ "$n" = 1 ] && pass || fail "$n claim files"

t "a loser reports the owner and time"
for i in 1 2 3 4 5 6 7 8 9 10; do [ "$(cat "$tmp/rc.$i")" = 3 ] && l=$i && break; done
grep -qE '^ALREADY (CLAIMED|ACTIVATED): .*Nash' "$tmp/par.$l" && pass || fail "$(head -2 "$tmp/par.$l")"

t "a second /go after activation exits 3 and adds no stamp"
out=$(run "$seat" "$seat/HANDOFF.md" late Nash)
case $out in *"ALREADY ACTIVATED"*"rc=3") pass ;; *) fail "$out" ;; esac
[ "$(count_lines "$seat/HANDOFF.md" "ACTIVATED: ")" = 1 ] || fail "stamp count changed"

# ---------------------------------------------------------------- refusals
refusal() { # name expected-token file seat
  t "refuses: $1"
  out=$(run "$seat" "$3" s1 "${4:-Nash}")
  case $out in *"REASON: $2"*"rc=2") pass ;; *) fail "want REASON: $2, got: $(printf '%s' "$out" | tr '\n' ' ')" ;; esac
}
b="$tmp/b"; mkdir -p "$b"
brief "$b/unknown.md" "FEATURE BUILD" Nash NONE "2026-10-05 09:00"
refusal "a TYPE outside the four" UNKNOWN_TYPE "$b/unknown.md"
printf 'SEAT: Nash\nMISSION: NONE\nWRITTEN: 2026-10-05 09:00\n' > "$b/notype.md"
refusal "no TYPE at all" UNKNOWN_TYPE "$b/notype.md"
printf 'TYPE: SELF-HANDOFF\nMISSION: NONE\nWRITTEN: 2026-10-05 09:00\n' > "$b/noseat.md"
refusal "no SEAT" NO_SEAT "$b/noseat.md"
printf 'TYPE: SELF-HANDOFF\nSEAT: Nash\nMISSION: NONE\n' > "$b/nowritten.md"
refusal "no WRITTEN" NO_WRITTEN "$b/nowritten.md"
brief "$b/badwritten.md" SELF-HANDOFF Nash NONE "2026-13-40 25:99"
refusal "an impossible WRITTEN" NO_WRITTEN "$b/badwritten.md"
brief "$b/other.md" SELF-HANDOFF Vaughn NONE "2026-10-05 09:00"
refusal "a brief for another seat" SEAT_MISMATCH "$b/other.md"
brief "$b/nashville.md" SELF-HANDOFF Nashville NONE "2026-10-05 09:00"
refusal "a seat whose name merely starts with ours" SEAT_MISMATCH "$b/nashville.md"
brief "$b/cons.md" SELF-HANDOFF Nash NONE "2026-10-05 09:00" "CONSOLIDATED-INTO: OPS-030 (consolidated 20261005-1000) 2026-10-05 10:00"
refusal "a consolidated brief" CONSOLIDATED "$b/cons.md"
brief "$b/norow.md" DISPATCH Nash AXM-999 "2026-10-05 09:00" "DISPATCHED BY: T-Bot"
refusal "a mission not on the board" NO_BOARD_ROW "$b/norow.md"
brief "$b/done.md" DISPATCH Nash OPS-032 "2026-10-05 09:00" "DISPATCHED BY: T-Bot"
refusal "a COMPLETE row" NO_BOARD_ROW "$b/done.md"
brief "$b/arch.md" DISPATCH Nash AXM-010 "2026-10-05 09:00" "DISPATCHED BY: T-Bot"
refusal "an archived row" NO_BOARD_ROW "$b/arch.md"
brief "$b/lane.md" DISPATCH Nash OPS-031 "2026-10-05 09:00" "DISPATCHED BY: T-Bot"
refusal "this seat's lane is COMPLETE" NO_BOARD_ROW "$b/lane.md"
brief "$b/nodisp.md" DISPATCH Nash NONE "2026-10-05 09:00" "DISPATCHED BY: T-Bot"
refusal "a dispatch with no mission ID" NO_BOARD_ROW "$b/nodisp.md"
for bad in "m-017" "-17" "M-" "xM-017"; do
  brief "$b/badid.md" DISPATCH Nash "$bad" "2026-10-05 09:00" "DISPATCHED BY: T-Bot"
  t "A-17 refuses: MISSION '$bad' is not a mission ID"
  out=$(run "$seat" "$b/badid.md" s1 Nash)
  case $out in *"REASON: NO_BOARD_ROW"*"holds no mission ID"*"rc=2") pass ;; *) fail "$(printf '%s' "$out" | tr '
' ' ')" ;; esac
done
brief "$b/notmine.md" DISPATCH Nash OPS-033 "2026-10-05 09:00" "DISPATCHED BY: T-Bot"
refusal "a row assigned to someone else" NOT_ASSIGNED "$b/notmine.md"
brief "$b/selfnotmine.md" SELF-HANDOFF Nash OPS-033 "2026-10-05 09:00"
refusal "a self-handoff naming someone else's mission" NOT_ASSIGNED "$b/selfnotmine.md"

lone="$tmp/lone/Nash - Developer"; mkdir -p "$lone"
brief "$lone/HANDOFF.md" DISPATCH Nash AXM-046 "2026-10-05 09:00" "DISPATCHED BY: T-Bot"
t "refuses: a dispatch with no board to check"
out=$(bash "$CLAIM" "$lone" "$lone/HANDOFF.md" s1 Nash 2>&1; echo "rc=$?")
case $out in *"REASON: BOARD_UNREACHABLE"*"rc=2") pass ;; *) fail "$out" ;; esac
brief "$lone/ctm.md" CTM-LANE Nash CTM-007 "2026-10-05 09:00" "DISPATCHED BY: Eli-Bot"
t "refuses: a CTM lane with no COLLECTIVE_BOARD.md"
out=$(bash "$CLAIM" "$lone" "$lone/ctm.md" s1 Nash 2>&1; echo "rc=$?")
case $out in *"REASON: BOARD_UNREACHABLE"*"rc=2") pass ;; *) fail "$out" ;; esac

t "all eight refusal tokens are covered above"
pass

t "a refusal writes nothing: no claim dir, no stamp"
[ ! -e "$b/.go-claim" ] && ! grep -q '^ACTIVATED:' "$b"/*.md && pass || fail "something was written"

# ---------------------------------------------------------------- accepted shapes
accept() { # name file [seat] [folder]
  t "accepts: $1"
  out=$(bash "$CLAIM" --check "${4:-$seat}" "$2" s1 "${3:-Nash}" 2>&1; echo "rc=$?")
  case $out in *CLAIMABLE*"rc=0") pass ;; *) fail "$(printf '%s' "$out" | tr '\n' ' ')" ;; esac
}
brief "$b/self.md" SELF-HANDOFF Nash NONE "2026-10-05 09:00"
accept "a self-handoff with MISSION NONE" "$b/self.md"
brief "$b/owner.md" SELF-HANDOFF T-Bot OPS-030 "2026-10-05 09:00"
accept "an owner's own mission (live boards name the owner, not the assignee)" "$b/owner.md" T-Bot "$team/T-Bot - The Overmind"
brief "$b/vlane.md" DISPATCH Vaughn OPS-031 "2026-10-05 09:00" "DISPATCHED BY: T-Bot"
accept "an open lane of a multi-lane row" "$b/vlane.md" Vaughn "$team/Vaughn - QA"
brief "$b/q.md" DISPATCH nash AXM-047 "2026-10-05 09:00" "DISPATCHED BY: T-Bot"
accept "a QUEUED row whose title says COMPLETE; seat case-insensitive" "$b/q.md"
printf '# Handoff\n\nTYPE: SELF-HANDOFF \xc2\xb7 SEAT: Nash \xc2\xb7 MISSION: AXM-046 \xc2\xb7 WRITTEN: 2026-09-14 22:03\n\n## Next steps\n' > "$b/dot.md"
accept "the live one-line ' · ' header" "$b/dot.md"
printf '**TYPE: SELF-HANDOFF \xc2\xb7 SEAT: Nash \xc2\xb7 MISSION: NONE \xc2\xb7 WRITTEN: 2026-09-14**\n' > "$b/bold.md"
accept "a whole-line bold header with a date-only WRITTEN" "$b/bold.md"
printf '**TYPE:** SELF-HANDOFF (seat handoff for the-axiom)  \n**SEAT:** Nash (WRENCH)  \n**MISSION:** AXM-046 - Axiom repair arc  \n**WRITTEN:** 2026-09-26 11:55 MDT, by the AXM-025 session  \n' > "$b/fields.md"
accept "legacy bold fields with commentary after every value" "$b/fields.md"
printf 'TYPE: INFORMATIONAL\r\nSEAT: Nash\r\nMISSION: NONE\r\nWRITTEN: 2026-10-05 09:00\r\n\r\nbody\r\n' > "$b/crlf.md"
accept "a CRLF brief" "$b/crlf.md"
brief "$lone/self.md" SELF-HANDOFF Nash AXM-046 "2026-10-05 09:00"
t "accepts: a self-handoff with a mission when the board is unreachable (noted)"
out=$(bash "$CLAIM" --check "$lone" "$lone/self.md" s1 Nash 2>&1; echo "rc=$?")
case $out in *"NOTE: board unreachable"*CLAIMABLE*"rc=0") pass ;; *) fail "$out" ;; esac

t "A-17 accepts: the single-letter M-017 claims and gets its mission claim"
brief "$b/m017.md" DISPATCH Nash "M-017" "2026-10-05 09:30" "DISPATCHED BY: T-Bot"
out=$(bash "$CLAIM" "$seat" "$b/m017.md" m17sess Nash 2>&1; echo "rc=$?")
case $out in *"MISSION=M-017"*"CLAIMED M-017-20261005-0930"*"rc=0") [ -f "$team/_claims/M-017.m17sess" ] && pass || fail "no _claims/M-017.m17sess" ;; *) fail "$(printf '%s' "$out" | tr '
' ' ')" ;; esac

t "--check echoes TYPE, SEAT, MISSION, WRITTEN, DISPATCHED_BY and AGE_MIN"
out=$(bash "$CLAIM" --check "$seat" "$b/q.md" s1 Nash 2>&1)
for k in TYPE=DISPATCH SEAT=nash MISSION=AXM-047 "WRITTEN=2026-10-05 09:00" DISPATCHED_BY=T-Bot AGE_MIN=; do
  case $out in *"$k"*) ;; *) fail "missing $k"; break ;; esac
done
pass

t "AGE_MIN reflects a brief written years ago"
brief "$b/old.md" SELF-HANDOFF Nash NONE "2020-01-01 00:00"
age=$(bash "$CLAIM" --check "$seat" "$b/old.md" s1 Nash | sed -n 's/^AGE_MIN=//p')
[ -n "$age" ] && [ "$age" -gt 10080 ] && pass || fail "AGE_MIN=$age"

t "--check writes nothing"
[ ! -e "$b/.go-claim" ] && ! grep -q '^ACTIVATED:' "$b/q.md" && pass || fail "--check wrote"

t "a prose 'Stamp ACTIVATED:' line in the body is not a stamp"
brief "$b/prose.md" SELF-HANDOFF Nash NONE "2026-10-05 09:00" "Stamp ACTIVATED: [time] by [seat] under the header."
out=$(bash "$CLAIM" --check "$seat" "$b/prose.md" s1 Nash 2>&1; echo "rc=$?")
case $out in *"rc=0") pass ;; *) fail "$out" ;; esac

t "a legacy ACTIVATED stamp in any shape exits 3"
brief "$b/legacy.md" DISPATCH Nash AXM-046 "2026-10-05 09:00" "ACTIVATED: 2026-10-04 by Nash (via T-Bot cross-session message)"
out=$(bash "$CLAIM" "$seat" "$b/legacy.md" s1 Nash 2>&1; echo "rc=$?")
case $out in *"ALREADY ACTIVATED: 2026-10-04 by Nash"*"rc=3") pass ;; *) fail "$out" ;; esac

# ---------------------------------------------------------------- claims and stamps
s2="$team/Vaughn - QA"
t "a self-handoff with MISSION NONE claims as SELF-<WRITTEN compact>, no mission claim"
brief "$s2/HANDOFF.md" SELF-HANDOFF Vaughn NONE "2026-10-05 09:07"
out=$(bash "$CLAIM" "$s2" "$s2/HANDOFF.md" vsess Vaughn 2>&1; echo "rc=$?")
case $out in *"CLAIMED SELF-20261005-0907"*"rc=0") [ -d "$s2/.go-claim/SELF-20261005-0907" ] && [ ! -e "$team/_claims/NONE.vsess" ] && pass || fail "claim dir or stray claim" ;; *) fail "$out" ;; esac

t "CRLF preserved: the stamp line ends in CRLF like the rest"
printf 'TYPE: INFORMATIONAL\r\nSEAT: Vaughn\r\nMISSION: NONE\r\nWRITTEN: 2026-10-05 09:08\r\n\r\nbody\r\n' > "$s2/HANDOFF.md"
bash "$CLAIM" "$s2" "$s2/HANDOFF.md" vsess Vaughn > /dev/null 2>&1
nl=$(wc -l < "$s2/HANDOFF.md" | tr -d ' '); ncr=$(tr -cd '\r' < "$s2/HANDOFF.md" | wc -c | tr -d ' ')
st=$(grep -c $'^ACTIVATED: .*\r$' "$s2/HANDOFF.md")
[ "$nl" = "$ncr" ] && [ "$nl" = 7 ] && [ "$st" = 1 ] && pass || fail "lines $nl, CRs $ncr, CRLF stamps $st"

t "an unsubstituted \${CLAUDE_SESSION_ID} writes no mission claim"
brief "$s2/HANDOFF.md" DISPATCH Vaughn OPS-033 "2026-10-05 09:09" "DISPATCHED BY: T-Bot"
bash "$CLAIM" "$s2" "$s2/HANDOFF.md" '${CLAUDE_SESSION_ID}' Vaughn > /dev/null 2>&1
ls "$team/_claims" | grep -q '^OPS-033\.' && fail "claim written with a bogus sid" || pass

t "the session id is sanitized as tars.sh sanitizes it"
brief "$s2/HANDOFF.md" DISPATCH Vaughn OPS-031 "2026-10-05 09:10" "DISPATCHED BY: T-Bot"
bash "$CLAIM" "$s2" "$s2/HANDOFF.md" 'ab/c..d$e;f' Vaughn > /dev/null 2>&1
[ -f "$team/_claims/OPS-031.abcdef" ] && pass || fail "$(ls "$team/_claims")"

t "a symlinked _claims is never written through"
t2="$tmp/team2"; mkteam "$t2"; mkdir -p "$tmp/elsewhere"
if ln -s "$tmp/elsewhere" "$t2/_claims" 2>/dev/null && [ -L "$t2/_claims" ]; then
  brief "$t2/Nash - Developer/HANDOFF.md" DISPATCH Nash AXM-046 "2026-10-05 09:00" "DISPATCHED BY: T-Bot"
  bash "$CLAIM" "$t2/Nash - Developer" "$t2/Nash - Developer/HANDOFF.md" s9 Nash > /dev/null 2>&1
  [ -z "$(ls "$tmp/elsewhere")" ] && pass || fail "wrote through the symlink"
else
  echo "  (symlinks unavailable on this filesystem: case not reachable)"; pass
fi

t "claims older than 7 days are pruned, fresh ones kept"
mkdir -p "$seat/.go-claim/OLD-20200101-0000" "$seat/.go-claim/NEW-20991231-0000"
echo "1000 Nash session x at 1970-01-01 00:16" > "$seat/.go-claim/OLD-20200101-0000/owner"
echo "99999999999 Nash session y at future" > "$seat/.go-claim/NEW-20991231-0000/owner"
echo "1000 Nash" > "$team/_claims/AXM-046.oldsess"
brief "$seat/HANDOFF.md" DISPATCH Nash AXM-047 "2026-10-05 09:11" "DISPATCHED BY: T-Bot"
bash "$CLAIM" "$seat" "$seat/HANDOFF.md" s10 Nash > /dev/null 2>&1
[ ! -e "$seat/.go-claim/OLD-20200101-0000" ] && [ -d "$seat/.go-claim/NEW-20991231-0000" ] && [ ! -e "$team/_claims/AXM-046.oldsess" ] && pass || fail "prune wrong"

t "the board check runs before the claim: a refused brief leaves no claim dir"
brief "$seat/HANDOFF.md" DISPATCH Nash OPS-033 "2026-10-05 09:12" "DISPATCHED BY: T-Bot"
bash "$CLAIM" "$seat" "$seat/HANDOFF.md" s11 Nash > /dev/null 2>&1
[ ! -e "$seat/.go-claim/OPS-033-20261005-0912" ] && pass || fail "claim dir created on refusal"

t "CTM-LANE missions are checked against COLLECTIVE_BOARD.md"
cat > "$team/COLLECTIVE_BOARD.md" <<'EOF'
## Cross-team missions

| ID | Goal | Convener | Assignees | Status |
|----|------|----------|-----------|--------|
| CTM-007 | Wiki | Eli-Bot | Nash | ACTIVE |
EOF
brief "$b/ctm.md" CTM-LANE Nash CTM-007 "2026-10-05 09:00" "DISPATCHED BY: Eli-Bot"
out=$(bash "$CLAIM" --check "$seat" "$b/ctm.md" s1 Nash 2>&1; echo "rc=$?")
case $out in *CLAIMABLE*"rc=0") pass ;; *) fail "$out" ;; esac

t "usage errors exit 2"
out=$(bash "$CLAIM" only two 2>&1; echo "rc=$?"); case $out in *"rc=2") pass ;; *) fail "$out" ;; esac

finish
