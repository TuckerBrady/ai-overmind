#!/usr/bin/env bash
# A-36: the spin-up brief. brief.sh checks a fold file's "Needs you" (at most
# 2, ranked) and "Also open (n)" (everything else, nothing dropped), and
# SKILL.md must carry every rule of the brief.
set -u
here=$(cd "$(dirname "$0")" && pwd); repo=${here%/tests/l6}
ok=0; no=0; name=""
t() { name=$1; }
pass() { ok=$((ok+1)); }
fail() { no=$((no+1)); echo "  FAIL: $name: $1"; }
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ovm.XXXXXX"); trap 'rm -rf "$tmp"' EXIT
brief="$repo/skills/consolidate/brief.sh"
inv="$repo/skills/consolidate/invariant.sh"
skill="$repo/skills/consolidate/SKILL.md"
SB=${BASH:-bash}
uuid() { printf '%08x-0000-4000-8000-%012x' "$1" "$1"; }

# The 7-item fixture: 2 blocking questions, 1 conflict (a pair), 4 questions.
# $1 = Needs you rows, $2 = Also open header count, $3 = Also open rows
fold() {
  cat <<EOF
# CONSOLIDATE AXM-046 20261005-0900
ANCHOR: AXM-046 (consolidated 20261005-0900) (f8d87694)

## Siblings
| Session | Class | Fork point | Mode | Result |
|---|---|---|---|---|
| 1589a98d | DIVERGED | $(uuid 1) | Read | folded: 2 decisions, 0 files |

## Inventory in
| Item | Kind | Source | Timestamp | Text |
|---|---|---|---|---|
| 1589a98d-D1 | DECISION | user:$(uuid 2) | 2026-10-01T10:00:00Z | Checkpoints every third level |
| anchor-D1 | DECISION | user:$(uuid 3) | 2026-10-03T10:00:00Z | Checkpoints every second level |
| 1589a98d-Q1 | QUESTION | assistant:$(uuid 4) | 2026-10-01T11:00:00Z | Ship the engine PR before the level PR? |
| 1589a98d-Q2 | QUESTION | assistant:$(uuid 5) | 2026-10-01T12:00:00Z | Which tray size for K1-7? |
| 1589a98d-Q3 | QUESTION | assistant:$(uuid 6) | 2026-10-01T13:00:00Z | Name for the repair arc? |
| 1589a98d-Q4 | QUESTION | assistant:$(uuid 7) | 2026-10-01T14:00:00Z | Codex entry tone? |
| 1589a98d-Q5 | QUESTION | assistant:$(uuid 8) | 2026-10-01T15:00:00Z | Music cue for the reveal? |
| 1589a98d-Q6 | QUESTION | assistant:$(uuid 9) | 2026-10-01T16:00:00Z | Keep the old K1-3 layout? |

## Merged record
| Item | Kind | Status | Text |
|---|---|---|---|
| 1589a98d-D1 | DECISION | CONFLICT anchor-D1 | Checkpoints every third level |
| anchor-D1 | DECISION | CONFLICT 1589a98d-D1 | Checkpoints every second level |
| 1589a98d-Q1 | QUESTION | CURRENT | Ship the engine PR before the level PR? |
| 1589a98d-Q2 | QUESTION | CURRENT | Which tray size for K1-7? |
| 1589a98d-Q3 | QUESTION | CURRENT | Name for the repair arc? |
| 1589a98d-Q4 | QUESTION | CURRENT | Codex entry tone? |
| 1589a98d-Q5 | QUESTION | CURRENT | Music cue for the reveal? |
| 1589a98d-Q6 | QUESTION | CURRENT | Keep the old K1-3 layout? |

## Conflicts
- 1589a98d-D1 vs anchor-D1: checkpoint cadence.

## Needs you
| Item | Rank | Text |
|---|---|---|
$1

## Also open ($2)
| Item | Rank | Text |
|---|---|---|
$3

## Unknown tags
none

## Close
EOF
}
NEED='| 1589a98d-Q1 | BLOCKING | Engine PR first? Nash is waiting on it. |
| 1589a98d-Q2 | BLOCKING | Tray size for K1-7; the level build is stopped. |'
ALSO='| 1589a98d-D1+anchor-D1 | CONFLICT | Checkpoint cadence: every third or every second level? |
| 1589a98d-Q3 | QUESTION | Name for the repair arc? |
| 1589a98d-Q4 | QUESTION | Codex entry tone? |
| 1589a98d-Q5 | QUESTION | Music cue for the reveal? |
| 1589a98d-Q6 | QUESTION | Keep the old K1-3 layout? |'

check() { local o; o=$("$SB" "$brief" "$1" 2>&1); echo "$?|$o"; }

