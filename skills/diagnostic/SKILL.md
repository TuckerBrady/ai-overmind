---
name: diagnostic
description: >
  Verify that an Overmind installation is actually wired correctly, and diagnose it when it
  isn't. Use when the human types /diagnostic, says "run a diagnostic", "level 1 diagnostic",
  "self test", "verify my setup", "is my team wired up right?", "something's broken with my
  Overmind", or right after first-run team building to confirm every system is functional.
  Three levels: 3 (fast local sweep, default), 2 (adds live platform probes), 1 (adds the
  full multi-session asset audit). Every FAIL prints its own fix.
---

# /diagnostic — System Verification

Borrowed from Starfleet: **higher numbers are quicker, Level 1 is the complete teardown.**

| Invocation | Level | Scope | Runs in |
|---|---|---|---|
| `/diagnostic` | 3 | Local sweep — install, structure, identity, board integrity | seconds |
| `/diagnostic 2` | 2 | Level 3 + live platform probes (artifact, scheduled task, network) | ~3 min |
| `/diagnostic 1` | 1 | Level 2 + every asset audits its own wiring and signs | ~10 min, needs the human |

Default to **Level 3** when no level is given. Only escalate if the human asks, or if Level 3
produces a FAIL whose root cause a deeper level would isolate — in that case say which level
you'd run and why, then let them choose.

## Ground rules

1. **PASS means verified this session.** Never infer a PASS from memory, from a previous run,
   or from "it worked earlier." A check you couldn't perform is **SKIP**, not PASS.
2. **A false PASS is the only real failure.** FAIL is useful and costs nothing.
3. **Every FAIL carries its fix inline.** A diagnostic that reports a broken state without the
   remedy has only relocated the confusion.
4. **Never repair silently.** Two exceptions, both harmless and both reported: creating a
   missing `INBOX.md`, and refreshing your own stale Gopher row. Anything else — structural
   moves, roster edits, Instructions changes — you propose, the human approves.

---

## LEVEL 3 — Local sweep (default)

Run all four groups, then report. Nothing here needs another session or the human's hands.

### A · Install & version drift

**A1 — Plugin version.** Resolve your own plugin root by walking up from this skill file to
`.claude-plugin/plugin.json` and read `version`.

**A2 — Marketplace drift.** Fetch
`https://raw.githubusercontent.com/TuckerBrady/ai-overmind/master/.claude-plugin/marketplace.json`
(add a cache-buster query param) and compare `plugins[0].version` to A1.

- Equal → PASS.
- Installed is behind → **FAIL: install is pinned to an old snapshot.**
  *Fix:* open the marketplace and press **Update**. If Update is greyed out or does nothing,
  remove the marketplace entirely → restart the Claude app → re-add `TuckerBrady/ai-overmind`
  → install. (Auto-sync only fires when a PR containing a version bump merges to the default
  branch; it does not fire on direct pushes, so a stale pin is a normal state, not a bug.)
- No network → SKIP, and say so plainly.

This one check accounts for more "the plugin is broken" reports than everything else combined.
Run it first.

### B · Team root & structure

**B1 — Team root reachable.** Read a file at the team root. If you cannot reach it, or the app
prompts the human for folder access to complete this read → **FAIL.**
*Fix:* this project's connected folder (Context) must be the **team root**, not the member's
subfolder. Every project — the Overmind's and each specialist's — connects the same root;
identity comes from Project Instructions, not from the mount.

**B2 — Shared state present.** At the team root: `TEAM_ROSTER.md`, `GOPHER_REGISTRY.md`,
`MISSION_BOARD.md`. Missing any → FAIL, *fix:* run the structure cleanup described in the
field manual's Upgrading section, or ask the Overmind to rebuild the missing file from roster.

**B3 — Roster ↔ folders agree.** Every member named in `TEAM_ROSTER.md` has a folder, and every
member folder maps to a roster entry. Orphans in either direction → FAIL, *fix:* run the roster
skill's sync pass (`/overmind` → roster → sync), which reconciles roster, folders, bootstraps,
and dispatch roster in one pass.

**B4 — Member files at folder root.** For each member folder: bootstrap present, persona file
present, `INBOX.md` present. All cross-session files live at the **folder root** — never under
`.auto-memory/`, which is not the project folder. Missing `INBOX.md` → create it, then PASS
with a note. Missing persona or bootstrap → FAIL, *fix:* regenerate via the roster skill.

### C · Identity & activation wiring

**C1 — Identity resolves.** You can state your member name and folder from Project Instructions.
If you cannot tell who you are → FAIL, *fix:* paste the Sleeper Activation block for this member
into the project's Instructions (generate it with `/overmind`).

