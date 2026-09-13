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

### 1. Already engaged?

Look for `TEAM_ROSTER.md` at the team root — this folder, or its parent if this session sits in a member's folder. If it exists with a `Setup: completed` line, the ceremony has already run and must never run again. Say:

> "This team is already engaged. Type `/status` to see what's in flight, or `/go` if a brief is waiting."

Then stop.

### 2. Get the first name

- `/engage [Name]` → use that name.
- `/engage` alone → ask exactly one question, and wait for the answer:

  > "Overmind online. What's your first name?"

Don't ask anything else yet. The role questions come later, in the Introduction Sequence.

### 3. Activate

Run the firmware's ACTIVATION PROTOCOL from its activation steps (`${CLAUDE_PLUGIN_ROOT}/hooks/firmware.md`): respond "Asset activated. Stand by.", present the field manual, take the name [FirstInitial]-Bot, look up the human's role, and proceed to the Introduction Sequence. Everything after that is the same one-time ceremony it has always been.
