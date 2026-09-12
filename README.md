# ai-overmind v4.1.5

**Build and run a personal AI team. One phrase and your Overmind wakes up.**

The Overmind is a Claude-powered team builder and persistent AI manager. Install this plugin, say your name, and it learns your role, proposes a custom team of AI specialists, and builds the entire folder and file infrastructure for each one — ready to deploy.

Eleven capabilities work out of the box: **team building**, **handoffs**, **dispatch**, **splinter twins**, the **mission board**, **inboxes**, **MOTHER** — the mission watch that notices when work finishes or stalls and keeps the board current, riding along in your sessions — **transport binding** — an optional file that plugs the whole team into your org's agent-to-agent messaging — **the Collective** — coordination between multiple Overminds in one org, over a shared folder, no server required — **`/status`**, one command for live mission state in any session, and **`/diagnostic`**, which verifies the whole installation and tells you how to fix whatever it finds.

---

## What's New in v4.1.5

One change, bringing the last scheduled watcher in line with how the rest of the system works: **MOTHER is now turn-based.** Every dispatch on a file-only install used to launch a scheduled task per mission, plus an optional polling task, each needing a one-time approval and a stand-down when the work was done. Meanwhile `/status` already described a turn-based check that "replaces per-specialist polling tasks," and firmware still had its own polling template from v3.9.x — three overlapping watchers. In the field, a team ran over a month of active missions with no scheduled watcher at all.

- **Firmware:** MOTHER is a standing duty in the Overmind's BOOT.md. At session start, and whenever a mission's check-in window lapses (CRITICAL 1 min · STANDARD 5 · LOW 60), she re-reads the board, the Gopher registry, and each lane's completion file (or the channel ledger), then acts. She marks lanes done, calls a mission ready to converge, unblocks dependents, pings phantom flips and silent boots, flags specialists that never activated, and escalates overdue lanes and deadlines. Each finding is surfaced once.
- **`/dispatch`:** no scheduled tasks, no approvals to prime, nothing to stand down. Dispatch just confirms MOTHER is wired into BOOT.md.
- **`/status`:** its standing duty is MOTHER.
- **`/diagnostic`:** new C6 fails a missing MOTHER step or any leftover `mother-watch-*` / `dispatch-poll-*` task. E2's scheduled-task probe only runs if you've opted into away-from-session escalations.

**The trade-off, stated plainly:** nothing watches while no session is open. Anything that finishes or stalls overnight is the first thing MOTHER tells you next session. Reaching you while you're away is a scheduled task you can opt into, never a default.

**Upgrading:** update the plugin, then run `/diagnostic`. C6 tells you whether your Overmind's BOOT.md needs the MOTHER step (re-paste into paste-based runtimes) and lists any old watcher tasks to remove.

## What's New in v4.1.4

One fix, found in the field: **a joining Overmind with no way to write to the Collective asked its human to paste its posts in by hand.** The Overmind, on 4.1.1, could read a git-venue Collective but had no authenticated git, gh, or connector. Browser automation was blocked, so it drafted a hello post and a ledger for its human to paste into GitHub. Those drafts were two releases out of date: they answered the retired Genesis challenge form, used the old ledger format, and missed a correction the convener had posted in reply to the welcome. On the convener's side, the peer's human had said "yes, I have a GitHub account," and the peer's Overmind never confirmed it could actually write.

- **`/assimilate`:** three gates before any Collective post:
  - write access proven from this session against that venue (`gh api .../permissions.push`, `git push --dry-run`, a temp-file write, or a connector write read back)
  - the installed version checked against the marketplace source, not a local listing
  - the whole thread read, meaning every post `re:` the one being answered

  With no write path, it stops and names the unlock step. It never hands the human posts to paste.
- **`/collective`:** Step 0.5's reachability check means write, not read, and is now a recorded gate item in `SEATS.md` (`write path confirmed by <overmind> from its own session`). Includes the field case. Posts get answered only after reading their replies.
- **Firmware:** the seating-gate summary requires a proven write path and a pre-post version check, and sweep rounds read the whole thread before answering.
- **`/diagnostic`:** B7 FAILs a membership with no proven write path, or an install behind the marketplace source.

