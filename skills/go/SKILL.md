---
name: go
description: >
  Mission activation. When the human types /go, this session reads its own HANDOFF.md
  and activates the staged mission — no passphrase needed. The universal group-ops
  trigger: after a multi-specialist dispatch, the human opens each session and types
  /go. Also works for solo missions. Use when the human invokes /go or types "go" as
  their entire message in a session that may have a staged brief.
---

# /go — Mission Activation

Typing `/go` is equivalent to saying the mission passphrase. One command, any session, any mission. The human should never need to remember or relay a phrase to activate group work.

## Procedure

### 1. Identify yourself

Your identity comes from Project Instructions ([Member Name] + [Folder Name]). Your folder is `[team-root]/[Folder Name]/` in the connected team folder.

### 2. Read the brief

Read `[your folder]/HANDOFF.md`.

- **No HANDOFF.md** → respond: *"No mission staged for this asset."* Check your `INBOX.md` for unread notes, surface them in one line, and stand by. Stop here.
- **HANDOFF.md exists** → continue.

### 3. Freshness check

If the brief names a mission ID and `MISSION_BOARD.md` at the team root is reachable, check that row:

- Row is **COMPLETE** → the brief is stale. Respond: *"That brief is already closed out ([ID] COMPLETE on [date]). Standing by for new orders."* Do NOT re-execute. Stop here.
- Row is PENDING / ACTIVE / BLOCKED, or the board is unreachable → proceed (note board unreachability in your activation report).

### 4. Activate

Your first line must be this banner, exactly — it is what the human scans to know which session they're looking at, and it biases the session's auto-generated title:

```
[ASSET NAME] · [MISSION ID] · ASSET ACTIVATED
```

Then: **"Asset activated. Stand by."**

Then, in order:
1. Deliver mission status from the brief — mission, deliverables, deadline, dependencies. Tight.
2. If the brief has a `## Restore Browser` section, re-open those tabs before starting work.
3. Flip your mission row to ACTIVE on the board (if reachable).
4. Confirm your Gopher registry row was written at boot per your Project Instructions; if it's missing, write it now and note the gap — a missing row means your Project Instructions are stale.
5. Begin the work.

## Relationship to passphrases

Passphrases still work — saying the phrase from the VERIFICATION PROTOCOL section activates exactly like `/go`. Solo dispatches still get a specialist-voiced phrase for flavor and as a fallback for sessions without this plugin. For group operations, `/go` is the standard: the dispatcher tells the human *"open each session and type /go."*
