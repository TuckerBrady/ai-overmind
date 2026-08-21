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

This skill is available to any session on the team — the Overmind or a specialist. Any team member can invoke it to brief another specialist. The format, lane mechanics, and HANDOFF.md structure are identical regardless of who is dispatching. The Overmind remains the default dispatcher for human-initiated tasks; specialists use this for lateral handoffs when work crosses domain boundaries mid-session (e.g., Alex briefing Drew on a requirements gap, or Cade flagging Argus on a safety concern).

The dispatcher writes a mission brief (HANDOFF.md) to the receiving specialist's folder and stakes the mission on the board. Activation is `/go` — the human opens the specialist's session and types it; the specialist reads the brief and goes to work fully briefed. Nothing to remember, nothing to relay.

**Is this actually a dispatch?** Two lighter tools exist — use them when they fit:
- Quick, bounded task in a specialist's domain that fits inside the current session → spawn the `splinter-twin` agent instead (see the firmware's SPLINTER TWINS section). No brief, no board row, no new session.
- Just information a peer should know, no work required → append a note to their `[folder]/INBOX.md` instead (see the firmware's INBOXES section).

Dispatch is for real missions: deliverables, session state, follow-up.

## Specialist Roster

**The roster of record is `TEAM_ROSTER.md` at the team root — read it before dispatching.** Never dispatch to a name that isn't in its Active table; if the domain has no active specialist, tell the human and offer to handle it directly or add/resurrect the specialist via the roster skill (`skills/roster/SKILL.md`).

The table below is the default team template, kept as a reference for domains and folder naming:

| Name | Role | Folder | Domain |
|------|------|--------|--------|
| Alex | Product Owner | `Product Owner/` | Jira backlog, RICE scoring, requirements, user stories |
| Sam | Executive Assistant | `Executive Assistant/` | Calendar, email, meeting prep, deadlines, logistics |
| Drew | System Engineer | `System Engineer/` | Requirements, PAT reviews, architecture docs, safety |
| Cade | Embedded Dev | `Embedded Dev/` | Firmware, MISRA C++, DDS/JAUS, hardware config |
| Owen | Mobius Dev | `Mobius Dev/` | C# autonomy platform, CI/CD, JAUS command flow |
| Finn | Mobile Dev | `Mobile Dev/` | React/Next.js Super App, Flutter, mobile apps, Figma |
| Enzo | Electrical Engineer | `Electrical Engineer/` | Schematics, CAN/DBC, hardware, E-stop wiring |
| Ada | QA Engineer | `QA Engineer/` | Regression testing, test cycles, V-cycle validation |
| Axel | System Architect | `System Architect/` | MBSE, HARA/STPA, ADRs, ICDs, cross-subsystem architecture |
| Argus | Functional Safety | `Functional Safety/` | ISO 26262/IEC 61508, FTA/FMECA, ASIL decomposition, safety case |

## Procedure

### Step 1: Understand the task

Extract from the human's message:
- **Mission** — what needs to be done (clear, actionable)
- **Context** — why it matters, urgency, downstream impact
- **Inputs** — tickets, pages, files, people involved
- **Deliverables** — what to produce, where to save it, what "done" looks like
- **Dependencies** — who else is involved, what the Overmind handles separately
- **Priority & deadline** — CRITICAL / STANDARD / LOW plus any due date (tiers and escalation windows in the firmware's MISSION BOARD section). Default STANDARD; confirm CRITICAL with the human if you're inferring it.

If the target specialist isn't named explicitly, map the task to the right person by domain. When a task spans multiple specialists, dispatch to each with tailored briefs.

### Step 2: Find the specialist's folder

The team root is the connected folder — the same folder every project in the ecosystem connects. Check the mounts:

```bash
ls /sessions/*/mnt/
```

The specialist's folder is `[team-root]/[Specialist Folder]/`.

### Step 3: Assign the mission ID and lanes

**The mission number is the GOAL, not the assignment.** Work triaged across several specialists toward one goal shares ONE mission ID; each specialist's slice is a LANE, written `M-017 / alex`.

- Take the next sequential mission ID from `MISSION_BOARD.md`.
- **Solo dispatch** — one mission, one lane.
- **Multi-specialist dispatch toward one deliverable** — one mission ID, one lane per specialist. Each lane gets its own HANDOFF, and every HANDOFF header carries the shared MISSION ID plus its LANE.
- **Boundary test:** lanes are for work sharing a goal, not work sharing a dispatch moment. If the outputs don't combine into one deliverable or decision, they are separate missions — give each its own ID, even if you're dispatching them in the same breath.

**No passphrases.** Dispatch does not generate activation passphrases — activation for every dispatched mission is `/go` (see `skills/go/SKILL.md`). Passphrases survive in exactly one place: an agent's own session-to-session handoff, which keeps its passphrase protocol unchanged. The passphrase flavor archive lives with the handoff feature, not here.

### Step 3b: Snapshot open browser tabs

Before writing the HANDOFF, capture the current browser state so the receiving specialist can pick up exactly where this session left off.

Call `mcp__Claude_in_Chrome__tabs_context_mcp` to get all open tabs. For each tab, capture:
- Page title
- URL

If the tool returns tabs, store the list for inclusion in the HANDOFF template below. If no tabs are open or the tool is unavailable, omit the `## Restore Browser` section entirely.

### Step 4: Write HANDOFF.md

Write the file to `[team-root]/[Specialist Folder]/HANDOFF.md` — the folder root, where the specialist's Sleeper Protocol looks. Use this exact format — it matches what the specialist's Sleeper Protocol is expecting:

```
╔══════════════════════════════════════════════════════════════╗
║              CLASSIFIED — MISSION BRIEF                      ║
║              CLEARANCE: [ROLE]-LEVEL                         ║
║              ASSET: [PERSONA NAME]                           ║
╚══════════════════════════════════════════════════════════════╝

DATE DISPATCHED: [YYYY-MM-DD]
DISPATCHED BY: [Overmind Name]
MISSION ID: [M-###]  //  LANE: [M-###] / [specialist name]
PRIORITY: [CRITICAL / STANDARD / LOW]  //  DEADLINE: [YYYY-MM-DD HH:MM or "none"]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## MISSION

[2-4 sentences. Clear, actionable. No ambiguity about what needs to happen.]

## CONTEXT

[Why this matters. Background the human provided. Downstream impact.
Any relevant history from Overmind memory the specialist needs.]

## INPUTS

[Specific files, tickets, pages, prior work, people.
Be concrete — IDs, filenames, page titles, folder paths.]

## DELIVERABLES

[What to produce. Where to save it. What "done" looks like.
The specialist should know exactly when the mission is complete.]

## DEPENDENCIES

[Who else is involved. What the Overmind or the human handles separately.
Other lanes on this mission, if any, and where the slices converge.
Any blockers or things to watch for.]

---

## Restore Browser

Re-open these tabs at session start (in order):

1. [Page Title](URL)
2. [Page Title](URL)
...

---

*(Omit this section entirely if no tabs were open at dispatch time.)*

*(Note for receiving specialist: If a `## Restore Browser` section is present, navigate to each listed URL before delivering mission status.)*

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                       ⚡  ACTIVATION  ⚡
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Activation is /go. No passphrase — dispatched missions activate
on the go command.

On activation, open your first reply with:

    M-### — [short mission title]

That line names the chat at the human level. If a session-title
tool exists in your session, also set the session title to it.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            END TRANSMISSION // BURN AFTER READING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Step 4b: Add the mission to the board

**One Active row per mission**, however many lanes it has. Add a row to `[team-root]/MISSION_BOARD.md` (create it from the firmware's MISSION BOARD format if missing): the mission ID, one-line mission summary, assignee(s), priority tier, due date (or —), any Depends On mission IDs, today's date.

Per-lane state lives in the status cell — e.g. `alex: PENDING · sam: PENDING`. A mission closes when ALL lanes are done AND the dispatcher has converged the deliverable — not before. One blocked lane never hides the others: mark that lane BLOCKED in the cell and leave the rest live.

If this mission depends on one that isn't COMPLETE, set the affected lane(s) to BLOCKED and mirror the dependency in the brief's DEPENDENCIES section.

### Step 4c: Wire the watch — transport ledger or MOTHER

Check the team root for `TRANSPORT.md`. This step forks on what it finds.

**Transport bound (TRANSPORT.md exists AND its tools are available this session):**

Post one one-line TASK per lane to the team channel — mission ID + lane + one-line goal + the HANDOFF path:

```
TASK M-017 / alex — score the Q3 backlog — HANDOFF: Product Owner/HANDOFF.md
```

(One TASK naming several members with lane assignments is also fine. Every post carries the shared mission ID.) Never put a secret, token, or passphrase in a post, ever.

That is the entire watch: the channel ledger replaces file-scraping watchers. Do NOT create a scheduled watcher or poll task — check the ledger at each turn and on `/status` instead. Skip Steps 4d, 4e, and 5; they are the file-only path. (Naming note: the file-only watcher below is called MOTHER; in transport mode "MOTHER" names the membership reflex instead — the watcher is sunset wherever a ledger exists.)

**Transport absent, or its tools unavailable this session (file-only install):**

Nothing changes from the file-only flow you know. Run Steps 4d, 4e, and 5 below exactly as written.

### Step 4d: Launch MOTHER (the mission watcher) — file-only installs

MOTHER is a headless scheduled task that repaints the live mission-board artifact while work is in flight. She never speaks to the human. Create her **already enabled** — never stage a task and ask the human to switch it on.

- `taskId`: `mother-watch-[mission-id-lowercase]` (e.g. `mother-watch-m006`)
- `cronExpression` by tier: **CRITICAL `* * * * *`** (1 min) · **STANDARD `*/15 * * * *`** · **LOW `*/30 * * * *`**
- `description`: `MOTHER — watching [mission ID] ([tier])`

Her prompt must instruct her to: read the board, registry, and named deliverables in one shell call; rewrite ONLY the `const DATA = {...};` line of the `mission-board` artifact with fresh JSON and call `update_artifact`; detect completion from the deliverables; and when complete, append a stand-down request to `[team-root]/Overmind/INBOX.md` marked UNREAD. She must also check that inbox marker at the top of every run and exit immediately if it's already there, so she idles cheaply.

**She cannot disable herself** — that call requires a human click and offers no "allow for all" option. She pings; the Overmind reaps. Never write a self-disable step into her prompt.

### Step 4e: Prime her approvals in the same breath — file-only installs

MOTHER's first artifact write triggers one approval dialog. Collect it now, while the human is present:

> Click **Run now** on MOTHER's task, then **"Allow for all scheduled runs"** on the dialog. She goes silent after that.

Never let this dialog find the human later — a permission prompt that arrives after they've context-switched reads as a bug, not a feature. Same for the specialists: warn that the first `/go` in each session may ask for folder or web access.

**Do not edit MOTHER's prompt after her approvals are granted** — editing a task's prompt appears to invalidate its stored grants, and she'll start prompting again. Finalize the prompt, then prime.

### Step 5: Create the deadline escalation task (optional) — file-only installs

After writing HANDOFF.md, create a scheduled task to monitor mission completion. This runs in the background — silent unless something needs attention.

Call `mcp__scheduled-tasks__create_scheduled_task` with:
- `taskId`: `dispatch-poll-[specialist-name-lowercase]-[YYYYMMDD]`
- `cronExpression`: by priority tier — CRITICAL `* * * * *` (every minute) / STANDARD `*/5 * * * *` (every 5 minutes) / LOW `0 * * * *` (hourly)
- `description`: `Mission poll — [specialist name] — [one-line mission summary]`
- `prompt`: Use the template below, filling in all bracketed values (escalation windows [W1]/[W2] by tier: CRITICAL 30 min / 4 h · STANDARD 6 h / 24 h · LOW 24 h / 72 h):

```
You are monitoring a dispatched mission.

Specialist: [specialist name]
Specialist folder: [absolute path to specialist's folder]
Mission complete signal: [specialist-folder]/mission-complete.md
Mission board: [team-root]/MISSION_BOARD.md — this mission's row: [mission ID]
Gopher registry: [team-root]/GOPHER_REGISTRY.md
Human operator: [human's first name]
Priority: [CRITICAL / STANDARD / LOW] — escalation windows: not activated after [W1], overdue after [W2]
Deadline: [YYYY-MM-DD HH:MM, or "none"]
Task ID (to disable on completion): dispatch-poll-[specialist-name-lowercase]-[YYYYMMDD]

Your job each run:

1. Check if [specialist-folder]/mission-complete.md exists.
   - If YES: Read it. Report to the human: "[Specialist] has completed their mission. [summary from file]. See [deliverables path]." Reconcile the mission board: if this specialist's lane on row [mission ID] is not already done, mark it done with today's date; if every lane on the row is done, note in your report that the mission is ready for the dispatcher to converge; if any BLOCKED row or lane lists [mission ID] in Depends On, note in your report that it is now clear to start. Then call mcp__scheduled-tasks__update_scheduled_task with enabled: false to stop this task.
   - If NO: continue.

2. Check [team-root]/MISSION_BOARD.md row [mission ID] and [team-root]/GOPHER_REGISTRY.md for [specialist name] — board first (claimed state), registry second (proof of boot):
   - Lane ACTIVE + registry refreshed after dispatch: online and working. No action this cycle.
   - Lane ACTIVE but registry predates the dispatch: phantom flip — unverified. Write a GOPHER PING to [specialist-folder]/INBOX.md if one isn't already waiting.
   - Registry refreshed after dispatch but lane still PENDING past [W1]: silent boot — booted, never took the brief. Ping and notify the human the boot layer may need attention.
   - No registry refresh, lane PENDING: not yet activated. No action until [W1] past dispatch, then notify the human: "[Specialist] hasn't activated yet. Open their session and type /go."
   - Activated but no mission-complete past [W2]: notify the human: "[Specialist] activated but mission is not yet complete. May need your attention."

3. Deadline rules (skip if Deadline is "none"): halfway to the deadline with the lane still PENDING → notify the human now. Deadline passed without the lane done → escalate immediately, regardless of tier.

4. Only surface to the human when: mission complete, not activated past [W1], silent boot detected, overdue past [W2], or a deadline rule fires.
```

Fill in all bracketed values before creating the task. The specialist folder path comes from Step 2. The team root is the connected folder.

### Step 6: Report back — the human scoreboard

Report to whoever initiated the dispatch — the human directly, or a specialist reporting upstream. **The human never reads wire format.** Whatever went to a channel or a HANDOFF header, the close is a translated, human-readable scoreboard — a first-class deliverable, not decoration. One row per lane:

| Mission | Asset | Status | Latest signal | Next |
|---------|-------|--------|---------------|------|
| M-017 backlog scrub | alex | DISPATCHED | Brief staged in their folder | You: open their session, type /go |

"Latest signal" is plain English, never a raw protocol line.

Then close with the human's entire job, in plain lines:

> **[Specialist Name] briefed on [M-###].**
> Open their session and type **`/go`**. First activation may ask for folder or web access; grant it while you're there.
> I'm watching the ledger. I'll report when they're done. You don't need to check back.

If multiple specialists were dispatched in one shot, one scoreboard row per lane, and the middle line names them all: "Open each of their sessions and type `/go` in each." If dispatching laterally (specialist to specialist), also note which session should be opened and in what order if sequencing matters. Keep it tight — the human knows what to do from here.

On a **file-only install**, swap the ledger line for the MOTHER beats, in this order:

> **MOTHER is watching [mission ID].** Click **Run now** on her task, then **"Allow for all scheduled runs"**.
> Then open [session names] and type **`/go`** in each. First activation may ask for folder access. Grant it while you're there.
> I'll report back with `/status` when she signals completion.

---

## Why this works

Every specialist boot layer already contains the Sleeper Protocol: at startup, they silently read their HANDOFF.md and hold the staged mission. The human types `/go` → they activate, restore their browser context, open with the mission title so the chat names itself, deliver mission status, and go to work. No one needs to re-explain what was happening.

**Overmind-initiated loop:**
1. Human describes task → Overmind dispatches (this skill)
2. Human opens specialist session → types `/go` → specialist activates
3. Specialist works → saves deliverables to their folder → posts status to the team channel if a transport is bound
4. Results flow back through the board (and the ledger, when one exists) — the Overmind translates them into the scoreboard

**Lateral dispatch loop (specialist to specialist):**
1. Specialist hits a domain boundary mid-task → invokes this skill to brief a peer
2. Specialist reports to the human: "I've briefed [Name] on [M-###]. Open their session and type /go."
3. Human opens the peer session → types `/go` → peer activates and continues the work
4. Results flow back through the human to whoever needs them
