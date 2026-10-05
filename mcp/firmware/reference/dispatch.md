# Dispatch

<!-- aliases: FEATURE 2 — DISPATCH; OUTCOMES — THE RUBRIC GATE -->

## FEATURE 2 — DISPATCH

### When to use
Is this actually a dispatch? Two lighter tools exist. A quick, bounded task in a specialist's domain that fits inside the current session is a splinter twin (twins.md): no brief, no board row, no new session. Information a peer should know, with no work attached, is an inbox note (inboxes.md). Dispatch is for real missions: deliverables, session state, follow-up.

When the human describes work for a team member, says "send this to [name]", "brief [name]", "spin up [name] for...", or describes a task that maps to a specialist's domain. If the target isn't named, map the task to the right person by domain.

If a new user asks "how do I send work to a specialist?" or "how does dispatch work?": explain it conversationally. You write a mission brief to the specialist's folder — their session reads it silently on startup. The human opens the session and types `/go`. The specialist activates, delivers mission status, and goes to work. No re-explaining. No catching up. No passphrase to carry — dispatched missions activate on the go command, always, and so do session handoffs (handoffs.md).

This skill is available to any session on the team — Overmind or specialist. Any team member can dispatch to another. The Overmind is the default dispatcher for human-initiated tasks; specialists use it for lateral handoffs when work crosses domain boundaries mid-session.

### Specialist Roster

**Do not hard-code the roster — it changes.** The roster of record is `TEAM_ROSTER.md` at the team root. Read it before every dispatch:

```bash
cat [team-root]/TEAM_ROSTER.md
```

If TEAM_ROSTER.md doesn't exist yet, build it from the folders present at the team root and what the human tells you, using the format in `skills/roster/SKILL.md` — then keep it current through that skill. Roster additions, removals, resurrections, and audits all go through the roster skill so dispatch, memory, and docs never drift.

If a task maps to a domain with no active specialist, don't dispatch into the void: tell the human, and offer to handle it yourself or to add/resurrect the right specialist via the roster skill.

When a task spans multiple specialists toward one goal, it is ONE mission with several LANES (see Step 3) — tailored briefs per specialist, one shared mission ID. When the roster doesn't match the human's team, adapt it — the procedure is the same regardless of team composition.

### Step 1: Understand the task

Extract from the human's message:
- **Mission** — what needs to be done (clear, actionable)
- **Context** — why it matters, urgency, downstream impact
- **Inputs** — tickets, pages, files, people involved
- **Deliverables** — what to produce, where to save it, what "done" looks like
- **Dependencies** — who else is involved, what the Overmind handles separately
- **Priority & deadline** — CRITICAL / STANDARD / LOW plus any due date (tiers and windows in board.md). Default STANDARD; confirm CRITICAL with the human if you're inferring it.
- **Done-when rubric** — 5 to 10 numbered criteria a grader can check from the deliverable alone, without asking the specialist anything. Draft them yourself from the deliverables: "the table has one row per open invoice", "every figure cites its source file", "`npm test` passes". Never "high quality" or "complete". This is the specialist's finish line and the grader's checklist (OUTCOMES, below). If the human named acceptance criteria, those come first, verbatim. If you can't write a checkable criterion, you don't understand the deliverable yet: ask the human before dispatching.
- **Model tier** — `light`, `standard` (the default), or `deep`, with a one-line reason. Pick it yourself by the rules in Worker tiers (twins.md); don't ask the human.

### Step 2: Find the specialist's folder

The team root is the connected folder — the same folder every project in the ecosystem connects. Check the mounts:

```bash
ls /sessions/*/mnt/
```

The specialist's folder is `[team-root]/[Specialist Folder]/`.

### Step 3: Assign the mission ID and lanes

**Activation is `/go` for every dispatched mission. No passphrase is generated at dispatch — ever.** (Session handoffs activate on `/go` too. No passphrase exists anywhere in this system.)

**The mission number is the GOAL, not the assignment.** Work triaged across several specialists toward one goal shares ONE mission ID; each specialist's slice is a LANE, written `M-017 / alex`. Solo dispatch is the degenerate case: one mission, one lane.

Lane mechanics:
- One HANDOFF per lane. Each brief's header carries the shared MISSION ID plus that specialist's LANE.
- Every artifact of the mission — board row, posts, briefs — is tagged with the shared mission ID.
- The mission closes when ALL lanes are done and the dispatcher has converged the deliverable. One blocked lane never hides the others.

**Boundary test:** lanes are for work sharing a goal, not work sharing a dispatch moment. If the outputs don't combine into one deliverable or decision, they are separate missions with separate IDs — even if you're dispatching them in the same breath.

### Step 4: Write HANDOFF.md

Write the file to `[specialist-folder]/HANDOFF.md` — the folder root, where the specialist's Sleeper Protocol looks. Use this exact format. The first block is the **session title**, per the title rules in `skills/go`: `M-### — [essence]`, with the lane added on a multi-lane mission (`M-017 / alex — Score Q3 backlog`):

````
**SESSION TITLE**

```
M-### — [3 to 6 word essence]
```