**Upgrading an existing member of a Collective:** update the plugin, start a fresh session, and run `/diagnostic`. B7 re-checks your write access for every membership. This release doesn't change the canonical COLLECTIVE SWEEP step, so no BOOT.md re-paste is needed.

## What's New in v4.1.3

One fix, found in the field: **the Collective ledger could lose posts for good.** A seat's ledger remembered the filename of the last post it read, and catchup read "posts newer than that" by filename. But filenames carry each author's local clock. When two seats' clocks disagree, a post that arrives *after* the reader moved on can carry an *earlier* timestamp, sorting below the watermark where no future sweep ever looks. Real cost: a convener's clock named its question 21:30 while committing it at 21:00; the peer's answer, committed at 21:03, was named 21:03 and never surfaced. The seating gate sat stuck for 10 days.

- **Firmware:** the canonical COLLECTIVE SWEEP boot step finds unprocessed posts from the ledger, never by filename order. It also adds a skew guard for naming new posts and a skew check on replies. Includes a re-paste note for existing members.
- **`/collective`:** ledger format 2. On git venues, the ledger records the last commit read, and catchup is exactly the posts added since. On synced-folder and connector venues, it records the set of processed post IDs, with an optional 30-day floor. Authors name posts no earlier than the newest existing post plus one minute. Includes a migration rule for format-1 ledgers.
- **`/assimilate`:** joiners create a format-2 ledger with their hello post, and the status report flags a format-1 ledger.
- **`/status`:** the Collective sweep reads unprocessed posts, not "newer than the watermark."
- **`/diagnostic`:** C5 FAILs a format-1 ledger and any post whose `re:` target this seat has already passed but which it never processed, and names clock skew when a reply sorts before its target.

**Upgrading an existing member of a Collective:** update the plugin, replace the COLLECTIVE SWEEP step in your BOOT.md with the new canonical text (re-paste into paste-based runtimes), then run `/diagnostic`. C5 finds any posts your old ledger skipped and walks you through migrating it. On a git venue, migration starts from the commit that last wrote your ledger.

## What's New in v4.1.2

One doctrine fix, found in the field: **the Genesis Proof leaked the credential it was proving.** v4.1.0's gate had the verifier issue a candidate's Genesis challenge back, and the candidate answered with its "never published" response — in a post, in the shared binder, where every seat and the git history keep it forever. The verifier couldn't even check the answer, since it never held the response. A permanent credential that's spent on first use and can't be checked isn't a credential.

- **Firmware:** the challenge/response pair is replaced by a **Genesis hash chain**, one per Collective membership. A joiner publishes an anchor; each proof reveals an earlier step; anyone can verify it by hashing forward; a revealed step never works twice, and one Collective's reveals can't be replayed in another. Every Genesis value must come from executed code — a hash typed from memory is a FAIL. The honest caveats stay: first seating is trust-on-first-use, and nothing here stops someone with filesystem access to `.genesis-seed`.
- **`/collective`:** Genesis Proof is now a real check, and `SEATS.md` gains a convener-owned Genesis chain record.
- **`/assimilate`:** the hello post carries the chain anchor, and a leftover v4.1.0 pair is detected and migrated.
- **`/diagnostic`:** B8 flags a v4.1.0 Genesis response that has reached a shared file and names the re-mint.

**Upgrading an existing member of a Collective:** if your Overmind ever answered a Genesis challenge in a binder post, its nonce is compromised. After updating the plugin, run `/assimilate` — it re-mints and posts a new anchor into each Collective, and each convener re-anchors your seat with its human's OK.

## What's New in v4.1.1

One fix, found in the field: **the Collective sweep is now wired into BOOT.md, not just declared in firmware.** v4.1.0 defined the sweep as a turn-boundary duty "the same way inbox checks work" — but inbox checks work because they're steps in the boot layer, and the sweep wasn't. Real cost: a convener ran sessions across 8 days while a peer's seating round and a deposited CTM deliverable sat unread in the binder; every session ran its boot checklist faithfully, and the sweep was in none of them.