fold "$NEED" 5 "$ALSO" > "$tmp/good.md"
t "the 7-item fixture: the 2 blocking items selected, the other 5 under Also open -> 0"
r=$(check "$tmp/good.md")
case $r in "0|brief: ok (needs you 2, also open 5)") pass ;; *) fail "$r" ;; esac
t "the fixture is also a valid fold (invariant.sh)"
"$SB" "$inv" "$tmp/good.md" > /dev/null 2>&1 && pass || fail "$("$SB" "$inv" "$tmp/good.md" 2>&1)"
t "CRLF fold passes too"
sed 's/$/\r/' "$tmp/good.md" > "$tmp/crlf.md"
r=$(check "$tmp/crlf.md"); case $r in "0|"*) pass ;; *) fail "$r" ;; esac

t "3 items in Needs you -> 1"
fold "$NEED
| 1589a98d-Q3 | QUESTION | Name for the repair arc? |" 4 "$(printf '%s\n' "$ALSO" | LC_ALL=C grep -v 'Q3 ')" > "$tmp/b1.md"
r=$(check "$tmp/b1.md"); case $r in "1|"*"Needs you has 3 items; at most 2"*) pass ;; *) fail "$r" ;; esac
t "a QUESTION selected while a BLOCKING item waits in Also open -> 1"
fold '| 1589a98d-Q1 | BLOCKING | Engine PR first? |
| 1589a98d-Q3 | QUESTION | Name for the repair arc? |' 5 "$(printf '%s\n' "$ALSO" | LC_ALL=C grep -v 'Q3 ')
| 1589a98d-Q2 | BLOCKING | Tray size for K1-7. |" > "$tmp/b2.md"
r=$(check "$tmp/b2.md"); case $r in "1|"*"Also open item 1589a98d-Q2 outranks Needs you item 1589a98d-Q3"*) pass ;; *) fail "$r" ;; esac
t "a conflict selected over a BLOCKING item -> 1"
fold '| 1589a98d-D1+anchor-D1 | CONFLICT | cadence |
| 1589a98d-Q1 | BLOCKING | Engine PR first? |' 5 "$(printf '%s\n' "$ALSO" | LC_ALL=C grep -v 'CONFLICT')
| 1589a98d-Q2 | BLOCKING | Tray size for K1-7. |" > "$tmp/b3.md"
r=$(check "$tmp/b3.md"); case $r in "1|"*"outranks"*) pass ;; *) fail "$r" ;; esac
t "an open question dropped from both lists -> 1"
fold "$NEED" 4 "$(printf '%s\n' "$ALSO" | LC_ALL=C grep -v 'Q6 ')" > "$tmp/b4.md"
r=$(check "$tmp/b4.md"); case $r in "1|"*"dropped: 1589a98d-Q6"*) pass ;; *) fail "$r" ;; esac
t "the CONFLICT dropped from both lists -> 1"
fold "$NEED" 4 "$(printf '%s\n' "$ALSO" | LC_ALL=C grep -v 'CONFLICT')" > "$tmp/b5.md"
r=$(check "$tmp/b5.md"); case $r in "1|"*"dropped: 1589a98d-D1"*"dropped: anchor-D1"*|"1|"*"dropped: anchor-D1"*"dropped: 1589a98d-D1"*) pass ;; *) fail "$r" ;; esac
t "the Also open header count is wrong -> 1"
fold "$NEED" 4 "$ALSO" > "$tmp/b6.md"
r=$(check "$tmp/b6.md"); case $r in "1|"*"Also open header says (4) but lists 5"*) pass ;; *) fail "$r" ;; esac
t "Needs you has room while Also open is not empty -> 1"
fold '| 1589a98d-Q1 | BLOCKING | Engine PR first? |' 6 "$ALSO
| 1589a98d-Q2 | BLOCKING | Tray size. |" > "$tmp/b7.md"
r=$(check "$tmp/b7.md"); case $r in "1|"*"Needs you has room"*) pass ;; *) fail "$r" ;; esac
t "an item listed twice -> 1"
fold "$NEED" 6 "$ALSO
| 1589a98d-Q1 | QUESTION | again |" > "$tmp/b8.md"
r=$(check "$tmp/b8.md"); case $r in "1|"*"listed twice: 1589a98d-Q1"*) pass ;; *) fail "$r" ;; esac
t "a CONFLICT ranked below CONFLICT -> 1"
fold "$NEED" 5 "$(printf '%s\n' "$ALSO" | sed 's/| CONFLICT | Checkpoint/| PROMISE | Checkpoint/')" > "$tmp/b9.md"
r=$(check "$tmp/b9.md"); case $r in "1|"*"ranked PROMISE, below CONFLICT"*) pass ;; *) fail "$r" ;; esac
t "an unknown rank -> 1"
fold "$NEED" 5 "$(printf '%s\n' "$ALSO" | sed 's/| QUESTION | Codex/| URGENT | Codex/')" > "$tmp/b10.md"
r=$(check "$tmp/b10.md"); case $r in "1|"*"unknown rank \"URGENT\""*) pass ;; *) fail "$r" ;; esac
t "no Needs you section -> 1; a missing file -> 2"
LC_ALL=C grep -v '^## Needs you' "$tmp/good.md" > "$tmp/b11.md"
r=$(check "$tmp/b11.md"); "$SB" "$brief" "$tmp/none.md" > /dev/null 2>&1; m=$?
case $r in "1|"*"no ## Needs you section"*) [ "$m" = 2 ] && pass || fail "missing file rc=$m" ;; *) fail "$r" ;; esac
t "an empty Needs you with nothing open passes"
cat > "$tmp/e.md" <<EOF
# CONSOLIDATE AXM-1 20261005-0900
ANCHOR: x (aaaaaaaa)
## Siblings
| Session | Class | Fork point | Mode | Result |
|---|---|---|---|---|
## Inventory in
| Item | Kind | Source | Timestamp | Text |
|---|---|---|---|---|
## Merged record
| Item | Kind | Status | Text |
|---|---|---|---|
## Conflicts
## Needs you
| Item | Rank | Text |
|---|---|---|
## Also open (0)
| Item | Rank | Text |
|---|---|---|
## Unknown tags
none
## Close
EOF
r=$(check "$tmp/e.md"); case $r in "0|"*) pass ;; *) fail "$r" ;; esac

