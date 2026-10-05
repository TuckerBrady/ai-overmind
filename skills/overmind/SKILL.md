---
name: overmind
description: >
  The Overmind's doctrine index: where each topic of the full doctrine lives. Use when the user
  asks how the Overmind or the team works, asks to manage or restructure an existing team of AI
  specialists, asks to add a new team member, or asks for a member's Sleeper Activation block.
  Activating a new Overmind and building its first team belongs to the engage skill, never this one.
---

# Overmind — AI Team Builder

Your always-loaded rules are the kernel (`hooks/kernel.md`, injected at session start in a team folder). The full doctrine is on demand, one topic per file in `../../reference/` at this plugin's root (`${CLAUDE_PLUGIN_ROOT}/reference/`). Read the file a task needs before acting on it:

- `../../reference/activation.md` — the first-run activation, the Introduction Sequence, Team Style presets, and the Sleeper protocol
- `../../reference/team-building.md` — team building, the BOOT.md template and its wrappers, the dual-runtime law
- `../../reference/initiative.md` — WORKING_WITH_[FIRSTNAME].md and the initiative setting
- `../../reference/handoffs.md`, `../../reference/dispatch.md`, `../../reference/twins.md`, `../../reference/board.md`, `../../reference/inboxes.md`, `../../reference/gopher.md` — the working features
- `../../reference/collective.md` — multi-Overmind coordination; `../../reference/tars.md` — the turn hook; `../../reference/voice.md` — the Overmind's voice

Each member's boot layer is a single-source `BOOT.md` at its folder root, plus thin runtime wrappers, and each member's persona lives inside that BOOT.md as a `## Persona` section (`../../reference/team-building.md`). Orgs running more than one Overmind can form **the Collective** over a shared folder (`skills/collective/SKILL.md`); an invited human's Overmind joins with `/assimilate` (`skills/assimilate/SKILL.md`). Every team has one `WORKING_WITH_[FIRSTNAME].md` at the team root holding the **initiative setting**, changed only by `/initiative` (`skills/initiative/SKILL.md`).

Quick reference for the most common triggers:

**Activating a new Overmind or building a first team** is the engage skill's job, and only its guard decides whether a team may be built here. This skill never starts activation or team building itself: hand the request to engage, which refuses when any team already exists.

**Restructuring a team that exists** → the roster skill (below).

**"Give me the Sleeper Activation block"** → Generate the SLEEPER ACTIVATION PROTOCOL section of the BOOT.md template in `../../reference/team-building.md`, with the human's name substituted in. The block lives inside the member's `BOOT.md`, which the member's `CLAUDE.md` imports.

**"Add [role] to the team" / "Remove [name]" / "Bring back [name]" / "Sync the roster" / "Re-theme the team" / "Change our team style"** → Roster changes are a first-class operation with their own skill: invoke `skills/roster/SKILL.md` and follow its Sync Set checklist so the roster file, folders, bootstraps, dispatch roster, and Overmind memory all update in one pass. Naming/voice-only changes to the whole team use the skill's RE-THEME operation.
