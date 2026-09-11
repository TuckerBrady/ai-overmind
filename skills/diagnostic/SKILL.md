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

**B4 — Member files at folder root.** For each member folder: persona file present, `INBOX.md`
present. All cross-session files live at the **folder root** — never under `.auto-memory/`,
which is not the project folder. Missing `INBOX.md` → create it, then PASS with a note.
Missing persona → FAIL, *fix:* regenerate via the roster skill.

**B5 — Boot layer per member.** Each member folder must be in one of two recognizable states:

- **Current layout:** `BOOT.md` at the folder root, and — where a working-directory runtime is
  in play — a `CLAUDE.md` wrapper whose import reads exactly `@BOOT.md`. The filename is
  deliberately space-free; an import path with spaces is undocumented behavior and fails
  silently. Wrapper present with the import missing, renamed, or pointing elsewhere → FAIL,
  *fix:* restore the `@BOOT.md` line; boot content is edited in BOOT.md only, never the wrapper.
- **Legacy layout:** a content-bearing `Project Instructions.md` and no `BOOT.md`. Not a FAIL —
  flag it with the migration pointer: the roster skill generates BOOT.md from the existing block
  plus the runtime wrappers. Offer, never force mid-mission, never silently rewrite.

Neither state (no BOOT.md and no content-bearing instructions) → FAIL, *fix:* regenerate the
boot layer via the roster skill.

**B6 — Transport binding.** Only when `TRANSPORT.md` exists at the team root; otherwise SKIP
silently — file-only operation is complete on its own. When present: the file parses (server,
team channel, calls table), and the tools it names are reachable **in this session**. Tools
named but unreachable → report the transport as **DORMANT** — a state, not a failure; every
transport-aware feature falls back to file-only behavior until the tools return. File present
but malformed → FAIL, *fix:* regenerate it from the firmware's TRANSPORT.md template.

**B7 — Collective venue capability (report-only).** In a working-directory runtime, check for
cloud-sync markers, a `.git` folder, and `gh auth status`; in a sandboxed runtime, this is a
report of what was last established in conversation, not a fresh scan. Report which venue
classes (git / synced folder / connector) are available to convene a Collective today — never
FAIL on this; it's a capability matrix, not a requirement. If the team is already seated in one
or more Collectives, also confirm the binder (`COLLECTIVE.md`, `SEATS.md`,
`COLLECTIVE_BOARD.md`) parses and that `MISSION_BOARD.md`'s Collectives section (if present)
lists a row per seated Collective — malformed binder files → FAIL, *fix:* regenerate from the
collective skill's templates.

**B8 — Genesis Seed hygiene (Overmind sessions only, report-only).** If `Overmind/.genesis-seed`
exists, confirm it's readable and never referenced from any shared file (`TEAM_ROSTER.md`,
`GOPHER_REGISTRY.md`, `MISSION_BOARD.md`, any Collective binder) — a reference anywhere shared
is a **FAIL**, *fix:* the nonce has leaked its purpose even if the value itself hasn't; treat it
as compromised and re-mint per the firmware's GENESIS SEED migration note (fresh nonce, new
Genesis ID, new chain anchor per membership). A leftover v4.1.0 `response:` line whose value
appears in any binder `posts/` file is also a **FAIL** with the same fix — that release's gate
published it. A v4.1.0 pair that never left the folder: note it and delete the pair. Any
membership line with `lowest-revealed` at 10 or below: note that chain renewal is due.
If the file doesn't exist yet, that's not a failure — it means `/assimilate` hasn't been run
here yet; note it only if the human is actively trying to join a Collective. Never run this
check from a specialist session — a specialist has no `Overmind/.genesis-seed` to check, by
design, and asking implies it should.

### C · Identity & activation wiring

**C1 — Identity resolves.** You can state your member name and folder from Project Instructions.
If you cannot tell who you are → FAIL, *fix:* paste the Sleeper Activation block for this member
into the project's Instructions (generate it with `/overmind`).

