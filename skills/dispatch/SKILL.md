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

**No passphrases.** Dispatch does not generate activation passphrases — activation for every dispatched mission is `/go` (see `skills/go/SKILL.md`). Session handoffs activate on `/go` too — since v4.3.0, nothing in this system uses a passphrase.

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

### Step 4c: Post to the transport, if one is bound

Check the team root for `TRANSPORT.md`.

**Transport bound (TRANSPORT.md exists AND its tools are available this session):** post one one-line TASK per lane to the team channel — mission ID + lane + one-line goal + the HANDOFF path:

```
TASK M-017 / alex — score the Q3 backlog — HANDOFF: Product Owner/HANDOFF.md
```

(One TASK naming several members with lane assignments is also fine. Every post carries the shared mission ID.) Never put a secret, token, or passphrase in a post, ever.

**No transport:** skip this step. Nothing else changes.

### Step 4d: Confirm TARS is watching

Nothing to launch. In Claude Code, TARS — the plugin's turn hook — reports a lane's delivery the moment its `mission-complete.md` appears, and cues you to run the watch rules when a mission's check-in window lapses. At session start, your BOOT.md **MISSION WATCH** step runs the same rules. Line formats, the watch rules, and lite-mode behavior live in the firmware (TARS — THE TURN HOOK, and DISPATCH Step 5).

So this step is a check, not a launch:

- Your BOOT.md carries the **MISSION WATCH** step → nothing to do.
- It doesn't, or it's still titled **MOTHER — MISSION WATCH** → replace it with the canonical step, and honor the dual-runtime law: the edit isn't done until re-pasted into every paste-based runtime.

**Never create a scheduled task for a dispatched mission** — no `mother-watch-*`, no `dispatch-poll-*`, and no approval to prime. If an older install still has either kind of task, list them for the human and have them removed, so a mission is never watched twice.

### Step 5: Report back — the human scoreboard

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

On a **file-only install**, swap the ledger line for TARS's:

> **TARS is watching [mission ID].** Open [session names] and type **`/go`** in each. First activation may ask for folder access. Grant it while you're there.
> TARS reports the moment it lands while we're working, and I'll catch anything that happened while you were away at the start of our next session. Nothing to click, nothing to switch off.

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