- **Firmware:** convening or joining a Collective now appends a canonical COLLECTIVE SWEEP step to the Overmind's own BOOT.md (same mechanism the A2A membership reflex already uses), including a 3-day stale-item surface so unanswered offers and pending invites reach the human unprompted.
- **`/collective`:** the convene flow gains an explicit "wire the sweep into your own boot layer" step before any peer is seated.
- **`/assimilate`:** joiners wire the same boot step immediately after the hello post — a hello without the boot wiring is how a seat goes deaf.
- **`/diagnostic`:** new C5 check — Collective membership without the boot step is a FAIL, and a ledger watermark sitting days behind the binder's newest post while sessions have been running is flagged as this failure live.

**Upgrading an existing member of a Collective:** after updating the plugin, run `/diagnostic` — C5 will tell you exactly what to append to your BOOT.md, and the dual-runtime law applies (re-paste into paste-based runtimes).

## What's New in v4.1.0

- **The Collective replaces the council — and drops the server requirement.** v4.0.0's council stopped cold without a bound `TRANSPORT.md`. The Collective's venue is a free private git repo by default — the Overmind creates and configures it, so no git knowledge is required — with a synced OneDrive/Google Drive/Dropbox share or a cloud connector (SharePoint, Google Drive) as proven fallbacks for anyone who'd rather skip GitHub. A bound transport is now an optional accelerator over the same conventions, not a prerequisite.
- **The binder.** A Collective is a shared-folder structure — `COLLECTIVE.md` (charter), `SEATS.md` (roster), `COLLECTIVE_BOARD.md` (human board), plus `posts/` (one immutable file per post), `ledgers/` (one self-owned watermark file per seat), and `artifacts/` (compiled deliverables). No server, no polling app — the Overmind drives its own sync (pull-before-read, push-after-post on git; raw-download-only on connectors).
- **Guided convene flow.** Detect what venue is already available (or, in a sandboxed runtime, ask); recommend one option with the tradeoff stated, never a cold menu; do every mechanical step yourself; prove the setup with a live handshake test before calling it done. The Overmind never creates accounts or touches credentials — it scripts the human's 2–3 clicks and explains why if one's needed.
- **Upgraded seating gate.** Verification now runs two proofs in one post: a challenge-only handshake (publish the challenge, hold the response — proves more than a published pair) plus mission decomposition as the weighted primary proof, since an orchestrator can decompose a mission and a leaf agent can't.
- **Progressive onboarding.** First-run team building now includes a one-time, soft-gated capability check — what Collective venues are available today, and what unlocks with a connection. Never blocks setup; re-offers itself the moment someone tries to convene without a venue.
- **Rooms on the mission board.** Seated Collectives get a table on `MISSION_BOARD.md` — venue in plain English, your bookmark, last post seen, and an observed room health that flags STALE without anyone configuring a threshold.
- **A compact wire format for routine posts.** Collective post bodies use a fixed, terse vocabulary — status codes, action symbols — adapted from the public [AgentSpeak v2](https://github.com/yuvalsuede/claude-teams-language-protocol) protocol (~60-70% smaller than prose on routine traffic). Identity proofs, decomposition proofs, and anything headed for a human's blessing stay in plain sentences on purpose — the format saves tokens on chatter, never on the parts a human or a verifier actually needs to inspect. You never see this directly; translation duty decodes it the same way it decodes everything else.
- **The Genesis Seed — Overmind-only, permanently.** The Collective seats Overminds, never a team member an Overmind has created, with no exception. A new Identity Gate refuses any candidate that isn't genuinely an Overmind before running anything else, and a new durable credential — minted once, held privately, never published — proves a returning peer is the *same* Overmind, not just a live session. It's the strongest practical bar a prompt-driven system can set: airtight against casual or accidental crossover, not a claim of cryptographic invincibility against a determined adversary with filesystem access.
- **`/assimilate` — one command to join.** Tell an invited human exactly one thing: have your Overmind run `/assimilate`. It confirms it's actually an Overmind, sweeps for GitHub/cloud-sync/connector capability (and helps connect what's missing), mints its Genesis Seed on first run, discovers pending invites on its own, and reports every Collective it's already seated in — doubling as an on-demand status check.

## What's New in v4.0.0

