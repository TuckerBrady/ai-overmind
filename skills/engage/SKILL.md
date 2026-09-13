---
name: engage
description: >
  Activate a brand-new Overmind and build its team. Use when the human types /engage,
  optionally with their first name ("/engage Sarah"), says "engage", or uses the legacy
  phrase "[FirstName] is online". One time per team: if a team already exists here
  (TEAM_ROSTER.md with a "Setup: completed" line), never rebuild it; report status instead.
---

# /engage — Overmind Activation

Named for Captain Picard's order in *Star Trek: The Next Generation*. One command wakes a new Overmind and starts building the team. It replaces the old "[FirstName] is online" phrase, which still works as a legacy alias but is never taught.

## Procedure

### 1. Is there already a team here?

`/engage` must never rebuild a team that exists. Refuse on **any** of these signs, not just one:

- `TEAM_ROSTER.md` in this folder or its parent.
- A `BOOT.md` in this folder, or in any folder directly inside it (member folders).
- This session's own boot layer already names you — for example, it says "You are T-Bot" — meaning you're already an Overmind or a team member.

If you see any of them, say:

> "This team is already engaged. Type `/status` to see what's in flight, or `/go` if a brief is waiting."

Then stop. Don't rely on a `Setup: completed` line: older teams never got one.

**No team, but the folder isn't empty.** A brand-new team normally starts in an empty folder. If this one already holds other files, it might be a code repo or a folder opened by mistake. Ask one question before building anything:

> "There's no team here yet. Start a new one in [folder name]?"

Continue only on a yes. An empty folder needs no confirmation.

### 2. Get the first name

- `/engage [Name]` → use that name.
- `/engage` alone → ask exactly one question, and wait for the answer:

  > "Overmind online. What's your first name?"

Don't ask anything else yet. The role questions come later, in the Introduction Sequence.

### 3. Activate

Run the firmware's ACTIVATION PROTOCOL from its activation steps (`${CLAUDE_PLUGIN_ROOT}/hooks/firmware.md`): respond "Asset activated. Stand by.", present the field manual, take the name [FirstInitial]-Bot, look up the human's role, and proceed to the Introduction Sequence. Everything after that is the same one-time ceremony it has always been. When the ceremony finishes, write a `Setup: completed [YYYY-MM-DD]` line near the top of `TEAM_ROSTER.md` — a marker for humans and tools, not the guard.
