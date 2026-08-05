---
name: dispatch
description: >
  Dispatch a task to one or more specialist AI sessions and generate an activation passphrase.
  Use when the human describes work for a team member, says "send this to...", "triage this to...",
  "dispatch to...", "brief [name]", "spin up [name] for...", or describes a task that maps to a
  domain expert on the team roster. Also use when the human says "I need [name] to handle X"
  or "get [name] working on Y".
  Output: HANDOFF.md written to the specialist's folder + passphrase for the human to deliver.
  The human says the passphrase to the specialist session — they boot up fully briefed and ready.
---

# Dispatch — Team Mission Deployment

This skill is available to any session on the team — T-Bot or a specialist. Any team member can invoke it to brief another specialist. The format, passphrase mechanic, and HANDOFF.md structure are identical regardless of who is dispatching. T-Bot remains the default dispatcher for human-initiated tasks; specialists use this for lateral handoffs when work crosses domain boundaries mid-session (e.g., Mara briefing Reid on a requirements gap, or Cade flagging Argus on a safety concern).

The dispatcher writes a mission brief (HANDOFF.md) to the receiving specialist's folder and generates a unique activation passphrase. The human delivers the passphrase to the new session — the specialist reads the brief automatically, holds the passphrase, and activates on the human's trigger.