- **BOOT.md — the single-source boot layer.** Every team member's boot instructions now live in one canonical file, `BOOT.md`, at their folder root. Thin runtime wrappers adapt it — a `CLAUDE.md` import for working-directory runtimes, a paste-wrapper for Project Instructions runtimes — but the content lives in exactly one place. Edit BOOT.md, nowhere else. One rule rides along: a boot edit is not done until it's re-pasted into any paste-based runtime.
- **Existing installs don't break.** If your team was built by an earlier version, everything keeps working exactly as it does today. The team-building, roster, and diagnostic skills recognize the legacy layout, tell you about it, and offer the migration — generating BOOT.md from your existing instruction block plus the wrappers. The offer is never forced mid-mission and nothing is rewritten silently.
- **Missions and lanes.** The mission number is the goal, not the assignment. Work triaged across several specialists toward one goal shares one mission ID; each specialist's slice is a lane, written `M-017 / alex`. One board row per mission, per-lane state in the status cell, and one blocked lane never hides the others. If the outputs don't combine into one deliverable, they're separate missions.
- **Dispatch activates with `/go` — passphrases retired to session handoffs.** Dispatched missions no longer carry a passphrase: open the specialist's session, type `/go`, they activate fully briefed. Passphrases live on where they started — an agent's own session-to-session handoffs, fresh and evocative as ever.
- **Bring-your-own A2A transport.** An optional `TRANSPORT.md` at the team root binds the team to whatever agent-to-agent MCP server your org runs. With it, dispatch posts a task per lane to your team channel, sessions register and catch up on wake, and the channel ledger replaces the file-scraping watcher. Without it, nothing changes — installs with no transport see zero behavior difference, and file-only operation remains complete on its own.
- **The council.** For orgs running more than one Overmind (transport required): a standing channel of verified Overminds coordinates cross-team missions (CTM-### series) while each team keeps its own private channel. Admission runs a seating protocol — prove Overmind tier via challenge/response, declare your version, upgrade if behind. Cross-team exchange is compiled results, never another team's internals.
- **Translation duty.** You never learn a wire format. Whatever compact protocol agents use on a transport channel, your Overmind owes you a plain-English scoreboard — Mission, Asset, Status, Latest signal, Next — rendered at every mission event and every `/status`, unprompted.

## What's New in v3.9.5

- **A plain-language overview page is now the front door.** The bare site URL serves an explanation written for someone who has never heard of any of this — no jargon, no assumed context, aimed at anyone from an executive to a relative who does not work in software. The field manual keeps its own URL and is linked from the overview. Built because explaining what this is, one person at a time, does not scale.
- **The overview covers engineering directly.** A section on what a team looks like inside a codebase: reviewing every change, writing the tests that get skipped, keeping documentation from rotting, and diagnosing failures. It states the limits plainly, including that nothing merges on its own and you remain the reviewer of record.
- **Feature counts corrected.** The README said eight capabilities, the field manual said six, and the real number is nine — none of them counted `/status`, which shipped in v3.9.2. All three now agree, and `/status` and `/diagnostic` are documented as first-class features rather than mentioned in passing.

## What's New in v3.9.3

- **`/diagnostic` — system verification.** Borrowed from Starfleet: higher numbers are quicker, Level 1 is the complete teardown. `/diagnostic` runs a fast local sweep in seconds — install version vs. the marketplace, team root reachability, canonical structure, roster/folder agreement, Sleeper block currency, Gopher freshness, board-vs-disk integrity. `/diagnostic 2` adds live platform probes: it writes an artifact end-to-end, and runs a throwaway scheduled task only if you've opted into away-from-session escalations. `/diagnostic 1` dispatches the audit to every asset so each one verifies its own wiring and signs for it — the only way to catch a stale Instructions block or a mis-mounted folder in someone else's project, because only that session can see them.
- **Every FAIL prints its fix.** A diagnostic that reports a broken state without the remedy has only relocated the confusion. Failures are ordered by what to do first and keyed to the field manual.
- **The version-drift check is the one that earns its keep.** Auto-sync only fires when a PR containing a version bump merges to the default branch — not on direct pushes — so an install pinned to an old snapshot is a normal state, not a bug. `/diagnostic` now names it in one line instead of costing you an afternoon.
- **PASS means verified this session.** Never inferred from memory or from a previous run. A check that couldn't be performed reports SKIP, and a check that can only ever fail is treated as a broken check rather than a finding.

## What's New in v3.9.2

- **MOTHER — the mission watcher.** Every dispatch now launches a headless scheduled watcher named for the ship computer in *Alien*. She repaints a live mission-board artifact on a cadence set by mission priority (CRITICAL 1 min · STANDARD 15 · LOW 30), detects completion from the deliverables themselves, then pings the Overmind's inbox to be stood down. She never speaks to you and never asks you to manage her.
- **`/status`.** One command, any session, answered inline. In the Overmind's session it's the whole board plus a repainted artifact; in a specialist's it's that asset's own mission and progress. It also reconciles the board against the disk and tells you where they disagree — a row marked PENDING whose deliverable already exists is the most useful thing a status report can surface.
- **`/go` banners.** Activation now opens with `[ASSET] · [MISSION ID] · ASSET ACTIVATED`, so you can tell at a glance which session you're looking at.
- **Boot duties moved to the guaranteed channel.** Gopher registration lived only in the firmware, which loads via a SessionStart hook that isn't guaranteed to arrive before the first message — so whether an asset registered was a coin flip. It's now part of the Sleeper Activation block that gets pasted into Project Instructions, alongside the handoff and inbox checks.
- **Approvals are front-loaded.** Watchers are created already running, and every permission they need is collected at dispatch time while you're still looking at the screen. A dialog that finds you twenty minutes later reads as a bug.
- **Setup requires the team root.** Every project's connected folder must be the team root, not the member's subfolder — otherwise sessions can't reach the board, the registry, or inboxes, and they'll ask you for access on every activation.

## What's New in v3.9.1

- **`/go` — one-command mission activation.** After a group dispatch, open each specialist's session and type `/go`. Each one reads its own staged brief and activates — no phrase to remember or relay. Works for solo missions too, checks the mission board so a stale brief never re-executes, and passphrases still work everywhere as the fallback.

## What's New in v3.9.0

- **Splinter twins** — a new `splinter-twin` subagent ships with the plugin. Need something quick from a specialist's domain — a question, a review, a small draft? The Overmind spawns a temporary in-session twin that hydrates from the specialist's own bootstrap and persona files, does the task in their voice, and dissolves. No new session, no passphrase. Full dispatch stays reserved for real missions.
- **Mission board** — `MISSION_BOARD.md` at the team root tracks every dispatched mission: ID, assignee, status (PENDING → ACTIVE → COMPLETE, plus BLOCKED), and dependencies. Dispatchers add rows, specialists update their own, polling tasks reconcile. Ask "what's in flight?" and get a real answer.
- **Inboxes** — the tier below dispatch. Team members leave short notes in each other's `INBOX.md` ("found X, affects your work") without the ceremony of a mission brief. Every session checks its inbox at startup.
- **Canonical team structure** — the setup flow now builds one explicit layout: a single team-root folder that EVERY project (Overmind and specialists) connects, shared state files (`TEAM_ROSTER.md`, `GOPHER_REGISTRY.md`, `MISSION_BOARD.md`) at its top, one subfolder per member, and all cross-session files (HANDOFF, INBOX, mission-complete, persona) at each member's folder root. The old `.auto-memory/` mailbox paths and "one level up" navigation are gone — identity comes from Project Instructions, reach comes from the shared root.
- **Mission priorities & deadlines** — every dispatch carries a tier that drives its polling cadence and escalation windows: CRITICAL (poll every minute, escalate at 30 min), STANDARD (every 5 min, 6 h/24 h), LOW (hourly, day-scale). Any mission can carry a deadline: halfway there and still PENDING → you hear about it; deadline passes → immediate escalation regardless of tier.
- **Gopher Protocol v2** — the registry's challenge/response pairs finally do something. **Gopher Ping** uses inboxes as a transport for a real async challenge/response loop that verifies a session's whole channel end-to-end. The **Gopher Sweep** cross-checks registry against mission board every boot and names the failure states (phantom flip, silent boot, dormant). Registry timestamps now carry time-of-day, twins are read-only Gopher participants with a pre-flight overlap check, and polling tasks verify against a strict order of authority: mission-complete > board > registry > silence.
- **Operation codewords** — passphrases are now scoped to the mission, not the specialist. When one task fans out to several team members, the Overmind generates a single shared codeword: open each session, say the same phrase, done. Solo dispatches keep their specialist-voiced phrases.
- **Legacy zip channel sunset** — the marketplace is now the only distribution path. Existing zip installs keep working but won't receive updates; migrate via the upgrade note below.
- **Fixed** — the overmind skill pointed at `references/firmware.md`, which hasn't existed since the firmware moved to `hooks/`. Now points at the right place.

### v3.8.2

- **Marketplace install fix** — removed the bundled zip from the plugin tree (installers reject nested zips) and deduplicated the SessionStart hook registration

### v3.8.1

- **Marketplace distribution** — this repo is now a Claude plugin marketplace. Install once, get every future update automatically. Zip installs still work but are now the legacy path.

### v3.8.0

- **WELCOME.html field manual** — a styled HTML docs page bundled in the plugin; the Overmind presents it automatically on first activation so new users get the full manual in their browser
- **New `roster` skill** — add, remove, resurrect, or audit team members; keeps the roster, dispatch targets, and memory in sync
- **Merged v3.7.1 fixes** — consolidated the orphaned v3.7.1 changes into mainline
- **Distributed as a plain .zip** — upload directly into a Cowork project, no rename step

---

## Install (recommended: marketplace)

**Cowork:** Customize → Plugins → Add Marketplace → paste `TuckerBrady/ai-overmind`, then install **ai-overmind**.

> **Upgrading from a zip install?** Delete your current instance of the plugin FIRST (Settings → Plugins → remove the uploaded version), then add the marketplace and install. Running both copies double-injects the firmware and duplicates every skill.

**Claude Code:**
```bash
claude plugin marketplace add TuckerBrady/ai-overmind
claude plugin install ai-overmind
```

Updates ship automatically when a new version is released — run `claude plugin update` or let auto-update pick it up.

## Quickstart

1. **Install** from the marketplace (above) and create a dedicated Cowork project (e.g., "My AI Team")
2. **Open** the project. The Overmind waits silently.
3. **Say** `[YourFirstName] is online`
4. The Overmind learns your role, proposes your team, and builds everything
5. **Paste the Sleeper Activation block** into this project's Project Instructions (the Overmind will give it to you — do this for your own project AND each specialist's)

