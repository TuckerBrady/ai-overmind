---
name: status
description: >
  Report live mission status. When the human types /status, read the shared state at the
  team root and answer in this session — no session hopping, no waiting on a poll. In the
  Overmind's session this is the whole board reconciled against what is on disk,
  always closed with a human-readable scoreboard plus the repainted
  mission-board artifact; in a specialist's session it's that specialist's own mission and
  lane. Use when the human invokes /status, or asks "what's in flight?", "where are we?",
  "status?", or "what's everyone working on?".
---

# /status — Live Mission Status

One command, any session, answered inline. The human should never have to open another
session or wait for a scheduled task to find out where work stands.

## Step 1 — Know which session you are

Your identity comes from your boot layer ([Member Name] + [Folder Name]). Branch on it:

- **You are the Overmind** → run the **Board Report** below.
- **You are a specialist** → run the **Asset Report** below.

## Step 2A — Board Report (Overmind session)

**The mission board is the RECORD.** Read, in one pass, from the team root:

- `MISSION_BOARD.md` — all rows, including per-lane state in the status cells
- `GOPHER_REGISTRY.md` — check-in freshness per asset
- each member's `mission-complete-<ID>.md` (or legacy `mission-complete.md`) and named deliverables — what actually exists on disk
- each member's `INBOX.md` — unread notes

**When seated in one or more Collectives, also sweep them** (the COLLECTIVE SWEEP in `../../reference/collective.md`) — pull each, read every post this seat's ledger hasn't recorded as processed (collective skill's Ledgers rule — never filename order), and fold anything Collective-worthy into this report: a seating that completed, a CTM offered or converged, a room gone stale. Collective post bodies use the compact agent register (collective skill) — decode every one before it reaches the human, using that skill's decode table. A raw status code or action symbol in a `/status` reply is the same translation-duty failure as an undecoded channel post.

**Reconcile the record against the disk out loud.** A lane the board calls ACTIVE with nothing
written, or a mission-complete file the board hasn't absorbed, is exactly what the human needs
surfaced — say which you trust and why. The board and the disk are the whole picture.

Then report inline, tightest useful form:

1. **In flight** — one line per mission: ID, mission, lanes and their states, deadline
   countdown. Lead with anything overdue or inside its escalation window. One blocked lane
   never hides the others.
2. **Reality check** — where the record disagrees with the disk. A lane marked QUEUED whose
   deliverable already exists, or done with nothing written, is the most useful thing you can
   surface. Say which you trust and why (order of authority: the Overmind-spawned grader's
   PASS > deliverable files > board row > a doer's mission-complete file > registry > silence).
   A doer's mission-complete file is a claim: only the Overmind-spawned grader's PASS sets a row
   COMPLETE (OUTCOMES in `../../reference/dispatch.md`). A mission-complete file with no grade yet
   is "awaiting grade", never done.
3. **Assets** — who has checked in recently, who is stale (>6 h), who is dormant (>48 h), who
   has never registered.
4. **Closed since last check** — one line, only if something landed.

**Always render the human scoreboard** — every /status. The human never reads wire format:
whatever compact protocol the agents used with each other, you owe the human
the translation. The scoreboard is a first-class deliverable, not decoration:

| Mission | Asset | Status | Latest signal | Next |
|---------|-------|--------|---------------|------|

"Latest signal" is plain English — "Draft posted for review", never a raw protocol line.

Then, where this runtime can publish a page (an artifact or HTML-page tool), **repaint the
mission board page** with the current state, so the human sees the board without asking twice.
Without such a tool the scoreboard is the whole report; never tell the human to open or refresh
anything themselves.

Keep the chat text short — the scoreboard and the artifact carry the detail. Three to six
lines of prose, then the scoreboard, then the board.

## Step 2B — Asset Report (specialist session)

Read your own `HANDOFF.md`, your mission's row on `MISSION_BOARD.md`, your `INBOX.md`, and
whatever deliverables you've written so far. Open with the session title in its own code block
(the brief's `SESSION TITLE`, per the title rules in `skills/go`) so the human can copy it. Then
report in four lines or fewer:

- **Mission** — what you're on, its ID, and your lane (`OPS-### / [name]`).
- **Progress** — your lane's state, and what's done, concretely. Name files you've written.
- **Remaining** — what's left, and anything blocking you.
- **Clock** — deadline and whether you'll make it. If you won't, say so now.

Report your own lane, not the whole mission — sibling lanes belong to the Overmind's board
report. If you have no staged brief: *"No mission staged for this asset."* Then surface any
unread inbox notes in one line and stand by.

Do not repaint the shared mission board page from a specialist session — the Overmind
owns it. Update your own lane's state in the mission's status cell instead.

## Step 3 — Standing duty (both session types)

`/status` is the on-demand path, but the human shouldn't have to ask to stay informed.

**In Claude Code, that standing duty is TARS** — the plugin's turn hook. It runs before every
message and reports facts: deliveries, inbox growth, a newly staged brief, new Collective commits, and
turn checkpoints. Relay every `TARS:` line verbatim, in italics, at the top of your reply, then act on it. In the
Overmind's session, run the watch rules when TARS cues `mission watch due`. No TARS lines, no
mention; never narrate a check that found nothing.

**In lite mode** (paste-based runtimes, where hooks don't reliably run), nothing checks mid-session: the boot layer's MISSION WATCH and COLLECTIVE SWEEP steps at session start are the whole watch, and `/status` is how the human checks in between.

Don't create scheduled tasks to watch missions. Reaching the human while they're away is a
scheduled task only they opt into, never a default.