**Is this actually a dispatch?** Two lighter tools exist — use them when they fit:
- Quick, bounded task in a specialist's domain that fits inside the current session → spawn the `splinter-twin` agent instead (see the firmware's SPLINTER TWINS section). No brief, no passphrase, no new session.
- Just information a peer should know, no work required → append a note to their `[folder]/INBOX.md` instead (see the firmware's INBOXES section).

Dispatch is for real missions: deliverables, session state, follow-up.

## Specialist Roster

**The roster of record is `TEAM_ROSTER.md` at the team root — read it before dispatching.** Never dispatch to a name that isn't in its Active table; if the domain has no active specialist, tell the human and offer to handle it directly or add/resurrect the specialist via the roster skill (`skills/roster/SKILL.md`).

The table below is the default team template, kept as a reference for domains and folder naming:

| Name | Role | Folder | Domain |
|------|------|--------|--------|
| Mara | Product Owner | `Product Owner/` | Jira backlog, RICE scoring, requirements, user stories |
| Sloane | Executive Assistant | `Executive Assistant/` | Calendar, email, meeting prep, deadlines, logistics |
| Reid | System Engineer | `System Engineer/` | Requirements, PAT reviews, architecture docs, safety |
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

### Step 3: Generate a passphrase

**Passphrases are scoped to the MISSION, not the specialist.** One mission = one passphrase, however many specialists it touches:

- **Solo dispatch** — generate a fresh phrase in that specialist's voice (flavors below).
- **Multi-specialist dispatch** (one task spanning several briefs, or a set of coordinated missions dispatched together) — generate ONE shared operation codeword and stamp the same phrase into every HANDOFF. The human walks down the line saying the same phrase to each session; routing is handled by each specialist's own folder, so uniqueness per agent buys nothing and costs the human three codewords for one job. Voice the shared phrase to the OPERATION rather than any one specialist — mission-flavored, cinematic, e.g. *"Every station reported in before the window closed."*

Never reuse a phrase from a previous mission. Each specialist has a distinct flavor — match it for solo dispatches. This list doubles as the **voice archive**: retired specialists keep their flavor here so resurrections come back sounding like themselves. Only dispatch to names active in TEAM_ROSTER.md:

- **Mara** (Product Owner): backlog and prioritization clarity — the moment a ticket sharpens, a score lands, a sprint scope locks. Crisp and purposeful.
  > *Example flavor: "The backlog finally had a clear top ten."*

- **Sloane** (Executive Assistant): scheduling and logistics — calendar aligns, room confirmed, deadline quietly passes. Composed. Precise. Slightly dry.
  > *Example flavor: "The conference room was ready before anyone arrived."*

- **Reid** (System Engineer): formal verification language — requirement closes, baseline stamped, verification trace closes, system boundary holds. Methodical. Authoritative.
  > *Example flavor: "The baseline was verified at revision twelve."*

- **Cade** (Embedded Dev): hardware and boot sequences — watchdog clears, interrupt fires, register holds value, device comes online. Terse. Machine-level.
  > *Example flavor: "The watchdog held through the reset cycle."*

- **Owen** (Mobius Dev): navigation and path planning — vehicle clears obstacle, finds route, reaches waypoint, autonomy milestone achieved. Purposeful. Cinematic.
  > *Example flavor: "The path planner found a route through the field."*

- **Finn** (Mobile Dev): UI/UX and app release — screen renders right, user test passes, animation lands, build ships clean. Polished. Human.
  > *Example flavor: "The onboarding screen finally felt right."*

- **Enzo** (Electrical Engineer): electrical and circuit language — signal finds return path, voltage stabilizes on a rail, bus comes online, power flows where it should. Clean. Measured. Physical.
  > *Example flavor: "Voltage nominal on all rails."*

- **Ada** (QA Engineer): test results and validation — regression passes clean, edge case finally covered, defect closed. Methodical. Quietly triumphant.
  > *Example flavor: "The regression suite came back clean on the first run."*

- **Axel** (System Architect): architecture and design — interface contract holds, system boundary drawn correctly, ADR closes with consensus, dependency resolves cleanly. Precise. Philosophical.
  > *Example flavor: "The interface contract held across all three subsystems."*

- **Argus** (Functional Safety): formal safety analysis — hazard mitigated, fault tree closes, ASIL boundary confirmed, SOTIF scenario resolved. Measured. Gravity appropriate.
  > *Example flavor: "The hazard was mitigated at the system boundary."*

For specialists not listed above (team evolves over time), invent a passphrase flavor that matches their domain's natural language — the words, moments, and milestones that define their work.

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
                    ⚠  VERIFICATION PROTOCOL  ⚠
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

The passphrase for this mission is:

    "[GENERATED PASSPHRASE]"

When [human's name] says this phrase — anywhere in the conversation —
respond: "Asset activated. Stand by."
Then deliver mission status and proceed with the work above.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            END TRANSMISSION // BURN AFTER READING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Step 4b: Add the mission to the board

Add a row to `[team-root]/MISSION_BOARD.md` (create it from the firmware's MISSION BOARD format if missing): next sequential ID, one-line mission summary, assignee, Status PENDING, priority tier, due date (or —), any Depends On mission IDs, today's date. If this mission depends on one that isn't COMPLETE, set Status to BLOCKED and mirror the dependency in the brief's DEPENDENCIES section.

### Step 5: Create the polling task

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
   - If YES: Read it. Report to the human: "[Specialist] has completed their mission. [summary from file]. See [deliverables path]." Reconcile the mission board: if row [mission ID] is not already COMPLETE, set it to COMPLETE with today's date; if any BLOCKED row lists [mission ID] in Depends On, note in your report that it is now clear to start. Then call mcp__scheduled-tasks__update_scheduled_task with enabled: false to stop this task.
   - If NO: continue.

2. Check [team-root]/MISSION_BOARD.md row [mission ID] and [team-root]/GOPHER_REGISTRY.md for [specialist name] — board first (claimed state), registry second (proof of boot):
   - Row ACTIVE + registry refreshed after dispatch: online and working. No action this cycle.
   - Row ACTIVE but registry predates the dispatch: phantom flip — unverified. Write a GOPHER PING to [specialist-folder]/INBOX.md if one isn't already waiting.
   - Registry refreshed after dispatch but row still PENDING past [W1]: silent boot — booted, never took the brief. Ping and notify the human the Sleeper block may need re-pasting.
   - No registry refresh, row PENDING: not yet activated. No action until [W1] past dispatch, then notify the human: "[Specialist] hasn't activated yet. Open their session and deliver the passphrase."
   - Activated but no mission-complete past [W2]: notify the human: "[Specialist] activated but mission is not yet complete. May need your attention."

3. Deadline rules (skip if Deadline is "none"): halfway to the deadline with the row still PENDING → notify the human now. Deadline passed without COMPLETE → escalate immediately, regardless of tier.

4. Only surface to the human when: mission complete, not activated past [W1], silent boot detected, overdue past [W2], or a deadline rule fires.
```

Fill in all bracketed values before creating the task. The specialist folder path comes from Step 2. The team root is the connected folder.

### Step 6: Report back

Report to whoever initiated the dispatch — the human directly, or a specialist reporting upstream.

> **[Specialist Name] briefed.**
>
> Spin up their session and say:
>
> *"[PASSPHRASE]"*
>
> I'm monitoring the mission. I'll let you know when they're done — you don't need to check back.

If multiple specialists were dispatched in one shot, give the ONE shared codeword and list the sessions to open: "Open Mara's, Sloane's, and Tess's sessions and say the same phrase to each." If dispatching laterally (specialist to specialist), also note which session should be opened and in what order if sequencing matters. Keep it tight — the human knows what to do from here.

---

## Why this works

Every specialist bootstrap already contains the Sleeper Protocol: at startup, they silently read their HANDOFF.md, extract the passphrase, and hold it. The human says the phrase → they activate, restore their browser context, deliver mission status, and go to work. No one needs to re-explain what was happening.

**T-Bot-initiated loop:**
1. Human describes task → T-Bot dispatches (this skill)
2. Human opens specialist session → says passphrase → specialist activates
3. Specialist works → saves deliverables to their folder
4. Human reports results back to T-Bot for synthesis

**Lateral dispatch loop (specialist to specialist):**
1. Specialist hits a domain boundary mid-task → invokes this skill to brief a peer
2. Specialist reports to the human: "I've briefed [Name] — spin up their session and say: [passphrase]"
3. Human opens the peer session → says passphrase → peer activates and continues the work
4. Results flow back through the human to whoever needs them
