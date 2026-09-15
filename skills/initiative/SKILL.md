---
name: initiative
description: >
  Show or change the team's initiative setting: how much every AI team member does on its own before
  asking the human. Like TARS's honesty setting in Interstellar, it's a percentage dial (25, 50, 75,
  90, 100). Use when the human types /initiative, "/initiative 90", "set initiative to 75", "what's
  our initiative setting", "take more initiative", "stop asking me so much", "you ask too many
  questions", "check with me more", or "you're doing too much without asking". Output: the current
  setting, or the new one written to the team's WORKING_WITH_[name].md so every seat has it.
---

# /initiative — the team's initiative setting

Named for TARS's settings dial in *Interstellar*. One number, set by the human, shared by the whole team. It
controls how much a team member finds and does on its own before it asks. It lives in
`WORKING_WITH_[FIRSTNAME].md` at the team root. Every member's BOOT.md imports that file, so every
session has the setting at boot. TARS tells any session that is already running when it changes.

## The scale

| Setting | Behavior |
|---|---|
| 25% | Propose, then wait. Ask before gathering or acting. |
| 50% | Gather freely; ask before acting on anything beyond reading. |
| 75% | Gather and act on anything reversible; confirm irreversible steps. |
| 90% | Find everything yourself. Act on everything reversible without asking. Resolve ambiguity by checking, not by asking. One confirmation, only at an irreversible or outward-facing final step. |
| 100% | As 90%, and where the human has pre-authorized a class of action, skip even that final check-in. |

At every setting, the platform's hard limits and required confirmations still apply. The setting changes how much a member asks. It never changes what a member is allowed to do.

Only these five values are valid. A number in between rounds to the nearest one; say which. Words
map too: "low" 25, "cautious" 50, "balanced" 75, "high" 90, "full" or "max" 100. "Take more
initiative" with no number means one step up. "Check with me more" means one step down.

## Procedure

### 1. Find the file

Look for `WORKING_WITH_*.md` at the team root (the folder holding `MISSION_BOARD.md`; from a member
folder, its parent).

- **Found:** read its `## Initiative setting: N%` heading.
- **Missing:** this team predates v4.5.0. In the Overmind's session, run the firmware's WORKING WITH
  YOUR HUMAN upgrade: ask the onboarding question, create the file from the template, and add the
  import to every member's BOOT.md in the same pass. In a specialist's session, tell the human the
  Overmind sets it up, and write a `WORKING-STYLE` entry to the Overmind's INBOX.md with the level
  the human asked for.

### 2. Show or set

- **`/initiative` alone:** reply with the current setting and its one-line behavior from the scale.
  Nothing else.
- **`/initiative N`, or a request to change it:** from any seat, this is the human's direct word, so
  apply it:
  1. Rewrite the `## Initiative setting: N%` heading.
  2. Move the bold marker in the scale table to the new row.
  3. Append a dated line to the file's change log: the old and new setting, and the human's reason
     in their words if they gave one.
  4. Confirm in one line: `Initiative setting: 75% → 90%. Every seat has it now.`

Running sessions pick up the change on their next message: TARS reports that the file was updated,
and each seat re-reads it. Nothing needs to be pasted anywhere. In lite mode, where TARS doesn't run,
say that other open sessions pick it up at their next boot.

### 3. Act on it immediately

The session that changed the setting behaves at the new level from its very next action. A human
who just raised it to 90% because they were tired of questions should not get another question on
the next turn.
