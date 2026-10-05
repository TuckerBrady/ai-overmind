---
name: dispatch
description: >
  Dispatch a task to one or more specialist AI sessions as a mission with lanes.
  Use when the human describes work for a team member, says "send this to...", "triage this to...",
  "dispatch to...", "brief [name]", "spin up [name] for...", or describes a task that maps to a
  domain expert on the team roster. Also use when the human says "I need [name] to handle X"
  or "get [name] working on Y".
  Output: HANDOFF.md written to each specialist's folder, one mission row on the board, and a
  single instruction for the human: open each session and type /go. No passphrase to relay —
  dispatched missions activate on the go command.
---

# Dispatch — Team Mission Deployment

This skill is available to any session on the team — the Overmind or a specialist. Any team member can invoke it to brief another specialist. The Overmind remains the default dispatcher for human-initiated tasks; specialists use it for lateral handoffs when work crosses domain boundaries mid-session.

**The procedure lives in one place: `../../reference/dispatch.md`.** Read it now and follow it step by step. This skill does not restate it, so the two can never disagree. Board format, statuses and priority tiers are in `../../reference/board.md`; model tiers are in `../../reference/twins.md`.

**Is this actually a dispatch?** A quick, bounded task in a specialist's domain that fits inside the current session is a splinter twin (`../../reference/twins.md`). Information a peer should know, with no work attached, is an inbox note (`../../reference/inboxes.md`). Dispatch is for real missions: deliverables, session state, follow-up.

## The steps, by name

Each one is written out in `../../reference/dispatch.md`:

1. **Understand the task** — mission, context, inputs, deliverables, dependencies, priority and deadline, a done-when rubric of 5 to 10 checkable criteria, and the model tier.
2. **Find the specialist's folder** — from `TEAM_ROSTER.md`, the roster of record. Never dispatch to a name that isn't in its Active table.
3. **Assign the mission ID and lanes** — one ID per goal, one lane per specialist. Allocate the ID through the team's board script when `[team-root]/_Team/team.py` exists; otherwise with `alloc-id.sh` in this skill's folder (`bash "${CLAUDE_SKILL_DIR}/alloc-id.sh" "[team-root]" PREFIX`), which claims the number atomically. Activation is `/go`; no passphrase is generated, ever.
4. **Place the brief with `handoff.sh place`** (`bash "${CLAUDE_PLUGIN_ROOT}/skills/go/handoff.sh" place "[specialist-folder]" "[draft file]"`), in the exact format in the reference file, so an unactivated brief already there is superseded, never overwritten. Then **add one row to the board** (status QUEUED for each lane, every lane's seat in Assignees).
5. **TARS watches the mission** — nothing to launch, and never a scheduled task.
6. **Report back** with the human scoreboard and one instruction: open the session and type `/go`.

**Completion is graded, not declared.** The specialist writes `mission-complete-<ID>.md` (first line `MISSION: <ID>`). Its own PASS is a claim. The Overmind spawns a fresh grader twin with the rubric and the deliverable paths only, and only that Overmind-spawned grader's PASS sets the row COMPLETE (OUTCOMES in `../../reference/dispatch.md`). A brief's MODEL TIER line is advisory; switching models needs the human's yes.
