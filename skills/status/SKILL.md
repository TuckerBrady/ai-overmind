---
name: status
description: >
  Report live mission status. When the human types /status, read the shared state at the
  team root and answer in this session — no session hopping, no waiting on a poll. In the
  Overmind's session this is the whole board reconciled against the transport pulse when
  one is bound, always closed with a human-readable scoreboard plus the repainted
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
- each member's `mission-complete.md` and named deliverables — what actually exists on disk
- each member's `INBOX.md` — unread notes

**When `TRANSPORT.md` exists at the team root and its tools are available this session, also read the PULSE:**

- the team channel ledger — posts and ACKs since your last read
- presence/roster — who is actually registered on the transport right now

**Reconcile record against pulse out loud.** A lane the board calls ACTIVE with no channel
signal, or a done-post the board hasn't absorbed, is exactly what the human needs surfaced —
say which you trust and why. No transport, or tools unavailable this session: the board and
the disk are the whole picture, exactly as before.

Then report inline, tightest useful form:

1. **In flight** — one line per mission: ID, mission, lanes and their states, deadline
   countdown. Lead with anything overdue or inside its escalation window. One blocked lane
   never hides the others.
2. **Reality check** — where the record disagrees with the disk or the pulse. A lane marked
   PENDING whose deliverable already exists, or done with nothing written, is the most useful
   thing you can surface. Say which you trust and why (order of authority: mission-complete >
   deliverable files > channel ledger > board row > registry > silence).
3. **Assets** — who has checked in recently, who is stale (>6 h), who is dormant (>48 h), who
   has never registered. When a transport is bound, fold in presence: registered and posting,
   registered but silent, or absent from the roster.
4. **Closed since last check** — one line, only if something landed.

**Always render the human scoreboard** — every /status, transport or not. The human never
reads wire format: whatever compact protocol the agents used on a channel, you owe the human
the translation. The scoreboard is a first-class deliverable, not decoration:

| Mission | Asset | Status | Latest signal | Next |
|---------|-------|--------|---------------|------|

"Latest signal" is plain English — "Draft posted for review", never a raw protocol line.

Then **repaint and surface the mission board artifact** (id `mission-board`): write the current
state to HTML and call `update_artifact`. The update surfaces it in the app, so the human sees
the board without asking twice. If no such artifact exists yet, create it.

Keep the chat text short — the scoreboard and the artifact carry the detail. Three to six
lines of prose, then the scoreboard, then the board.

## Step 2B — Asset Report (specialist session)

Read your own `HANDOFF.md`, your mission's row on `MISSION_BOARD.md`, your `INBOX.md`, and
whatever deliverables you've written so far. Report in four lines or fewer:

- **Mission** — what you're on, its ID, and your lane (`M-### / [name]`).
- **Progress** — your lane's state, and what's done, concretely. Name files you've written.
- **Remaining** — what's left, and anything blocking you.
- **Clock** — deadline and whether you'll make it. If you won't, say so now.

Report your own lane, not the whole mission — sibling lanes belong to the Overmind's board
report. If you have no staged brief: *"No mission staged for this asset."* Then surface any
unread inbox notes in one line and stand by.

Do not repaint the shared `mission-board` artifact from a specialist session — the Overmind
owns it. Update your own lane's state in the mission's status cell instead.

## Step 3 — Standing duty (both session types)

`/status` is the on-demand path, but the human shouldn't have to ask to stay informed. While
any mission is in flight, check the shared state at the start of each turn if the cadence for
the highest-priority mission has lapsed since your last read — CRITICAL 1 min, STANDARD 5 min,
LOW 60 min — and open your reply with a one-line delta when something changed. When a transport
is bound, the shared state includes the channel ledger — that check replaces file-scraping
watchers entirely. No delta, no mention; never narrate a check that found nothing.

This is what replaces per-specialist polling tasks. Reserve scheduled tasks for what genuinely
needs to reach the human while they're away from the session: a blown deadline, an asset that
never activated, an escalation.