**C2 — Sleeper block is current.** The block in your Instructions must contain all three boot
duties — read `HANDOFF.md`, check `INBOX.md`, **write your row to `GOPHER_REGISTRY.md`** — and
must accept `/go` as an activation trigger. A block missing the registration clause is the
pre-v3.9.2 version: it registered only via the SessionStart hook, which is not guaranteed to
arrive before the first message, making boot registration a coin flip. → FAIL, *fix:* regenerate
and re-paste the block for every project, not just this one.

**C3 — Own Gopher row.** Your row exists in `GOPHER_REGISTRY.md`. Report its age: fresh (<6 h),
stale (>6 h), dormant (>48 h), or absent. Absent or dormant → refresh it now and note that you
did. If it was absent, that is evidence C2 failed even if the block *looks* right.

### D · Board integrity

**D1 — Board parses**, and every assignee resolves to a roster member.

**D2 — Board vs disk.** Same reality check as `/status`, order of authority:
`mission-complete > deliverable files > board row > registry > silence`. A row marked PENDING
whose deliverable already exists, or COMPLETE with nothing on disk, is a FAIL of bookkeeping —
report which side you trust and why.

**D3 — Stale in-flight.** Any ACTIVE row past its deadline, or any mission whose assignee has
never registered, gets surfaced with its age.

### Report — Level 3

A single table, one row per check, `PASS / FAIL / SKIP`. Then:

- **Verdict** — one line. `ALL SYSTEMS NOMINAL — n checks passed` or `n FAIL, m SKIP`.
- **Fixes** — only the failed checks, each with its remedy, ordered by what to do first.
- Nothing else. No narration of checks that passed.

---

## LEVEL 2 — Adds live platform probes

Everything in Level 3, plus three probes that prove the moving parts actually move. Tell the
human up front that Level 2 creates and then removes a temporary scheduled task, and collect
its approvals in the same breath — a permission dialog that finds them ten minutes later reads
as a bug.

**E1 — Artifact channel.** Write and update an artifact (reuse `mission-board` if it exists,
otherwise create a scratch one). Confirm the update returns cleanly. FAIL → the live board will
not repaint; MOTHER still works but the human loses visibility.

**E2 — Scheduled-task channel (MOTHER's engine).** Create a **one-shot task, already enabled**,
firing ~2 minutes out, whose only job is to append one dated line to the Overmind's `INBOX.md`.
When the line appears, delete the task and PASS. If it never fires → FAIL, *fix:* scheduled
tasks need their approvals granted in this session; re-run and approve when prompted. Never
leave the probe task behind.

**E3 — Network reach.** Confirm `raw.githubusercontent.com` is fetchable (A2 already proves it —
report SKIP-as-covered rather than fetching twice).

---

## LEVEL 1 — Complete teardown (multi-session audit)

Everything in Level 2, plus the part no single session can fake: **each asset verifies its own
wiring and signs for it.** This is the only way to catch a stale Instructions block or a
mis-mounted Context in someone else's project, because only that session can see them.

The elegance here is that the test's mechanism *is* the thing under test. If dispatch, `/go`,
boot registration, and inbox reporting all work, the audit completing is itself the proof. If
activation is broken, the audit cannot finish — which is an unambiguous diagnosis, not a
mystery.

1. **Write the audit file** at the team root: `SETUP_AUDIT_[YYYY-MM-DD].md` — one row per roster
   member, columns: Asset · Role · Team root reachable · Board readable · Own INBOX exists ·
   Persona present · Gopher row at boot · Signed (HH:MM). Then a **Notes** section, one line per
   asset, "be specific."
2. **Sign your own row first** as the Overmind, so the format is unambiguous.
3. **Dispatch the audit** to every specialist via the dispatch skill — CRITICAL, one shared
   operation codeword, MOTHER launched per the dispatch rules, all approvals front-loaded.
4. **Tell the human exactly one thing:** open each specialist session and type `/go`.
5. **Collect and report** the full matrix when the rows land. Stand MOTHER down when the last
   row is signed; she cannot disable herself.

### Wording the boot-registration check so it is answerable

Do **not** ask whether the Gopher row predates all mission work — in a session whose first
message is `/go`, boot and activation are the same message, so a pre-mission timestamp is
structurally impossible and the check can only ever FAIL. Ask instead:

> Is your row present in `GOPHER_REGISTRY.md`, and was it written in boot order
> (handoff → inbox → registry) before you began audit work this session? If your row was
> carried over from an earlier session, refresh it and say so.

A check that cannot come back PASS is a broken check, not a finding. Walk every check from the
asset's seat, under the exact activation path they'll use, before you dispatch it.

---

## First run

After `/overmind` builds a team for the first time, `/diagnostic` is the natural next command:
it confirms the folders, roster, registry, and Instructions blocks all landed before the human
trusts the setup with real work. Recommend it once, in one line, and don't nag.

When someone reports that their Overmind is "not working," run `/diagnostic` before asking them
any questions. Most of the time the table answers the question for them.