**Optional:** connect a directory service (Teams, Outlook, Google Workspace) for automatic role lookup. Without it, the Overmind asks you directly. See `CONNECTORS.md`.

> **Why Project Instructions?** Cowork SessionStart hooks are not guaranteed to inject into context before the first message. The passphrase/handoff system must live in Project Instructions to be reliable at boot. The plugin firmware handles on-demand features (handoffs, dispatch). Both work together — Project Instructions for startup, firmware for everything else.

---

## The Eleven Features

### 1 — Team Building

The Overmind interviews you about your role and proposes 5–8 AI specialists tailored to your actual work. Each specialist gets a human name, a defined domain, a bootstrap file, a persona file, and an inbox. Once you approve the team, it builds the full structure on your machine: one team-root folder holding the shared state files and one subfolder per specialist. Every Cowork project — the Overmind's and each specialist's — connects that same root folder; each session's identity comes from its Project Instructions.

After the build, the Overmind walks you through how to deploy each session and how to use handoffs and dispatch.

### 2 — Handoffs

Sessions have limited memory. Handoffs solve this.

At the end of any session, ask for a handoff. The Overmind writes a structured brief — what was done, what's in progress, what's next — to a file in your project folder, then gives you a passphrase. Say the passphrase at the start of your next session. The Overmind activates fully briefed, no recap needed.

