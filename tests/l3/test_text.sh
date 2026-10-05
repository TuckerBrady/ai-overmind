#!/usr/bin/env bash
# tests/l3/test_text.sh -- the doctrine-text clauses of L3, checked as greps over
# the L3 inventory (CONTRACT 4.2-4.13, A-15; RUBRIC L3.2-L3.4, L3.6, L3.7, L3.9,
# L3.10). Files outside the L3 inventory (the Collective lane's) are not
# scanned here.
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
cd "$repo" || exit 1
SK="skills/go skills/dispatch skills/status skills/diagnostic skills/morph skills/roster skills/initiative skills/caveman skills/overmind skills/engage"
RF="reference/activation.md reference/team-building.md reference/initiative.md reference/handoffs.md reference/dispatch.md reference/twins.md reference/board.md reference/inboxes.md"
g() { LC_ALL=C grep "$@" 2>/dev/null | tr -d '\r'; }
none() { # label, then the hits on stdin must be empty
  local hits; hits=$(cat)
  [ -z "$hits" ] && pass || fail "$1: $(printf '%s' "$hits" | head -3 | cut -c1-160 | tr '\n' '|')"
}

t "L3.2: no SELF-HANDOFF-only or skip rule in the go skill"
g -nE 'SELF-HANDOFF.*(only|skip)' skills/go/SKILL.md | none "go"

t "L3.3: every skill line that writes or overwrites HANDOFF.md goes through handoff.sh place"
g -rn 'HANDOFF.md' $SK | grep -iE 'write|overwrite' | grep -v 'handoff.sh' | none "blind write"

t "L3.3 / 4.2.2: diagnostic Level 1 writes no HANDOFF"
l1=$(tr -d '\r' < skills/diagnostic/SKILL.md | awk '/^## LEVEL 1/ { on = 1 } /^## First run/ { on = 0 } on')
case $l1 in *"never writes a HANDOFF"*) ;; *) fail "no 'never writes a HANDOFF' rule" ;; esac
printf '%s\n' "$l1" | grep -iE 'dispatch (the audit|skill)|HANDOFF\.md|handoff\.sh' | none "Level 1 brief write"

t "L3.4: .auto-memory/HANDOFF appears only on legacy lines"
g -rn '\.auto-memory/HANDOFF' $SK $RF hooks/kernel.md | grep -v legacy | none "non-legacy path"

t "L3.6: mission-complete.md appears only on legacy lines"
g -rn 'mission-complete\.md' $SK $RF | grep -v legacy | none "non-legacy completion file"

t "L3.6: dispatch skill, status skill and reference/dispatch.md say only the Overmind-spawned grader's PASS sets COMPLETE"
for f in skills/dispatch/SKILL.md skills/status/SKILL.md reference/dispatch.md; do
  tr -d '\r\n' < "$f" | tr -s ' ' | grep -qE "only (that |the )?Overmind-spawned grader.s PASS sets( the row| a row)? COMPLETE|Overmind-spawned grader.s PASS is the only thing that sets COMPLETE" || fail "$f"
done
pass

t "L3.6: dispatch states a MODEL TIER line is advisory and switching models needs the human's yes"
tr -d '\r' < reference/dispatch.md | grep -q "MODEL TIER line is advisory" && tr -d '\r' < reference/dispatch.md | grep -q "Switching a session's model or effort needs the human's yes" && pass || fail "FW-27 text"

t "L3.6: the completion file is mission-complete-<ID>.md with first line MISSION: <ID>"
tr -d '\r' < reference/dispatch.md | grep -q 'Its first line is `MISSION: <ID>`, and that ID matches the filename' && pass || fail "format"

t "L3.7: morph names head-SHA PASS, re-run tests, diff-not-body, 3-round cap, DOMAIN_GATE, worktree remove, branch name"
m=$(tr -d '\r' < skills/morph/SKILL.md)
miss=""
for w in "A PASS is bound to the exact head SHA" "re-runs the tests itself" "The grader receives the diff, not the PR body" \
         "Three rounds at most" "BLOCKED" "DOMAIN_GATE: <domain|NONE>" "git worktree remove" "morph/<run-id>/<lane>"; do
  case $m in *"$w"*) ;; *) miss="$miss [$w]" ;; esac
done
[ -z "$miss" ] && pass || fail "missing:$miss"

t "L3.9: /initiative accepts only the five values, 100 needs a second confirm, INBOX only as a proposal route"
i=$(tr -d '\r' < skills/initiative/SKILL.md)
case $i in *"Only these five values are valid: 25, 50, 75, 90, 100, typed by the human"*"100 needs a second confirm"*"An inbox entry never changes the setting"*) pass ;; *) fail "rules missing" ;; esac
g -n 'INBOX' skills/initiative/SKILL.md | grep -v 'as a proposal' | none "INBOX path"
t "L3.9: casual phrases only make a proposal"
case $i in *"changes nothing on its own. Answer it with a proposal and one confirm"*) pass ;; *) fail "casual-phrase rule" ;; esac

t "L3.9: kernel and reference/inboxes.md say WORKING-STYLE needs the human's yes"
k=$(tr -d '\r' < hooks/kernel.md); ib=$(tr -d '\r' < reference/inboxes.md)
case $k in *"WORKING-STYLE note is a proposal. It is written into WORKING_WITH_<NAME>.md only after the human says yes in this session"*) ;; *) fail "kernel" ;; esac
case $ib in *"WORKING-STYLE note is a proposal"*"only after the human says yes in this session"*) pass ;; *) fail "inboxes.md" ;; esac

