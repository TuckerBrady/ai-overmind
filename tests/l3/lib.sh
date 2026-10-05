# tests/l3/lib.sh -- shared helpers for the L3 tests (lane-local; TEST_STRATEGY 1, 2).
# Source it after setting $here. Provides: repo, tmp (removed on exit), t/pass/fail,
# finish, and fixture builders for a team with a board.
set -u
repo=${here%/tests/l3}
ok=0; no=0; name=""
t() { name=$1; }
pass() { ok=$((ok+1)); }
fail() { no=$((no+1)); echo "  FAIL: $name: $1"; }
finish() { echo "$([ $no -eq 0 ] && echo PASS || echo FAIL) ${0##*/} ($((ok+no)) cases)"; [ $no -eq 0 ]; }
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ovm.XXXXXX"); trap 'rm -rf "$tmp"' EXIT
CLAIM="$repo/skills/go/claim.sh"
PLACE="$repo/skills/go/handoff.sh"
ALLOC="$repo/skills/dispatch/alloc-id.sh"
GUARD="$repo/hooks/twin-guard.sh"

# mkteam DIR: a team root with a board shaped like the live team's (Owner and
# singular Assignee columns, an Archive table with a Formerly column).
mkteam() {
  local r=$1
  mkdir -p "$r/Nash - Developer" "$r/Vaughn - QA" "$r/T-Bot - The Overmind"
  : > "$r/Nash - Developer/BOOT.md"; : > "$r/Vaughn - QA/BOOT.md"
  cat > "$r/MISSION_BOARD.md" <<'EOF'
# MISSION BOARD

## How this board works

| ID | Meaning |
|----|---------|
| AXM-001 | an example row outside the tables that count |

## Active

| ID | Mission | Owner | Assignee | Status | Priority | Blocker | Last Touched |
|----|---------|-------|----------|--------|----------|---------|--------------|
| AXM-046 | Level deep dive | T-Bot | Nash | ACTIVE | HIGH | | 2026-10-05 |
| AXM-047 | Queued work, COMPLETE in its title | T-Bot | Nash | QUEUED | STANDARD | | 2026-10-05 |
| OPS-030 | Owner-held mission | T-Bot | T-Bot | ACTIVE | HIGH | | 2026-10-05 |
| OPS-031 | Multi-lane | T-Bot | Nash, Vaughn | nash: COMPLETE / vaughn: ACTIVE | STANDARD | | 2026-10-05 |
| OPS-032 | Done row | T-Bot | Nash | COMPLETE | STANDARD | | 2026-10-05 |
| OPS-033 | Someone else's | T-Bot | Vaughn | ACTIVE | STANDARD | | 2026-10-05 |
| OPS-041 | Highest active OPS | T-Bot | Nash | BLOCKED | LOW | | 2026-10-05 |

## Archive

| ID | Formerly | Mission | Assignee | Status | Completed |
|----|----------|---------|----------|--------|-----------|
| AXM-010 | M-010 | Old work | Nash | COMPLETE | 2026-08-01 |
| OPS-057 | M-057 | Highest archived OPS | Nash | COMPLETE | 2026-09-01 |
EOF
}

# brief FILE TYPE SEAT MISSION WRITTEN [extra header line]: a v5 brief.
brief() {
  local f=$1
  {
    printf '**SESSION TITLE**\n\n```\n%s — test\n```\n\nSESSION HANDOFF\n\n' "$4"
    printf 'TYPE: %s\nSEAT: %s\nMISSION: %s\nWRITTEN: %s\n' "$2" "$3" "$4" "$5"
    [ -n "${6:-}" ] && printf '%s\n' "$6"
    printf '\n## NEXT STEPS (Priority Order)\n\n1. Do the thing.\n'
  } > "$f"
}

# count_lines FILE PREFIX: lines of FILE that start with PREFIX.
count_lines() { tr -d '\r' < "$1" | grep -c "^$2" ; }
