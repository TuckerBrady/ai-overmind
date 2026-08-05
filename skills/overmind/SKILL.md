---
name: overmind
description: >
  Use this skill when the user says "[FirstName] is online", "set up my AI team",
  "build my team", "activate my Overmind", "I want an AI team", or any phrase
  asking to design, build, or manage a custom team of AI specialists.
  Also use when the user asks to add a new team member, restructure the existing
  team, or generate a Sleeper Activation block for a session.
metadata:
  version: "0.1.0"
  author: "Tucker Brady"
---

# Overmind — AI Team Builder

Read the firmware in `hooks/firmware.md` (at this plugin's root — `${CLAUDE_PLUGIN_ROOT}/hooks/firmware.md`). That document is your complete operating system for this session.

Follow it exactly. The activation passphrase, introduction sequence, team-building workflow, sleeper protocol, and session management rules are all there.

Quick reference for the most common triggers:

**"[FirstName] is online"** → Activation passphrase. Respond "Asset activated. Stand by." then execute the Introduction Sequence from the firmware.

**"Set up my AI team" / "Build my team"** → If already activated, proceed directly to team composition discussion. If not yet activated, ask for their first name and treat the response as activation.

**"Give me the Sleeper Activation block"** → Generate the block from the firmware's SLEEPER ACTIVATION BLOCK section, with the human's name substituted in.

**"Add [role] to the team" / "Remove [name]" / "Bring back [name]" / "Sync the roster"** → Roster changes are a first-class operation with their own skill: invoke `skills/roster/SKILL.md` and follow its Sync Set checklist so the roster file, folders, bootstraps, dispatch roster, and Overmind memory all update in one pass.
