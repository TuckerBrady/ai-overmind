---
name: roster
description: >
  Add, remove, rename, or re-role a member of the AI team — one seamless, repeatable
  process that keeps every file in sync. Use when the human says "add a team member",
  "add [role] to the team", "remove [name]", "retire [name]", "I removed [names]",
  "downsize the team", "bring back [name]", "resurrect [name]", "rename [name]",
  "who's on the team", or "sync the roster". Also use when the sessions the human
  actually has no longer match TEAM_ROSTER.md. Output: roster, folders, bootstraps,
  dispatch roster, and Overmind memory all updated in one pass.
metadata:
  version: "1.0.0"
  author: "Tucker Brady"
---

# Roster — Team Membership Management

The team roster changes. People get added when a domain heats up, retired when it goes quiet, resurrected when it comes back. Every change touches the same set of files — miss one and the ecosystem drifts: dispatch offers specialists that don't exist, memory contradicts reality, docs describe a team from three months ago. This skill is the one door all roster changes walk through.

## The Sync Set

Every roster operation must leave ALL of these consistent. This is the checklist — walk it every time, no exceptions:

1. **`TEAM_ROSTER.md`** at the team root — the roster of record. Create it if missing (format below).
2. **The specialist's folder** under the team root (created, deleted, or renamed).
3. **Bootstrap + persona files** inside that folder (for adds/resurrections).
4. **`GOPHER_REGISTRY.md`** at the team root — remove rows for departed members.
5. **`MISSION_BOARD.md`** at the team root — every Active row assigned to a departed member gets resolved: reassigned (usually to the Overmind), or closed with a note. Never leave a live mission assigned to a ghost.
6. **`INBOX.md`** at the departing member's folder root — check for UNREAD entries; anything unactioned gets surfaced to the human or re-routed before the member goes dark.
7. **The dispatch roster** — wherever dispatch is defined for this ecosystem (a saved `dispatch` skill, the firmware's DISPATCH section, or both). Update the specialist table AND the passphrase-flavor list AND any names hard-coded in the skill description.
8. **Overmind memory** — every memory file that names team members, counts them, or maps the ecosystem. Grep memory for each affected name; update or tombstone. Update the MEMORY.md index lines to match.
9. **Living docs** that state the roster (status boards, ledgers, setup guides). Historical documents (old handoffs, completed mission briefs, dated reports) are NOT rewritten — if one materially misleads, add a dated banner at the top instead.

If TEAM_ROSTER.md doesn't exist yet, create it at the team root:

```markdown
# TEAM ROSTER — Overmind Ecosystem

**Canonical roster of record.** If a doc, skill, or memory disagrees with this file, this file wins.
**Last updated:** [YYYY-MM-DD]

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

1. **Spec the member.** Name (check TEAM_ROSTER.md's Removed table first — retired names are reserved for their domain; a returning domain gets its old specialist back, same name, same voice), role, domain, 6–10 responsibilities, personality posture, passphrase flavor. Propose it; get the human's confirmation before touching disk.
2. **Create the folder** at the team root, named after the role (e.g., `Data Engineer/`).
3. **Write the bootstrap .docx, persona .md, and starter INBOX.md** per the firmware's TEAM BUILDING section (read the docx skill first) — all at the folder root. Include the Sleeper Protocol, Gopher Registration, Mission Complete Signal, Mission Board, and Inbox Protocol sections in the bootstrap.
4. **Add to the Sync Set** — roster table, dispatch roster (table + passphrase flavor), memory.
5. **Activate** — write the onboarding HANDOFF.md to the folder root, generate a passphrase in their flavor, and hand the human the standard activation instruction (new Cowork project → connect the same team root folder → paste Sleeper block → say the passphrase). Track it on the status board until they're online.

## Operation: REMOVE (or RETIRE)

1. **Confirm scope.** Which members, and what happens to their folders — the three dispositions:
   - **Archive** (default suggestion): move the folder into `[team-root]/_Archive/`. Nothing lost; easy resurrection.
   - **Leave in place**: docs and memory updated only.
   - **Delete**: permanent. Confirm explicitly before deleting — name what's inside (handoffs, personas, work product). Never delete on inference.
2. **Check for active missions.** If the member has an unread HANDOFF.md, an open mission, or an Active row on MISSION_BOARD.md, flag it — the mission needs a new owner (usually the Overmind) before the member goes dark.
3. **Execute the disposition**, then walk the full Sync Set. In TEAM_ROSTER.md, move them to the Removed table with date and disposition — don't erase them from history.
4. **Tombstone, don't amnesia.** Memory files about the member get rewritten to record the removal and preserve what matters for resurrection (name, domain, voice) — not deleted outright, unless the human says so.
5. **Reassign orphaned work.** Grep living docs and memory for tasks assigned to the departed member; each one gets flagged to the human: Overmind absorbs it, another member takes it, or it dies with a note.

## Operation: RENAME / RE-ROLE

Treat as a single transaction: update folder name (if role changed), bootstrap identity section, persona file name and contents, and the full Sync Set. Note the old name in TEAM_ROSTER.md ("formerly [X]") so old documents still resolve.

## Operation: AUDIT ("sync the roster")

When the human's actual sessions and the file system disagree — or on request — run a reconciliation:

1. List folders at the team root; list TEAM_ROSTER.md active members; ask the human which sessions actually exist.
2. Report the diff in a status-board table (present ✓ / missing ✗ / undocumented ⚠).
3. Propose the operations needed to converge, get confirmation, execute via the operations above.

## Report format

Close every roster operation with a tight after-action block:

> **ROSTER UPDATED — [N] active**
>
> [What changed, one line per member affected]
> [Sync Set items touched, one line]
> [Anything orphaned/flagged, if applicable]

Then, if a new member was added, go straight into the activation instruction — don't make the human ask.