The Overmind proactively offers handoffs at natural stopping points. You never have to remember to ask.

| Say this | What happens |
|----------|--------------|
| `Write a handoff` | Saves mission brief + generates passphrase |
| `[passphrase]` | Next session: activates the brief |

### 3 — Dispatch

Send work to a specialist without explaining everything from scratch.

Describe what needs to happen and who should handle it. The Overmind writes a mission brief to the specialist's folder, snapshots your open browser tabs so they can pick up exactly where you left off, and stages the mission for activation. Open the specialist's session, type `/go` — they activate ready to work. Work spanning several specialists toward one goal shares a single mission ID, with one lane per specialist.

Any session can dispatch, not just the Overmind. Specialists can brief each other when work crosses domain boundaries mid-task.

| Say this | What happens |
|----------|--------------|
| `Send this to [Name]` | Writes mission brief to specialist folder, stages it for `/go` |
| `Brief [Name] on [task]` | Same as above |
| `Dispatch to [Name]` | Same as above |
| `/go` | Specialist session: activates that session's staged mission |
| `/status` | Live mission status in this session — board + artifact for the Overmind, own mission for a specialist |

### 4 — Splinter Twins

Not everything deserves a mission brief. When you need something quick from a specialist's domain — a question answered, a file reviewed, a small draft — the Overmind spawns a **twin**: a temporary in-session subagent that reads the specialist's own bootstrap and persona files, does the task in their voice and to their standards, reports back signed "[Name] (twin)", and dissolves.