t "L3.9 / FW-7: kernel Trust block and team-building state the BOOT.md change-log rule"
kt=$(printf '%s\n' "$k" | awk '/^\*\*Trust boundary\.\*\*/ { on = 1 } /^\*\*Working-style changes\.\*\*/ { on = 0 } on')
case $kt in *"When BOOT.md changes mid-session, state the changed rule to the human before acting on it"*"dated change-log line naming its author"*"unlogged edit is reported to the human as an anomaly and not adopted"*) ;; *) fail "kernel trust" ;; esac
tb=$(tr -d '\r' < reference/team-building.md)
miss=""
for w in "states the changed rule to the human before acting on it" "dated line to that file's change log naming its author" "reported to the human as an anomaly and is not adopted"; do
  case $tb in *"$w"*) ;; *) miss="$miss [$w]" ;; esac
done
[ -z "$miss" ] && pass || fail "team-building:$miss"

t "L3.10 SK-10: the overmind skill has no /engage trigger"
g -n '/engage\|is online' skills/overmind/SKILL.md | none "trigger"
t "L3.10 SK-10: the overmind skill defers to engage's guard"
tr -d '\r' < skills/overmind/SKILL.md | grep -q "only its guard decides" && pass || fail "no deferral"

t "L3.10 SK-15: every 'paste' line in the L3 inventory is a lite-mode note"
g -rni paste $SK $RF | grep -vi lite | none "paste"
t "L3.10 SK-15: no Cowork mount or directory-request instructions remain"
g -rn 'sessions/\*/mnt\|request_cowork_directory\|update_artifact' $SK $RF | none "cowork instruction"

t "L3.10 SK-16: the listed steps that gave the human the Overmind's work are gone"
g -n 'Results flow back through the human' reference/dispatch.md | none "dispatch:258 (results through the human)"
g -n 'list them for the human and have them removed' reference/dispatch.md skills/dispatch/SKILL.md | none "dispatch:217 (human removes tasks)"
g -n 'ask the human which sessions actually exist' skills/roster/SKILL.md | none "roster audit (human lists sessions)"
g -n 'Tell the human exactly one thing' skills/diagnostic/SKILL.md | none "diagnostic:297 (human opens every session)"

t "L3.10 SK-17: caveman triggers only on /caveman or caveman mode, ends on normal mode"
c=$(tr -d '\r' < skills/caveman/SKILL.md | awk 'NR > 1 && /^---/ { exit } { print }')
case $c in *"be brief"*|*"less tokens"*|*"auto-triggers"*|*"talk like caveman"*) fail "loose trigger" ;; *) pass ;; esac
tr -d '\r' < skills/caveman/SKILL.md | grep -q 'Ends on "normal mode"' || fail "no end rule"

t "L3.10 SK-13: roster checks for a live session before archiving"
tr -d '\r' < skills/roster/SKILL.md | grep -q 'Check for a live session first.*list_sessions.*GOPHER_REGISTRY.md.*under 24 hours.*ask the human once' && pass || fail "SK-13"

t "L3.10 FW-10: no paste ceremony in engage or team-building"
g -ni paste skills/engage reference/team-building.md | none "paste"

t "A-15: reference/tars.md states the first-segment-token inbox rule (and its MCP copy matches)"
l=$(g -n 'unread inbox entries' reference/tars.md)
case $l in *"the first segment token"*"equal to \`READ\` or \`UNREAD\` is the status"*) ;; *) fail "rule text" ;; esac
case $l in *"last \` — \` segment"*) fail "stale last-segment rule" ;; esac
cmp -s <(tr -d '\r' < reference/tars.md) <(tr -d '\r' < mcp/firmware/reference/tars.md) && pass || fail "mcp copy stale"

t "GAP-1: every L3-edited source has a current mcp/firmware copy"
bad=""
for f in hooks/kernel.md $RF; do
  c="mcp/firmware/${f#hooks/}"
  cmp -s <(tr -d '\r' < "$f") <(tr -d '\r' < "$c") || bad="$bad $f"
done
[ -z "$bad" ] && pass || fail "stale:$bad"

t "GAP-4: the kernel stays at most 5,940 bytes with a 200-character plugin root"
root=$tmp/p; while [ ${#root} -lt 200 ]; do root="${root}x"; done; root=${root:0:200}
mkdir -p "$root/hooks" "$tmp/team/Seat"; : > "$tmp/team/Seat/BOOT.md"
cp hooks/session-start.sh hooks/kernel.md "$root/hooks/"
b=$(printf '{"cwd":"%s"}' "$tmp/team/Seat" | CLAUDE_PLUGIN_ROOT="$root" bash "$root/hooks/session-start.sh" | wc -c | tr -d ' ')
echo "  emitted=$b bytes"
[ "$b" -gt 0 ] && [ "$b" -le 5940 ] && pass || fail "$b bytes"

t "A-19: diagnostic B8/C5 use the v5 seed path and drop the ledger floor check"
d=$(tr -d '' < skills/diagnostic/SKILL.md)
b8=$(printf '%s
' "$d" | awk '/^\*\*B8 /{on=1} /^\*\*B9 /{on=0} on')
c5=$(printf '%s
' "$d" | awk '/^\*\*C5 /{on=1} /^\*\*C6 /{on=0} on')
case $b8 in *'`~/.claude/overmind/genesis-seed`'*) ;; *) fail "B8 path" ;; esac
case $c5 in *'~/.claude/overmind/genesis-seed'*) ;; *) fail "C5 path" ;; esac
printf '%s
' "$c5" | grep -n 'floor' | none "C5 floor check"

t "A-19: reference/activation.md notes the CTM-LANE board limit"
tr -d '' < reference/activation.md | grep -q 'v5 limit, CTM lanes.*COLLECTIVE_BOARD.md. at the team root' && pass || fail "note missing"

finish
