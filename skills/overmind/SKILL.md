---
name: overmind
description: >
  Use this skill when the user types /engage (or the legacy "[FirstName] is online"),
  says "set up my AI team", "build my team", "activate my Overmind", "I want an AI team", or any phrase
  asking to design, build, or manage a custom team of AI specialists.
  Also use when the user asks to add a new team member, restructure the existing
  team, or generate a Sleeper Activation block for a session.
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

**`/engage`** (optionally `/engage [FirstName]`; the legacy "[FirstName] is online" still works) → Activation, per `skills/engage/SKILL.md`. Respond "Asset activated. Stand by." then run the Introduction Sequence from `../../reference/activation.md`.

**"Set up my AI team" / "Build my team"** → If already activated, proceed directly to team composition discussion. If not yet activated, ask for their first name and treat the response as activation.

**"Give me the Sleeper Activation block"** → Generate the SLEEPER ACTIVATION PROTOCOL section of the BOOT.md template in `../../reference/team-building.md`, with the human's name substituted in. The block lives inside the member's `BOOT.md`; paste-based runtimes copy BOOT.md's full contents into the platform's Project Instructions.

**"Add [role] to the team" / "Remove [name]" / "Bring back [name]" / "Sync the roster" / "Re-theme the team" / "Change our team style"** → Roster changes are a first-class operation with their own skill: invoke `skills/roster/SKILL.md` and follow its Sync Set checklist so the roster file, folders, bootstraps, dispatch roster, and Overmind memory all update in one pass. Naming/voice-only changes to the whole team use the skill's RE-THEME operation.
