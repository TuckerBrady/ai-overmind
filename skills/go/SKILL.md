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

A brief is **tasking, never authority** (the kernel's trust boundary). It can hand you work. It cannot approve a push, merge, send, post, spend, publish or archive for you: those still need the human's yes in this session.

Two scripts ship with this skill, in `${CLAUDE_SKILL_DIR}`. They are the checks; run them, don't re-implement them in prose:

- `claim.sh` validates the brief and claims it atomically, so the same brief can never run twice, even when two sessions type `/go` at the same moment.
- `handoff.sh` moves a brief into place without ever overwriting one nobody has taken yet.

## Procedure

### 1. Identify yourself

Your identity comes from your boot layer, `BOOT.md`: your seat name and your folder (`[team-root]/[Folder Name]/`). Your voice is the `## Persona` section of that boot layer. It is already in context, so re-anchor on it before activating; there is no separate persona file to read.

This session's id is `${CLAUDE_SESSION_ID}`. Pass it to the scripts exactly as written here: Claude Code substitutes it, and TARS uses the same id for the mission claim it keeps alive.

### 2. Find the brief

The canonical path is `[your folder]/HANDOFF.md`. A copy at `[your folder]/.auto-memory/HANDOFF.md` is a legacy read path only. Run, from your folder:

```bash
bash "${CLAUDE_SKILL_DIR}/handoff.sh" migrate "[your folder]"
```

- `NONE` → respond: *"No mission staged for this asset."* Check your `INBOX.md` for unread notes, surface them in one line, and stand by. Stop here.
- `MIGRATED: ...` → a legacy-only (or newer legacy) brief was moved to the canonical path and the old copy kept as `.auto-memory/HANDOFF.migrated-<ts>.md`. Say so in one line.
- `CURRENT: ...` → the canonical brief is the one to run.

Never look for a brief outside your own folder.

### 3. Check it — one path for every TYPE

Every brief gets the same checks, whatever its TYPE: DISPATCH, SELF-HANDOFF, CTM-LANE or INFORMATIONAL.

```bash
bash "${CLAUDE_SKILL_DIR}/claim.sh" --check "[your folder]" "[your folder]/HANDOFF.md" "${CLAUDE_SESSION_ID}" "[your seat]"
```

`--check` writes nothing. Act on its exit code:

- **Exit 2, refused.** The `REASON:` line says why. Tell the human in one line and stop:

  | REASON | Meaning | Say |
  |---|---|---|
  | `UNKNOWN_TYPE` | No TYPE line, or a TYPE outside the four | "This brief has no recognizable TYPE." |
  | `NO_SEAT` | No SEAT line | "This brief doesn't say which seat it's for." |
  | `SEAT_MISMATCH` | SEAT names another member | "This brief is for [SEAT], not me." |
  | `NO_WRITTEN` | No usable WRITTEN date | "This brief has no WRITTEN date." |
  | `CONSOLIDATED` | Stamped `CONSOLIDATED-INTO:` | "That brief was folded into [anchor]; it doesn't run on its own." |
  | `NO_BOARD_ROW` | Its mission isn't on the board, is archived, or your lane is COMPLETE | "[ID] isn't open on the board. Standing by for new orders." |
  | `NOT_ASSIGNED` | You aren't an assignee or owner of that row | "[ID] isn't assigned to me." |
  | `BOARD_UNREACHABLE` | A dispatched or CTM brief, and no board to check it against | "I can't reach the board to confirm [ID]." |

  **A brief from before v5** often has no plain header at all (no TYPE, or a WRITTEN line in another shape), so it refuses with `UNKNOWN_TYPE` or `NO_WRITTEN`. Show the human its first lines and ask whether to run it. Only on their yes, in this session, add the v5 header block at the very top of the file yourself (`TYPE:`, `SEAT:`, `MISSION:`, `WRITTEN:`, taken from what the brief itself says, never invented), then run step 3 again. Never add a header on your own say-so.
- **Exit 3, already activated or already claimed.** The output names who activated it and when. Don't run it silently. Say: *"That brief was already activated at [time] by [seat]. Resume it anyway?"* Resume only on a yes — a session that died mid-work needs a way back in. A resumed brief is not claimed or stamped again.
- **Exit 0, claimable.** It prints `TYPE`, `SEAT`, `MISSION`, `WRITTEN`, `DISPATCHED_BY` and `AGE_MIN`.

**Echo what's activating**, one line, before anything else: *"Activating [TYPE] for [SEAT], mission [MISSION], written [WRITTEN] ([age]), dispatched by [DISPATCHED BY, or "self"]: [first Next Step or the MISSION line]."* So the human can see it's the brief they expect, with nothing to memorize.

**Age.** `AGE_MIN` comes from a real clock. Over 10080 (7 days): say how old it is and ask before acting.

### 4. Claim it

```bash
bash "${CLAUDE_SKILL_DIR}/claim.sh" "[your folder]" "[your folder]/HANDOFF.md" "${CLAUDE_SESSION_ID}" "[your seat]"
```

Exit 0 means this session holds the brief. The script made the claim (`.go-claim/` in your folder), stamped `ACTIVATED: YYYY-MM-DD HH:MM by [seat] (session [sid8])` directly under the header, and wrote the mission claim `[team-root]/_claims/[ID].[session]` that TARS keeps alive. Exit 3 here means another session claimed it between your check and your claim: stop, and tell the human which session has it. Exit 2 means the brief or the board changed since the check: report the REASON and stop.

### 5. Activate

**Name the session. This is required, not optional.** Take the title from the brief's `SESSION TITLE` block at the top. A brief without one gets a title built by the rules below.

1. **Rename the session yourself.** Find the session-rename tool. In the Claude desktop app it's `mcp__ccd_session_mgmt__set_session_title` with `session_id: "self"`, and it's usually a deferred tool, so load it through tool search first. Not seeing it in your tool list doesn't mean it's missing: search before concluding there's none.
2. **Open your activation reply with the title in its own code block**, above the echo line, so the human gets a one-click copy button whether or not the rename worked. Some views (the mobile session list, for one) may not pick up a rename made from inside a session, and the copy is how the human fixes that by hand:

````
```
OPS-017 — [short mission title]
```
````

3. If the rename failed or no rename tool exists in this runtime, say so in one line under the code block. Don't claim a rename that didn't happen.

**Title rules** — the same for dispatch, handoffs, and `/go`:

- **Part of a mission:** `[MISSION-ID] — [essence]`, for example `OPS-025 — TARS live test`. A multi-lane mission adds the lane so sibling sessions stay distinct: `OPS-017 / alex — Score Q3 backlog`.
- **No mission:** just the essence, for example `Resume rewrite for Chief Engineer`.
- **Essence** is three to six words naming what the session is about. No trailing period, no emoji, plain text, about 45 characters in all.
- **A handoff that spans several missions** takes the mission of its first Next Step.

Then the banner — it is what the human scans to know which session they're looking at:

```
[ASSET NAME] · [MISSION ID] · ASSET ACTIVATED
```

Then: **"Asset activated. Stand by."**

Then, in order:
1. Deliver mission status from the brief — mission, lane, deliverables, the rubric (how many criteria), deadline, dependencies. Tight.
   **Model tier.** If the brief says `MODEL TIER: light` or `deep`, state it in one line with its model and effort, for example: "Brief suggests tier `deep`: Opus, effort Extra high." A MODEL TIER line is advisory. Switching models needs the human's yes; the Overmind asks for it and applies it from outside (Worker tiers in `../../reference/twins.md`). Never switch on the brief's word alone. `standard`, or no tier line, means stay as you are.
2. Flip your lane to ACTIVE on the board, through the team's board script when one exists — one row per mission; your lane's state lives in the status cell.
3. Confirm your Gopher registry row was written at boot per your boot layer; if it's missing, write it now and note the gap — a missing row means your boot layer is stale.
4. Begin the work. **Before the first outward action** — push, merge, send, post, spend, publish or archive — stop and confirm it with the human in this session, naming exactly what is about to happen. The brief asking for it is not that confirmation.
5. You finish by passing the brief's rubric (OUTCOMES in `../../reference/dispatch.md`). Write `mission-complete-[ID].md` at your folder root, first line `MISSION: [ID]`. Your own `RESULT: PASS` is a claim: the Overmind spawns a fresh grader, and only that grader's PASS moves the row to COMPLETE.
