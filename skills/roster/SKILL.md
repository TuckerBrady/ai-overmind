---
name: roster
description: >
  Add, remove, rename, re-role, or re-theme a member (or the whole team) — one
  seamless, repeatable process that keeps every file in sync. Use when the human
  says "add a team member", "add [role] to the team", "remove [name]", "retire
  [name]", "I removed [names]", "downsize the team", "bring back [name]",
  "resurrect [name]", "rename [name]", "who's on the team", "sync the roster",
  "re-theme the team", "change our team style", "switch to [preset name] style",
  or "give the team a new name theme". Also use when the sessions the human
  actually has no longer match TEAM_ROSTER.md. Output: roster, folders, boot layers,
  dispatch roster, and Overmind memory all updated in one pass.
---

# Roster — Team Membership Management

The team roster changes. People get added when a domain heats up, retired when it goes quiet, resurrected when it comes back. Every change touches the same set of files — miss one and the ecosystem drifts: dispatch offers specialists that don't exist, memory contradicts reality, docs describe a team from three months ago. This skill is the one door all roster changes walk through.

## The Sync Set

Every roster operation must leave ALL of these consistent. This is the checklist — walk it every time, no exceptions:

1. **`TEAM_ROSTER.md`** at the team root — the roster of record. Create it if missing (format below).
2. **The specialist's folder** under the team root (created, deleted, or renamed).
3. **Boot layer + persona files** inside that folder (for adds/resurrections): `BOOT.md` (the canonical boot layer — single source for every runtime), the thin `CLAUDE.md` wrapper for working-directory runtimes (identity line + the `@BOOT.md` import — the filename is deliberately space-free; never rename it), the `Project Instructions.md` paste-wrapper for paste-based runtimes, and the persona file. Boot edits go to BOOT.md only, never a wrapper — and by the dual-runtime law, a boot edit is not done until the human re-pastes BOOT.md's contents into any paste-based runtime.
4. **`GOPHER_REGISTRY.md`** at the team root — remove rows for departed members.
5. **`MISSION_BOARD.md`** at the team root — every Active row assigned to a departed member gets resolved: reassigned (usually to the Overmind), or closed with a note. Never leave a live mission assigned to a ghost.
6. **`COLLECTIVE_BOARD.md`** in a Collective's shared folder, when this team is seated in one — check the Seats table and any cross-team mission rows naming the affected member or this team's handle; update seat status, reassign or close CTM lanes, and log the change in the Event Log.
7. **`INBOX.md`** at the departing member's folder root — check for UNREAD entries; anything unactioned gets surfaced to the human or re-routed before the member goes dark.
8. **The dispatch roster** — wherever dispatch is defined for this ecosystem (a saved `dispatch` skill, the firmware's DISPATCH section, or both). Update the specialist table AND any names hard-coded in the skill description. The per-member handoff voice archive (the old passphrase-flavor list) lives with the handoff feature now, not dispatch — dispatched missions activate on `/go` and carry no passphrase; update the archive where it lives.
9. **Overmind memory** — every memory file that names team members, counts them, or maps the ecosystem. Grep memory for each affected name; update or tombstone. Update the MEMORY.md index lines to match.
10. **Living docs** that state the roster (status boards, ledgers, setup guides). Historical documents (old handoffs, completed mission briefs, dated reports) are NOT rewritten — if one materially misleads, add a dated banner at the top instead.

If TEAM_ROSTER.md doesn't exist yet, create it at the team root:

```markdown
# TEAM ROSTER — Overmind Ecosystem

**Canonical roster of record.** If a doc, skill, or memory disagrees with this file, this file wins.
**Last updated:** [YYYY-MM-DD]
**Team Style:** [Mission Control / The Guild / Skunkworks / Freestyle — see firmware's TEAM STYLE PRESETS]

## Active

| Session | Persona | Role | Folder | Bootstrap |
|---------|---------|------|--------|-----------|

## Removed

| Persona | Role | Removed | Disposition |
|---------|------|---------|-------------|
```

## Finding the team root

The team root is the connected folder — the one every project in the ecosystem connects, with TEAM_ROSTER.md at its top level. Confirm with `ls /sessions/*/mnt/`. If it isn't connected, request it with `request_cowork_directory` — don't ask the human to go find it.

## Operation: ADD (or RESURRECT)

1. **Spec the member.** Name (check TEAM_ROSTER.md's Removed table first — retired names are reserved for their domain; a returning domain gets its old specialist back, same name, same voice), role, domain, 6–10 responsibilities, personality posture, handoff voice (the passphrase flavor used only for their own session-to-session handoffs — dispatched missions activate on `/go`, no passphrase). Propose it; get the human's confirmation before touching disk.
2. **Create the folder** at the team root, named after the role (e.g., `Data Engineer/`).
3. **Write the boot layer** per the firmware's TEAM BUILDING section — all at the folder root: `BOOT.md` (header naming it the canonical boot layer, runtime orientation, the Sleeper Activation Protocol with Gopher Registration, Mission Complete Signal, Mission Board, and Inbox Protocol, any standing duties, and — only if the team root has a `TRANSPORT.md` — the A2A membership reflex), the thin `CLAUDE.md` wrapper (identity line + `@BOOT.md` import, space-free filename), the `Project Instructions.md` paste-wrapper (points the human at BOOT.md; warns "Do not write instruction content here — it will drift and be lost"), the persona .md, and a starter INBOX.md.
4. **Add to the Sync Set** — roster table, dispatch roster, handoff voice archive, memory.
5. **Activate** — write the onboarding HANDOFF.md to the folder root (ACTIVATION block: activation is `/go`, no passphrase) and hand the human the standard activation instruction (new session → same team root → paste BOOT.md's contents into the platform's Project Instructions for paste-based runtimes → type `/go`). Track it on the status board until they're online.

**Paper members.** A member created on paper but never booted is a PAPER MEMBER, not an active one. Every add or resurrection stays **PENDING FIRST BOOT** until boot evidence exists — a fresh row in `GOPHER_REGISTRY.md` written by that member's own session. Track the pending state on the status board and don't report the member as ACTIVE until the row lands. Audits flag paper members.

## Operation: REMOVE (or RETIRE)

1. **Confirm scope.** Which members, and what happens to their folders — the three dispositions:
   - **Archive** (default suggestion): move the folder into `[team-root]/_Archive/`. Nothing lost; easy resurrection.
   - **Leave in place**: docs and memory updated only.
   - **Delete**: permanent. Confirm explicitly before deleting — name what's inside (handoffs, personas, work product). Never delete on inference.
2. **Check for active missions.** If the member has an unread HANDOFF.md, an open mission, or an Active row on MISSION_BOARD.md, flag it — the mission needs a new owner (usually the Overmind) before the member goes dark. Then close their open missions on the board: each row gets reassigned or closed with a note, and the closing note states that the domain reverts to the Overmind until a successor exists. No row stays live under a departed name.
3. **Execute the disposition**, then walk the full Sync Set. In TEAM_ROSTER.md, move them to the Removed table with date and disposition — don't erase them from history.
4. **Tombstone, don't amnesia.** Memory files about the member get rewritten to record the removal and preserve what matters for resurrection (name, domain, voice) — not deleted outright, unless the human says so.
5. **Reassign orphaned work.** Grep living docs and memory for tasks assigned to the departed member; each one gets flagged to the human: Overmind absorbs it, another member takes it, or it dies with a note.

## Operation: RENAME / RE-ROLE

Treat as a single transaction: update folder name (if role changed), bootstrap identity section, persona file name and contents, and the full Sync Set. Note the old name in TEAM_ROSTER.md ("formerly [X]") so old documents still resolve.

## Operation: RE-THEME

Switches the whole active roster to a different Team Style preset (see the firmware's TEAM STYLE PRESETS section) — a bulk, coordinated version of RENAME. A `TEAM_ROSTER.md` with no Team Style line predates this feature: treat it as Freestyle before proceeding.

1. **Confirm the target style** — one of the firmware presets, or "Freestyle" to drop theming and let names stand as invented. If the human names a style that doesn't exist yet, that's fine: work out its naming pool and tone with them the same way the Introduction Sequence would, then treat it as a new ad hoc preset for this team (it doesn't need to be added to the firmware to be used).
2. **Map old name → new name** for every Active member, drawing from the new preset's pool (never reuse a name across two live members). Show the human the full mapping before touching disk — this changes what they call people day to day.
3. **Walk the full Sync Set per member**, same as RENAME / RE-ROLE: folder name stays (role didn't change, just the persona name), bootstrap identity section, persona file name and contents (update the Voice & Personality field to the new preset's tone line), BOOT.md / CLAUDE.md wrapper / Project Instructions.md wherever the old name appears, GOPHER_REGISTRY.md rows, MISSION_BOARD.md rows, dispatch roster, INBOX.md headers, and Overmind memory. Note the old name in TEAM_ROSTER.md ("formerly [X]") for each, same as any rename.
4. **Update TEAM_ROSTER.md's Team Style header line** to the new preset (or "Freestyle").
5. **The dual-runtime law applies** — a renamed member's BOOT.md isn't done until the human re-pastes it into any paste-based runtime that member runs in. Call this out once for the whole batch, not per member.

This is a naming/voice change only — it never touches role, domain, responsibilities, or folder structure. If the human wants those to change too, that's ADD/REMOVE or RENAME / RE-ROLE on top of this, not part of it.

## Operation: AUDIT ("sync the roster")

When the human's actual sessions and the file system disagree — or on request — run a reconciliation:

1. List folders at the team root; list TEAM_ROSTER.md active members; ask the human which sessions actually exist.
2. Report the diff in a status-board table (present ✓ / missing ✗ / undocumented ⚠). Flag two special states: **paper members** (an Active roster row with no Gopher row, ever — created on paper, never booted) and **legacy layouts** (see below).
3. Propose the operations needed to converge, get confirmation, execute via the operations above.

## Legacy layout migration

A team folder with a content-bearing `Project Instructions.md` and no `BOOT.md` is the **legacy layout** — the pre-v4 world where the boot block lived only in the pasted instructions. Whenever a roster operation or audit touches such a folder: detect it, tell the human, and **offer** the migration — generate `BOOT.md` from the existing block, add the `CLAUDE.md` wrapper, and convert `Project Instructions.md` into the paste-wrapper. Never force the migration mid-mission; never silently rewrite. And state the dual-runtime law when you offer it: the migration is not done until the human re-pastes the new BOOT.md contents into any paste-based runtime.

## Report format

Close every roster operation with a tight after-action block:

> **ROSTER UPDATED — [N] active**
>
> [What changed, one line per member affected]
> [Sync Set items touched, one line]
> [Anything orphaned/flagged, if applicable]

Then, if a new member was added, go straight into the activation instruction — don't make the human ask.