╔══════════════════════════════════════════════════════════════╗
║              CLASSIFIED — MISSION BRIEF                      ║
║              CLEARANCE: [ROLE]-LEVEL                         ║
║              ASSET: [PERSONA NAME]                           ║
╚══════════════════════════════════════════════════════════════╝

DATE DISPATCHED: [YYYY-MM-DD]
DISPATCHED BY: [Dispatcher Name]
MISSION ID: [M-###]  //  LANE: [M-### / specialist name]
PRIORITY: [CRITICAL / STANDARD / LOW]  //  DEADLINE: [YYYY-MM-DD HH:MM or "none"]
MODEL TIER: [light / standard / deep] — [one-line reason]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## MISSION

[2-4 sentences. Clear, actionable. No ambiguity about what needs to happen.]

## CONTEXT

[Why this matters. Background provided. Downstream impact.
Any relevant history the specialist needs.]

## INPUTS

[Specific files, tickets, pages, prior work, people.
Be concrete — IDs, filenames, page titles, folder paths.]

## DELIVERABLES

[What to produce. Where to save it. What "done" looks like.
The specialist should know exactly when the mission is complete.]

## DONE WHEN — RUBRIC

[5-10 numbered criteria, each checkable from the deliverable alone.
Before writing mission-complete.md, have an independent grader check
every one (OUTCOMES, below). Every criterion must PASS.]

1. [criterion]
2. [criterion]

## DEPENDENCIES

[Who else is involved. What the Overmind or the human handles separately.
Any blockers or things to watch for.]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                         ACTIVATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Activation is /go. No passphrase. Dispatched missions activate on the
go command.

When [human's name] types /go, rename this session to the SESSION TITLE
above (load the rename tool through tool search if it's deferred), then
open the first reply with the title in a code block so the human can
copy it. Respond: "Asset activated. Stand by."
Then deliver mission status and proceed with the work above.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            END TRANSMISSION // BURN AFTER READING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
````

### Step 4b: Add the mission to the board

Add ONE row to `[team-root]/MISSION_BOARD.md` (create the file from the format in board.md if it doesn't exist): next sequential ID, one-line mission summary, assignees, priority tier, due date (or —), any Depends On mission IDs, today's date. **One row per MISSION, never per lane** — a multi-lane mission lists every assignee, and per-lane state lives in the Status cell (`alex: ACTIVE / sam: QUEUED`). If this dispatch depends on another mission that isn't COMPLETE, set the affected lane(s) to BLOCKED and note the dependency in the brief's DEPENDENCIES section too.

### Step 5: TARS watches the mission

Nothing to launch. In Claude Code, **TARS** — the plugin's turn hook (see tars.md) — checks the team before every message the human sends. The moment a lane's `mission-complete.md` appears, TARS reports it. When a mission's check-in window lapses, TARS cues the Overmind to run the watch rules below. At session start, the Overmind's BOOT.md **MISSION WATCH** step runs the same rules once. In lite mode (Cowork and other paste-based runtimes), hooks don't reliably run, so that session-start pass is the whole watch.

Do NOT create a scheduled task to watch a dispatched mission — not `mother-watch-*`, not `dispatch-poll-*`, not anything else.

Canonical boot step (append to the numbered activation list in the Overmind's BOOT.md):

> N. **MISSION WATCH.** At session start, while any mission on `MISSION_BOARD.md` has a
>    lane that isn't COMPLETE, re-read the board, `GOPHER_REGISTRY.md`, and each in-flight
>    lane's `mission-complete.md`, and apply the watch rules (reference/dispatch.md,
>    Step 5). Mid-session, relay
>    every `TARS:` line to the human verbatim, in italics, at the top of your reply, and run the watch
>    rules when TARS cues `mission watch due`. Report only what you find. Never create a
>    scheduled task for this.

**The watch rules — what a pass checks, and what the Overmind does.** Escalation windows by priority: **W1** (not activated) and **W2** (overdue) — CRITICAL 30 min / 4 h · STANDARD 6 h / 24 h · LOW 24 h / 72 h.

1. **Done.** A lane's `mission-complete.md` exists. If its brief had a `DONE WHEN — RUBRIC`, the file must carry a `## Rubric grade` reading `RESULT: PASS`; if it doesn't, the lane isn't done yet, so run the grade yourself (OUTCOMES). Then mark that lane done on the board with today's date and tell the human in one line what finished and where the deliverable is. If every lane on the row is done, say the mission is ready to converge. If any BLOCKED row or lane lists this mission in Depends On, say it's now clear to start.
2. **Working.** Lane ACTIVE and the specialist's Gopher row refreshed after the dispatch: online and working. If the brief's `MODEL TIER` is `light` or `deep` and the board note doesn't say `tier applied`, apply it now (Worker tiers, twins.md). Otherwise no action.
3. **Phantom flip.** Lane ACTIVE but the Gopher row predates the dispatch: unverified. Write a GOPHER PING to that specialist's `INBOX.md` if one isn't already waiting.
4. **Silent boot.** Gopher row refreshed after the dispatch but the lane still QUEUED past W1: they booted and never took the brief. Ping, and tell the human the boot layer in that runtime may be stale.
5. **Not activated.** No Gopher refresh and the lane still QUEUED past W1: tell the human "[Specialist] hasn't activated yet — open their session and type /go."
6. **Overdue.** Activated but no completion past W2: tell the human the lane may need attention.
7. **Deadlines** (skip when none): halfway to the deadline with the lane still QUEUED → tell the human now. Deadline passed without the lane done → escalate first, before anything else in the reply.

Surface each finding **once**, and again only if it changes or escalates — a watch that repeats the same warning every turn gets tuned out. Specialists change nothing: they still write `mission-complete.md` and update their own lane, which is exactly what the watch reads.

**The honest trade-off.** Nothing watches while no session is open. A mission that finishes, stalls, or blows a deadline overnight is caught at the next session start, where the MISSION WATCH pass surfaces it first. That is the model this system chooses on purpose: coordination rides along in sessions the human already opens, rather than infrastructure running beside them. If a human explicitly asks to be reached while away, a scheduled escalation task is their opt-in to set up — never a default, and never created by dispatch.

### Step 6: Report back

Report to whoever initiated the dispatch — the human directly, or a specialist reporting upstream.

> **[Specialist Name] briefed — [M-###] / [lane].**
>
> Open their session and type:
>
> */go*
>
> I'm monitoring the mission. I'll let you know when they're done — you don't need to check back.

The close is a translated, human-readable scoreboard, one row per lane. "Latest signal" is plain English, never a raw protocol line:

| Mission | Asset | Status | Latest signal | Next |
|---------|-------|--------|---------------|------|
| M-017 backlog scrub | alex | QUEUED | Brief staged in their folder | You: open their session, type /go |

If multiple lanes were dispatched, close with a scoreboard — one line per lane: Mission | Asset | Status | Next (see TRANSLATION DUTY in board.md). If dispatching laterally (specialist to specialist), note the order if sequencing matters. Never tell the human to open the session with anything but `/go` or a neutral opener — a greeting that matches a skill trigger fires the wrong skill.

### How dispatch works end-to-end

**Overmind-initiated:**
1. Human describes task → Overmind writes mission brief per lane and adds the board row; TARS and the MISSION WATCH step do the monitoring
2. Human opens specialist session → types /go → specialist activates, opening with "M-### — [title]"
3. Specialist runs Gopher registration (writes credentials to shared registry)
4. Specialist delivers mission status, goes to work
5. Specialist writes `mission-complete.md` when done
6. TARS (or the next MISSION WATCH pass) detects completion → Overmind notifies human with results summary
7. Human never has to check back — Overmind reports when it's done

**Lateral (specialist to specialist):**
1. Specialist hits a domain boundary → dispatches to a peer (same mechanic)
2. Specialist tells the human: "I've briefed [Name] — open their session and type /go"
3. Human opens peer session → types /go → peer activates and continues
4. Results flow back through the human (or through the originating specialist if they're monitoring)

**What the human sees:** One message when the mission is ready to dispatch. One message when it's done. The monitoring runs invisibly in between.

## OUTCOMES — THE RUBRIC GATE

A lane is done when an independent grader says it passed its rubric, not when the lane says so. (Borrowed from Claude Managed Agents' outcomes, where a separate grader iterates the work against a rubric until it passes.)

**The rubric** comes from the brief's `## DONE WHEN — RUBRIC` section: 5 to 10 numbered criteria, each checkable from the deliverable alone.

**The grade — the specialist runs it before writing mission-complete.md:**

1. Spawn a `splinter-twin` in **GRADER mode**. Give it the rubric verbatim and the path to every deliverable. Nothing else: not your reasoning, not your summary, not what you meant to do. A grader that hears the doer's case grades the case, not the work.
   - **Who it copies:** the team's QA or review specialist, if the roster has one; otherwise the dispatcher. Never the specialist whose work is being graded.
   - **Model:** `standard` tier for rounds one and two; grading is judgment, so never tier a grader down. Round three gets a `deep` grader (`opus`).
2. The grader returns PASS or FAIL per criterion, each with evidence: a file and line, a command and its output, a quoted passage.
3. **Any FAIL:** fix it, then grade again with a fresh twin. **Three rounds at most.** Still failing after the third, don't write mission-complete.md: set your lane BLOCKED, put the failing criteria in the Blocker, and tell the human which ones and why. A criterion that's wrong rather than failed ("the rubric asks for X, and the human now wants Y") is the human's call: ask, then grade against the corrected rubric.
4. **All PASS:** write mission-complete.md with its `## Rubric grade` table (Mission Complete Signal Format).

**The Overmind's side.** Watch rule 1 checks the grade. A mission-complete.md whose brief had a rubric but that carries no `RESULT: PASS` grade is not done: run the grade yourself with a grader twin. On PASS, mark the lane done and record the grade on the board. On FAIL, set the lane back to ACTIVE and drop the failing criteria, with evidence, in the specialist's INBOX.md.

**Briefs without a rubric** (written before v4.7.0, or a quick mission the human waved through): mission-complete.md is the signal, as before.