# --- SKILL.md carries every rule of the brief ---------------------------------------
sk=$(tr -d '\r' < "$skill" | tr '\n' ' ' | tr -s ' ')   # one line, single spaces: phrases may wrap
has() { printf '%s\n' "$sk" | LC_ALL=C grep -qF -- "$1"; }
t "SKILL: the TLDR comes first, 2 to 4 plain sentences, with how long since it was worked"
has "TLDR" && has "2 to 4 plain sentences" && has "last worked" && has "No tables, no session ids, no file paths" && pass || fail "TLDR rules missing"
t "SKILL: Needs you is at most 2, ranked in the A-36 order"
has "at most 2" && printf '%s\n' "$sk" | LC_ALL=C grep -q 'BLOCKING.*DEADLINE.*CONFLICT.*QUESTION.*PROMISE' && has "Also open (n)" && pass || fail "ranking rules missing"
t "SKILL: decisions and questions go through AskUserQuestion with a Recommended option"
has "AskUserQuestion" && has "(Recommended)" && has "2 to 4" && has '"Other"' && has "single AskUserQuestion call" && pass || fail "question rules missing"
t "SKILL: the close is one AskUserQuestion question with the three options"
has "Close all N (Recommended)" && has "Let me pick which" && has "Keep them open" && has "multiSelect" && has "The tool answer IS that yes" && pass || fail "close rules missing"
t "SKILL: the 12-line budget, and the record stays in the file"
has "at most 12 lines" && has "never pasted into chat" && pass || fail "budget missing"
t "SKILL: then continue the mission and record the answers as DECISION items"
has "continue the mission" && has "in their own words" && pass || fail "then-go rule missing"
t "SKILL (A-42): the Close all option lists the plain title of every session that will close"
has "lists the plain title of every session that will close, side sessions included" && pass || fail "close-all titles rule missing"
t "SKILL (A-40): widget answers are DECISION sources as answer:<uuid>"
has 'answer:<uuid>' && has "AskUserQuestion widget" && pass || fail "answer source rule missing"
t "SKILL (A-41): unknown-tag rows go to ## Unknown tags and are asked as questions"
has "## Unknown tags" && has "never a DECISION source" && pass || fail "unknown-tag rule missing"
t "SKILL (A-39): the guard fails closed and says so"
has "fails closed" && has "core.worktree" && has "never touches the network" && pass || fail "fail-closed description missing"
t "SKILL (A-46 N6): more than 3 siblings split across questions or use a typed list"
has "with more than 3 siblings, split them across two multiSelect questions" && pass || fail "N6 rule missing"
t "SKILL (A-46 B2): decision words come from answer rows, copied into ## Answers"
has "Never take decision words from an \`asked\` row" && has "## Answers" && pass || fail "answer-field rule missing"
t "SKILL: brief.sh runs, and the close waits on it"
has "bash brief.sh" && pass || fail "brief.sh not run"

echo "$([ $no -eq 0 ] && echo PASS || echo FAIL) ${0##*/} ($((ok+no)) cases)"; [ $no -eq 0 ]
