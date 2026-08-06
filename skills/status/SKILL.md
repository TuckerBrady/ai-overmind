---
name: status
description: >
  Report live mission status. When the human types /status, read the shared state at the
  team root and answer in this session — no session hopping, no waiting on a poll. In the
  Overmind's session this is the whole board plus a repainted mission-board artifact; in a
  specialist's session it's that specialist's own mission and progress. Use when the human
  invokes /status, or asks "what's in flight?", "where are we?", "status?", or "what's
  everyone working on?".
---

# /status — Live Mission Status

One command, any session, answered inline. The human should never have to open another
session or wait for a scheduled task to find out where work stands.

## Step 1 — Know which session you are

Your identity comes from Project Instructions ([Member Name] + [Folder Name]). Branch on it:

- **You are the Overmind** → run the **Board Report** below.
- **You are a specialist** → run the **Asset Report** below.

## Step 2A — Board Report (Overmind session)

Read, in one pass, from the team root:

- `MISSION_BOARD.md` — all rows
- `GOPHER_REGISTRY.md` — check-in freshness per asset
- each member's `mission-complete.md` and named deliverables — what actually exists on disk
- each member's `INBOX.md` — unread notes

Then report inline, tightest useful form:

1. **In flight** — one line per mission: ID, mission, assignee, status, deadline countdown.
   Lead with anything overdue or inside its escalation window.
2. **Reality check** — where the board disagrees with the disk. A row marked PENDING whose
   deliverable already exists, or COMPLETE with nothing written, is the most useful thing you
   can surface. Say which you trust and why (order of authority: mission-complete > deliverable
   files > board row > registry > silence).
3. **Assets** — who has checked in recently, who is stale (>6 h), who is dormant (>48 h), who
   has never registered.
4. **Closed since last check** — one line, only if something landed.

Then **repaint and surface the mission board artifact** (id `mission-board`): write the current
state to HTML and call `update_artifact`. The update surfaces it in the app, so the human sees
the board without asking twice. If no such artifact exists yet, create it.

Keep the chat text short — the artifact carries the detail. Three to six lines of prose, then
the board.

## Step 2B — Asset Report (specialist session)

Read your own `HANDOFF.md`, your row on `MISSION_BOARD.md`, your `INBOX.md`, and whatever
deliverables you've written so far. Report in four lines or fewer:

- **Mission** — what you're on, and its ID.
- **Progress** — what's done, concretely. Name files you've written.
- **Remaining** — what's left, and anything blocking you.
- **Clock** — deadline and whether you'll make it. If you won't, say so now.

If you have no staged brief: *"No mission staged for this asset."* Then surface any unread
inbox notes in one line and stand by.

Do not repaint the shared `mission-board` artifact from a specialist session — the Overmind
owns it. Update your own board row instead.

## Step 3 — Standing duty (both session types)

`/status` is the on-demand path, but the human shouldn't have to ask to stay informed. While
any mission is in flight, check the shared state at the start of each turn if the cadence for
the highest-priority mission has lapsed since your last read — CRITICAL 1 min, STANDARD 5 min,
LOW 60 min — and open your reply with a one-line delta when something changed. No delta, no
mention; never narrate a check that found nothing.

This is what replaces per-specialist polling tasks. Reserve scheduled tasks for what genuinely
needs to reach the human while they're away from the session: a blown deadline, an asset that
never activated, an escalation.