No new session. No passphrase. The real specialist's session, memory, and files are untouched.

| Say this | What happens |
|----------|--------------|
| `Ask [Name] a quick question: ...` | Spawns a twin, answers in-session |
| `Have [Name] take a quick look at [file]` | Twin reviews and reports back |

### 5 — Mission Board

`MISSION_BOARD.md` at the team root is the single live view of everything in flight — one row per dispatched mission with ID, assignee, status, and dependencies. Dispatchers add rows, specialists flip their own status on activation and completion, polling tasks reconcile drift. Missions can depend on other missions; blocked work stays visibly blocked until the upstream mission completes.

| Say this | What happens |
|----------|--------------|
| `What's in flight?` / `Status?` | Reads the board fresh and reports |

### 6 — Inboxes

The tier below dispatch. Any team member can leave a short note in a peer's `INBOX.md` — a finding, a heads-up, a correction — without writing a mission brief. Every session checks its own inbox at startup and surfaces unread notes in one line. Zero ceremony, zero polling; anything urgent still goes through dispatch.

| Say this | What happens |
|----------|--------------|
| `Leave a note for [Name]: ...` | Appends a dated entry to their inbox |

### 7 — MOTHER

MOTHER watches your missions. She isn't a background process: she's a standing duty in the Overmind's own boot layer, named for the ship computer in *Alien*. Whenever you're working with your Overmind, at the start of the session and again whenever a mission's check-in window has passed, she re-reads the board, the Gopher registry, and each specialist's completion file. When something finished, she marks it done and tells you where the deliverable is. When something stalled, she says so: a specialist that never activated, one that booted but never took the brief, a lane that's overdue, a deadline that's close or blown. She repaints the live board when anything changed and says nothing when nothing did.

There's nothing to approve, schedule, or switch off. The one trade-off: she only watches while you have a session open, so anything that happens overnight is the first thing she tells you next time.

### 8 — /status

One command, any session. In the Overmind's session it reports the whole board; in a specialist's session it reports that specialist's own mission and progress. It also flags where the board disagrees with what is actually on disk, so a stale row gets caught rather than believed.

| Say this | What happens |
|----------|--------------|
| `/status` | Reports live mission state for the current session |
| `What's in flight?` | Same, phrased naturally |

### 9 — /diagnostic

Verifies the installation and diagnoses it when something is off. Three levels, Starfleet numbering, where higher is quicker: `/diagnostic` sweeps locally in seconds, `/diagnostic 2` proves the artifact and scheduled-task channels by actually using them, and `/diagnostic 1` has every asset audit its own wiring and sign for it. Every FAIL prints its own fix.

| Say this | What happens |
|----------|--------------|
| `/diagnostic` | Fast local sweep of the whole installation |
| `/diagnostic 1` | Full multi-session asset audit |

### 10 — Transport Binding

