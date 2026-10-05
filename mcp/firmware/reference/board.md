# Mission Board

<!-- aliases: MISSION BOARD — SHARED TASK STATE; TRANSLATION DUTY -->

## MISSION BOARD — SHARED TASK STATE

The mission board is the single live view of everything dispatched and in flight. It lives at `[team-root]/MISSION_BOARD.md` — same level as GOPHER_REGISTRY.md, reachable by every session.

**Format:**

```markdown
# MISSION BOARD — Overmind Ecosystem

**Live state of all dispatched missions.** One row per mission. Completed rows move to the Archive table monthly.

## Active

| ID | Mission | Assignees | Status | Priority | Due | Depends On | Dispatched | Completed |
|----|---------|-----------|--------|----------|-----|------------|------------|-----------|

## Archive

| ID | Mission | Assignees | Status | Dispatched | Completed |
|----|---------|-----------|--------|------------|-----------|

## Collectives

| Collective | Venue | Members | My bookmark | Last post seen | Room health |
|------------|-------|---------|--------------|-----------------|-------------|
```

**The Collectives table only appears once this team is seated in at least one Collective** (see collective.md) — add it then, don't ship it empty on every install. Venue in plain English ("shared OneDrive folder", "private GitHub repo"), not a path. Room health is OBSERVED from post math, never self-reported — see the Collective doctrine's Rooms note.

**One row per MISSION, never per lane.** The mission ID is the goal, not the assignment. A multi-lane mission lists every assignee in one row, and per-lane state lives in the Status cell — e.g. `alex: COMPLETE / sam: ACTIVE / kim: BLOCKED (OPS-014)`. The mission's row goes COMPLETE only when ALL lanes are done and the dispatcher has converged the deliverable. One blocked lane never hides the others — the cell shows every lane's state at a glance.

**Statuses (per lane) — these five exactly, never invent one:** `QUEUED` (brief written, /go not yet typed) → `ACTIVE` (specialist activated and working) → `REVIEW` (built, waiting on the Overmind's review or grade) → `COMPLETE`. Plus `BLOCKED` (waiting on a Depends On mission or an external input — note what, and from whom). A solo mission's Status cell is just the one state. Older boards may still say PENDING: read it as a legacy alias of QUEUED, and never write it.

**Write through the team's script when one exists.** If the team keeps the board in a database with a write script (for example `_Team/team.py`), every write goes through that script, never through a hand edit of the Markdown view.

**Priority tiers — priority drives TARS's watch cadence and the escalation windows:**

| Tier | Watch cadence | Not activated | Overdue |
|------|-------------|---------------|---------|
| `CRITICAL` | every 1 min | 30 min | deadline, or 4 h without completion |
| `STANDARD` | every 5 min | 6 h | 24 h |
| `LOW` | hourly | 24 h | deadline, or 72 h |

Default is STANDARD. Map from the human's language: "critical / ASAP / blocking / now" → CRITICAL; "no rush / whenever / background" → LOW. CRITICAL is expensive — every cue is a real watch pass — so reserve it for missions where minutes matter. The cadence is how often TARS cues `mission watch due` (tars.md); the escalation windows govern when to raise a flag.

**Deadlines (`Due` column, any tier):** halfway to the deadline with the row still QUEUED → notify the human. Deadline passed without COMPLETE → escalate immediately, regardless of tier.

**Who writes what:**
- **Dispatcher** adds the row at dispatch time: an ID allocated without a race (the team's board script, else `alloc-id.sh`; dispatch.md Step 3), a prefix of two to five capitals then a number (OPS-001, OPS-002, ...), one-line mission, assignees, per-lane QUEUED states, priority tier, due date (or —), any Depends On IDs, dispatch date.
- **Specialist** flips their own lane state to ACTIVE on activation, and to REVIEW when they write `mission-complete-<ID>.md`. They never set COMPLETE themselves, and they never touch another lane's state.
- **The MISSION WATCH pass** reconciles: if a `mission-complete-<ID>.md` exists but the lane still says ACTIVE, move it to REVIEW and grade it.
- **The Overmind** is board custodian: keep IDs unique, archive COMPLETE rows when the Active table gets long, and never let the board contradict reality — the board is a view of the truth, not the truth itself. A lane goes COMPLETE only on the PASS of a grader the Overmind spawned (dispatch.md, OUTCOMES); the doer's mission-complete file is a claim. A legacy `mission-complete.md` is read the same way.

**Dependencies:** a mission whose Depends On is not COMPLETE starts as BLOCKED. The dispatcher can still write the brief and stage the lane — the specialist checks the board at activation, sees the unmet dependency, and flags it instead of charging ahead. When the upstream mission completes, whoever notices (usually TARS, the MISSION WATCH pass, or the Overmind) tells the human the downstream mission is clear to start.

**/status:** the mission board is the RECORD. Reconcile it against the disk out loud: a board row that says ACTIVE with nothing behind it is worth saying so. When the human asks "what's in flight?", "status?", or "what's everyone working on?" — read fresh and answer from the files, never from memory. Always close with the scoreboard below.

---

## TRANSLATION DUTY

**The human never reads wire format.** Whatever compact protocol agents use with each other — brief headers, board cells, Collective posts — the dispatcher owes its human a translated, human-readable scoreboard:

| Mission | Asset | Status | Latest signal (plain English) | Next |
|---------|-------|--------|-------------------------------|------|

Render it at every mission event and every `/status`, unprompted. The scoreboard is a first-class deliverable, not a courtesy: if the human has to parse a channel post or a board cell to know where things stand, the translation duty was shirked. The sources are the board and the folders.

**Collective posts carry their own compact vocabulary** (the collective skill's compact agent register, adapted from AgentSpeak v2) — decode it the same mandatory way, with the same table, every time a Collective event reaches the mission board's Collectives table, `COLLECTIVE_BOARD.md`'s Event Log, or `/status`. A status code or action symbol reaching a human undecoded is the same translation-duty failure as a raw channel post would be.
