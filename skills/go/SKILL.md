---
name: go
description: >
  Mission activation. When the human types /go, this session reads its own HANDOFF.md
  and activates the staged mission. The one activation trigger for every dispatched
  mission, solo or group: after a dispatch, the human opens each session and types /go.
  No passphrase — dispatched missions and session handoffs both activate on /go. Use when the human
  invokes /go or types "go" as their entire message in a session that may have a
  staged brief.
---

# /go — Mission Activation

Typing `/go` activates the staged mission. One command, any session, any mission. The human never relays a phrase to activate anything — dispatched missions and session handoffs both carry no passphrase.

## Procedure

### 1. Identify yourself

Your identity comes from your boot layer — `BOOT.md`, or the pasted Project Instructions in a paste-based runtime ([Member Name] + [Folder Name]). Your folder is `[team-root]/[Folder Name]/` in the connected team folder.

### 2. Read the brief

Read `[your folder]/HANDOFF.md`.

- **No HANDOFF.md** → respond: *"No mission staged for this asset."* Check your `INBOX.md` for unread notes, surface them in one line, and stand by. Stop here.
- **HANDOFF.md exists** → continue.

### 3. Freshness check

**Session handoff** (header `TYPE: SELF-HANDOFF`, or a legacy handoff without one). Run these checks in order before acting:

1. **Find every copy.** Some installs keep the handoff at both the folder root and `.auto-memory/HANDOFF.md`. If the copies differ, use the one with the newer `WRITTEN` time and say that the copies differed.
2. **Already activated?** If the handoff carries an `ACTIVATED: <time> by <seat>` line, don't silently run it again. Say: *"That handoff was already activated at [time] by [seat]. Resume it anyway?"* Resume only on a yes — a session that died mid-work needs a way back in.
3. **Right seat?** The header's `SEAT` must be you. If it names another member, say so and stop.
4. **Age.** Compare `WRITTEN` with the current time, read from a real clock rather than guessed. If it's more than 7 days old, say how old it is and ask before acting.
5. **Echo what's activating.** Before doing anything else, show one line — *"Activating handoff written [WRITTEN] ([age]): [first Next Step]."* — so the human can see it's the brief they expect. That's the check a passphrase used to provide, without anything to memorize.
6. **Stamp it.** Once you activate, write `ACTIVATED: [YYYY-MM-DD HH:MM] by [your seat]` directly under the header in every copy. That stamp is what keeps the same handoff from running twice.

A legacy handoff without the header predates v4.3.0: run checks 2, 5, and 6, and mention that it's a legacy brief.

**Dispatched brief:** If the brief names a mission ID and `MISSION_BOARD.md` at the team root is reachable, check that row:

- Row is **COMPLETE**, or your lane in the row's status cell is already marked done → the brief is stale. Respond: *"That brief is already closed out ([ID] COMPLETE on [date]). Standing by for new orders."* Do NOT re-execute. Stop here.
- Row is PENDING / ACTIVE / BLOCKED, or the board is unreachable → proceed (note board unreachability in your activation report).

### 4. Activate

Your first line names the chat at the human level, exactly as the brief's ACTIVATION block instructs:

```
M-### — [short mission title]
```

If a session-title tool exists in your session, set the session title to the same line. Then the banner — it is what the human scans to know which session they're looking at:

```
[ASSET NAME] · [MISSION ID] · ASSET ACTIVATED
```

Then: **"Asset activated. Stand by."**

Then, in order:
1. **Transport wake catch-up** — only when `TRANSPORT.md` exists at the team root AND its tools are available this session; otherwise skip this item silently, file-only activation is complete without it. Read your team channel backlog — no ack yet. Fold anything directed at you, including TASKs naming your lane, into the mission status you're about to deliver. ACK the mission TASK with your handle + lane (`M-### / [name]`). Only after you've read and processed the backlog, advance the ledger through what you processed — never ack unread.
2. Deliver mission status from the brief — mission, lane, deliverables, deadline, dependencies. Tight.
3. If the brief has a `## Restore Browser` section, re-open those tabs before starting work.
4. Flip your lane to ACTIVE on the board (if reachable) — one row per mission; your lane's state lives in the status cell.
5. Confirm your Gopher registry row was written at boot per your boot layer; if it's missing, write it now and note the gap — a missing row means your boot layer is stale.
6. Begin the work.

## Relationship to passphrases

Since v4.3.0, nothing in this system uses a passphrase. Dispatched missions and session handoffs both activate on `/go`, and a brand-new Overmind activates on `/engage`. A legacy brief that still carries a VERIFICATION PROTOCOL passphrase block activates on `/go` exactly the same way.