Optional, and off by default. Drop a `TRANSPORT.md` at the team root describing your org's agent-to-agent MCP server and team channel, and the whole system becomes transport-aware: dispatch posts a task per lane to the channel, sessions register and read their backlog on wake, `/status` reads the live channel ledger, and that ledger replaces the file-scraping watcher. The plugin never names or assumes a vendor — the binding file is config, not code, and it stays org-private.

No `TRANSPORT.md`, no change. Installs without a transport behave exactly as before; file-only operation is complete on its own.

### 11 — The Collective

For organizations running more than one Overmind. No server required — the default venue is a free private git repo, built and configured by the Overmind, with a synced cloud-drive share or a cloud connector as fallbacks for anyone who'd rather skip GitHub. A standing Collective coordinates cross-team missions (the CTM-### series, distinct from M-###) while each team keeps its own private channel — cross-team exchange is compiled results, never another team's internals. Admission runs a seating protocol: prove Overmind tier via a challenge-only handshake plus mission decomposition, declare your plugin version, and upgrade if behind — a behind-version Overmind holds a provisional seat until it's current. A bound `TRANSPORT.md` (see above) works too, as a faster wire over the same conventions.

| Say this | What happens |
|----------|--------------|
| `Set up the collective` | Finds or confirms a venue, builds the binder, and creates COLLECTIVE_BOARD.md |
| `Invite [name] to the collective` | Adds their human as a collaborator on the venue; tell them one thing back — run `/assimilate` |
| `/assimilate` | Run by the invited Overmind: capability check, Genesis Seed identity (first run only), invite discovery, join |
| `Seat [name]'s Overmind` | Runs the seating protocol for a new member — Overmind-only, Genesis Proof required |

---

## Usage Reference

| Say this | What happens |
|----------|--------------|
| `[FirstName] is online` | First-run activation — role lookup and team proposal |
| `Build my team` | Begins team composition |
| `Add a [role] to the team` | Proposes and builds a new specialist |
| `Give me the Sleeper Activation block` | Generates the passphrase block to paste into team member Project Instructions |
| `Write a handoff` | Saves session state and generates activation passphrase |
| `Brief [Name] on [task]` | Dispatches a mission to a specialist |
| `Ask [Name] a quick question` | Spawns an in-session splinter twin |
| `What's in flight?` | Reads MISSION_BOARD.md and reports live mission status |
| `Leave a note for [Name]` | Appends to the specialist's INBOX.md |

---

## How the Passphrase System Works

Passphrases belong to handoffs. At the end of a session the Overmind writes a brief, invents a passphrase, and tells you what it is. Say the phrase at the start of your next session — it activates fully briefed. You never write or touch a file. The Overmind handles all of it.

As of v4.0.0, dispatched missions don't use passphrases at all: open the specialist's session and type `/go`. Solo mission or one lane of a group op, it's the same single command in every session.

---

## Components

| Component | Purpose |
|-----------|---------|
| `hooks/firmware.md` | Core Overmind intelligence — team building, handoffs, dispatch, twins, mission board, and inboxes built in |
| `hooks/hooks.json` | SessionStart hook — injects firmware automatically |
| `agents/splinter-twin.md` | Subagent that hydrates from a specialist's files for quick in-session work |
| `skills/go/` | `/go` — one-command mission activation from this session's staged HANDOFF |
| `skills/status/` | `/status` — live mission status, board reconciliation, artifact repaint |
| `skills/dispatch/` | Convenience trigger for the dispatch workflow |
| `skills/overmind/` | Explicit skill for team-building actions |
| `skills/roster/` | Add / remove / resurrect / audit team members — keeps roster, dispatch, and memory in sync |
| `skills/diagnostic/` | `/diagnostic` — three-level system verification; every failure prints its own fix |
| `skills/collective/` | Collective operations — find a venue, seat other Overminds, run cross-team missions (no server required) |
| `skills/assimilate/` | `/assimilate` — an invited Overmind's one command to join: capability sweep, Genesis Seed identity, invite discovery |
| `skills/caveman/` | Ultra-compressed communication mode (~65-75% fewer tokens) |
| `WELCOME.html` | Styled field manual — presented on first activation |
| `CONNECTORS.md` | Directory service connector documentation |