**C2 — Sleeper block is current.** The block in your Instructions must contain all three boot
duties — read `HANDOFF.md`, check `INBOX.md`, **write your row to `GOPHER_REGISTRY.md`** — and
must accept `/go` as an activation trigger. A block missing the registration clause is the
pre-v3.9.2 version: it registered only via the SessionStart hook, which is not guaranteed to
arrive before the first message, making boot registration a coin flip. → FAIL, *fix:* regenerate
and re-paste the block for every project, not just this one. In the current layout the canonical
source is the member's `BOOT.md` — edit there, and remember the dual-runtime law: a boot edit is
not done until it's re-pasted into every paste-based runtime.

**C3 — Own Gopher row.** Your row exists in `GOPHER_REGISTRY.md`. Report its age: fresh (<6 h),
stale (>6 h), dormant (>48 h), or absent. Absent or dormant → refresh it now and note that you
did. If it was absent, that is evidence C2 failed even if the block *looks* right.

**C4 — Paper members.** Every Active roster row needs boot evidence — a Gopher row, ever. A
roster member with no Gopher row was created on paper but never booted: flag as **PAPER
MEMBER**, not ACTIVE. *Fix:* open that member's session and run its first boot (`/go` or any
first message); the roster skill holds adds and resurrections at PENDING FIRST BOOT until this
evidence lands, so a paper member usually means that tracking was skipped.

**C5 — Collective sweep is boot-wired.** Only applies when this Overmind holds any Collective
membership (an `Overmind/.genesis-seed` exists AND a binder root is recorded in `COLLECTIVE.md`,
memory, or the mission board). If so, the Overmind's `BOOT.md` must carry a COLLECTIVE SWEEP step
naming every binder root. Membership without the boot step → FAIL, *fix:* append the canonical
step from the firmware's THE COLLECTIVE SWEEP section, then re-paste per the dual-runtime law.
This is the v4.1.1 field fix: a convener once sat 8 days deaf to its own binder because the sweep
lived in doctrine, not in boot. Then check each ledger:

- **Format.** A format-1 ledger (only `acked-through: <post-id>`) → FAIL, *fix:* migrate per the
  collective skill's Ledgers rule and re-paste the canonical sweep step. Filename-order catchup
  permanently skips posts from any peer whose clock disagrees with yours.
- **Skipped posts.** Any binder post whose `re:` target is at or below this seat's newest
  processed post (or its format-1 watermark), but which the ledger hasn't recorded as processed →
  FAIL. That's a post this seat will never see. On git, "recorded" means the commit that added the
  post is reachable from `acked-commit`; elsewhere, it means the ID is in the Processed list or at
  or below `floor`. *Fix:* process it now, then migrate. A reply whose filename sorts before its
  own `re:` target is proof of clock skew — name both authors. v4.1.3 field case: a peer's
  challenge responses sat unseen for 10 days because the convener's clock named its question
  21:30 while committing it at 21:00.
- **Staleness.** A newest processed post (git: `acked-commit`) days behind the binder head while
  sessions have been running is the deaf-seat failure live, even if the boot step exists (it may
  be malformed or unreachable).

### D · Board integrity

**D1 — Board parses**, and every assignee resolves to a roster member.

**D2 — Board vs disk.** Same reality check as `/status`, order of authority:
`mission-complete > deliverable files > board row > registry > silence`. A row marked PENDING
whose deliverable already exists, or COMPLETE with nothing on disk, is a FAIL of bookkeeping —
report which side you trust and why.

**D3 — Stale in-flight.** Any ACTIVE row past its deadline, or any mission whose assignee has
never registered, gets surfaced with its age.

**D4 — Board vs ledger.** Only when a transport exists (B6 found `TRANSPORT.md` and its tools);
otherwise SKIP. The channel ledger is a second witness against the board: compare
`MISSION_BOARD.md` rows to the channel's TASK and status posts. A board row still ACTIVE whose
lane posted done, or a ledger TASK with no board row, is a FAIL of bookkeeping — apply D2's
authority order and report which side you trust and why. One grading caution: a missing channel
ACK next to a moved board row usually means the session was **permission-gated**, not
disobedient — first posts on a transport can hit permission prompts. Front-load approvals at
dispatch, and grade accordingly.

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
