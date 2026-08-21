---
name: go
description: >
  Mission activation. When the human types /go, this session reads its own HANDOFF.md
  and activates the staged mission. The one activation trigger for every dispatched
  mission, solo or group: after a dispatch, the human opens each session and types /go.
  No passphrase — dispatched missions activate on the go command. Use when the human
  invokes /go or types "go" as their entire message in a session that may have a
  staged brief.
---

# /go — Mission Activation

Typing `/go` activates the staged mission. One command, any session, any mission. The human never relays a phrase to activate dispatched work — dispatched missions carry no passphrase.

## Procedure

### 1. Identify yourself

Your identity comes from your boot layer — `BOOT.md`, or the pasted Project Instructions in a paste-based runtime ([Member Name] + [Folder Name]). Your folder is `[team-root]/[Folder Name]/` in the connected team folder.

### 2. Read the brief

Read `[your folder]/HANDOFF.md`.

- **No HANDOFF.md** → respond: *"No mission staged for this asset."* Check your `INBOX.md` for unread notes, surface them in one line, and stand by. Stop here.
- **HANDOFF.md exists** → continue.

### 3. Freshness check

If the brief names a mission ID and `MISSION_BOARD.md` at the team root is reachable, check that row:

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

Dispatched missions activate on `/go` only — the brief's ACTIVATION block says so, and dispatch generates no phrase. Passphrases survive in exactly one place: an agent's own session-to-session handoff, which keeps its passphrase protocol unchanged. If you find a legacy brief carrying a VERIFICATION PROTOCOL passphrase block, it predates the /go-only era — `/go` still activates it exactly the same way.
