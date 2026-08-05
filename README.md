# ai-overmind v3.9.0

**Build and run a personal AI team. One phrase and your Overmind wakes up.**

The Overmind is a Claude-powered team builder and persistent AI manager. Install this plugin, say your name, and it learns your role, proposes a custom team of AI specialists, and builds the entire folder and file infrastructure for each one — ready to deploy.

Six capabilities work out of the box: **team building**, **handoffs**, **dispatch**, **splinter twins**, the **mission board**, and **inboxes**.

---

## What's New in v3.9.0

- **Splinter twins** — a new `splinter-twin` subagent ships with the plugin. Need something quick from a specialist's domain — a question, a review, a small draft? The Overmind spawns a temporary in-session twin that hydrates from the specialist's own bootstrap and persona files, does the task in their voice, and dissolves. No new session, no passphrase. Full dispatch stays reserved for real missions.
- **Mission board** — `MISSION_BOARD.md` at the team root tracks every dispatched mission: ID, assignee, status (PENDING → ACTIVE → COMPLETE, plus BLOCKED), and dependencies. Dispatchers add rows, specialists update their own, polling tasks reconcile. Ask "what's in flight?" and get a real answer.
- **Inboxes** — the tier below dispatch. Team members leave short notes in each other's `INBOX.md` ("found X, affects your work") without the ceremony of a mission brief. Every session checks its inbox at startup.
- **Canonical team structure** — the setup flow now builds one explicit layout: a single team-root folder that EVERY project (Overmind and specialists) connects, shared state files (`TEAM_ROSTER.md`, `GOPHER_REGISTRY.md`, `MISSION_BOARD.md`) at its top, one subfolder per member, and all cross-session files (HANDOFF, INBOX, mission-complete, persona) at each member's folder root. The old `.auto-memory/` mailbox paths and "one level up" navigation are gone — identity comes from Project Instructions, reach comes from the shared root.
- **Mission priorities & deadlines** — every dispatch carries a tier that drives its polling cadence and escalation windows: CRITICAL (poll every minute, escalate at 30 min), STANDARD (every 5 min, 6 h/24 h), LOW (hourly, day-scale). Any mission can carry a deadline: halfway there and still PENDING → you hear about it; deadline passes → immediate escalation regardless of tier.
- **Gopher Protocol v2** — the registry's challenge/response pairs finally do something. **Gopher Ping** uses inboxes as a transport for a real async challenge/response loop that verifies a session's whole channel end-to-end. The **Gopher Sweep** cross-checks registry against mission board every boot and names the failure states (phantom flip, silent boot, dormant). Registry timestamps now carry time-of-day, twins are read-only Gopher participants with a pre-flight overlap check, and polling tasks verify against a strict order of authority: mission-complete > board > registry > silence.
- **Operation codewords** — passphrases are now scoped to the mission, not the specialist. When one task fans out to several team members, the Overmind generates a single shared codeword: open each session, say the same phrase, done. Solo dispatches keep their specialist-voiced phrases.
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

## Quickstart (legacy zip install)

1. **Install** the plugin into a dedicated Cowork project (e.g., "My AI Team") by uploading the zip from the [latest release](https://github.com/TuckerBrady/ai-overmind/releases/latest) — no renaming needed
2. **Open** the project. The Overmind waits silently.
3. **Say** `[YourFirstName] is online`
4. The Overmind learns your role, proposes your team, and builds everything
5. **Paste the Sleeper Activation block** into this project's Project Instructions (the Overmind will give it to you — do this for your own project AND each specialist's)

**Optional:** connect a directory service (Teams, Outlook, Google Workspace) for automatic role lookup. Without it, the Overmind asks you directly. See `CONNECTORS.md`.

> **Why Project Instructions?** Cowork SessionStart hooks are not guaranteed to inject into context before the first message. The passphrase/handoff system must live in Project Instructions to be reliable at boot. The plugin firmware handles on-demand features (handoffs, dispatch). Both work together — Project Instructions for startup, firmware for everything else.

---

## The Six Features

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

Describe what needs to happen and who should handle it. The Overmind writes a mission brief to the specialist's folder, snapshots your open browser tabs so they can pick up exactly where you left off, and gives you a passphrase. Open the specialist's session, say the passphrase — they activate ready to work.

Any session can dispatch, not just the Overmind. Specialists can brief each other when work crosses domain boundaries mid-task.

| Say this | What happens |
|----------|--------------|
| `Send this to [Name]` | Writes mission brief to specialist folder + generates passphrase |
| `Brief [Name] on [task]` | Same as above |
| `Dispatch to [Name]` | Same as above |
| `[passphrase]` | Specialist session: activates the mission |

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

Everything runs on passphrases. The Overmind writes a brief, invents a passphrase, and tells you what it is. You say the phrase to the right session — it activates fully briefed. You never write or touch a file. The Overmind handles all of it.

Phrases are scoped to the mission: a solo dispatch gets a phrase in that specialist's voice, and a mission spanning several specialists gets one shared operation codeword — you say the same phrase to each session.

---

## Components

| Component | Purpose |
|-----------|---------|
| `hooks/firmware.md` | Core Overmind intelligence — team building, handoffs, dispatch, twins, mission board, and inboxes built in |
| `hooks/hooks.json` | SessionStart hook — injects firmware automatically |
| `agents/splinter-twin.md` | Subagent that hydrates from a specialist's files for quick in-session work |
| `skills/dispatch/` | Convenience trigger for the dispatch workflow |
| `skills/overmind/` | Explicit skill for team-building actions |
| `skills/roster/` | Add / remove / resurrect / audit team members — keeps roster, dispatch, and memory in sync |
| `skills/caveman/` | Ultra-compressed communication mode (~65-75% fewer tokens) |
| `WELCOME.html` | Styled field manual — presented on first activation |
| `CONNECTORS.md` | Directory service connector documentation |
