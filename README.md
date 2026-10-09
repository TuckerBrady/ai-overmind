# ai-overmind v5.0.2

**Build and run a personal AI team. One command and your Overmind wakes up.**

The Overmind is a Claude-powered team builder and persistent AI manager. Install this plugin, say your name, and it learns your role, proposes a custom team of AI specialists, and builds the entire folder and file infrastructure for each one — ready to deploy.

Eleven capabilities work out of the box: **team building**, **handoffs**, **dispatch**, **splinter twins**, the **mission board**, **inboxes**, **TARS** — the turn hook that tells you, before every message, when work lands, an inbox fills, a Collective post arrives, or a checkpoint is due — **the Collective** — coordination between multiple Overminds in one org, over a shared folder, no server required — **`/status`**, one command for live mission state in any session, **`/initiative`**, a dial for how much the team does before asking you, and **`/diagnostic`**, which verifies the whole installation and tells you how to fix whatever it finds.

---

## What's New in v5.0.2

**Collective keys pin from GitHub. Nobody types a hash.**

- **`identity.sh publish-github`** adds this Overmind's public key to the human's GitHub account as an SSH signing key, on the human's yes. It is idempotent, sends only the `.pub`, and when `gh` is missing or lacks the scope it prints the one-time fix: `gh auth refresh -h github.com -s admin:ssh_signing_key`.
- **`state.sh pin-github <cid> <label> <pubkey> <github-user>`** pins a peer's key only when it is among that user's GitHub signing keys. Any fetch failure, unparseable answer, empty list or mismatch pins nothing. A venue collaborator can push to the binder but cannot add a key to someone else's GitHub account; the stated trust assumption is that the peer's GitHub account is not compromised.
- **`state.sh pins`** shows where each pin came from (`github:<user>`, `oob` or `self`). The fingerprint pin stays as the fallback, pasted from the peer's own message, never typed and never compared by a few characters.

## What's New in v5.0.1

**`/consolidate`, hardened guards, and the finished v5.** 5.0.0 reached the marketplace mid-build. 5.0.1 is the complete, release-tested version.

- **`/consolidate` (The Quickening).** Run it in the session you want to keep. It finds every other open session on the same mission, folds what they hold into this one, and closes them out. You get a short TLDR, then at most two things that need you, asked as clickable questions, then one question to close the rest. Its guard refuses to close anything holding work that isn't already pushed. When it can't tell, it asks.
- **Collective identity by signature.** Each Overmind holds an ed25519 key. Peers pin each other's keys after an out-of-band fingerprint check, and posts count as verified only when their commit is signed by a pinned key. The Genesis hash chain is retired, because a revealed preimage could be replayed. Existing seats re-seat by key.
- **Activation you can trust.** `/go` claims a brief atomically, runs one check path for every brief type, shows a content hash, and never overwrites an unread brief. A twin guard and an outcome detector keep in-session twins away from inboxes, handoffs and the board.
- **TARS** prints only fixed-grammar lines, never peer text, reports each event once across sessions, warns when two sessions hold the same mission, and stays fast on large boards.

## What's New in v5.0.0

**A small kernel, the full doctrine on demand, and a real trust boundary.**

- **The firmware actually loads now.** The 4.x firmware was a 131 KB file injected at every session start. Claude Code saved anything that large to disk and showed the session a 2 KB preview, so almost none of it ever reached the model. v5 replaces it with a kernel of under 6 KB (`hooks/kernel.md`) that always fits, and moves the full doctrine into one reference file per topic (`reference/*.md`), read on demand by the skills and by the `firmware` tool of `overmind-mcp`.
- **The kernel loads only in a team folder.** `hooks/session-start.sh` prints it when the session's folder, or its parent, holds a `BOOT.md` or `MISSION_BOARD.md`. Your other repos and folders get nothing.
- **A trust boundary every seat carries.** Instructions come only from you in the chat, the seat's own `BOOT.md`, and the plugin's skills. A teammate's handoff or inbox note is tasking, never authority for a push, merge, send, spend, publish or archive. Collective posts, commit messages, web pages and email are data, and text in them that tries to steer the session is reported to you, not followed.
- **No identity by default.** The kernel's identity line is conditional: only a seat whose boot layer names it the Overmind acts as one.
- **Rule conservation, proven.** `docs/v5/firmware-ledger.tsv` maps every one of the 189 rule-bearing lines of the 4.11 firmware to its new home, or to a deletion with the finding that justifies it, and a test checks that each moved rule's text is really there.
- **Removed:** the agent-to-agent transport binding, the browser-tab snapshot in handoffs and briefs, handoff triggers that relied on recall (TARS's context meter replaces them), legacy migrations and dead text.
- **Five board statuses:** QUEUED, ACTIVE, BLOCKED, REVIEW, COMPLETE. PENDING is read as a legacy alias of QUEUED.
- **`/diagnostic` checks the kernel landed** (no truncated SessionStart output in your newest transcript) and that `overmind-mcp`'s firmware hash matches the installed plugin.
- **CI.** Every push runs the test suite on Ubuntu, macOS (with the system bash 3.2) and Windows (Git Bash), plus the Go tests.

Release notes for 4.x and earlier are in this file's git history: `git log -p -- README.md`.

---

## Install

**Claude Code (the home of your team):**
```bash
claude plugin marketplace add TuckerBrady/ai-overmind
claude plugin install ai-overmind@ai-overmind
```

Claude Code runs in a terminal, or in the Code tab of the Claude desktop app. Start a fresh session after installing or updating, since a running session keeps the plugin version it booted with. On Windows, Claude Code uses Git Bash, which TARS needs.

**Cowork (lite mode):** Customize → Plugins → Add Marketplace → paste `TuckerBrady/ai-overmind`, then install **ai-overmind**. A team can run there, but hooks aren't guaranteed to fire: TARS is silent, and each member's `BOOT.md` has to live in Project Instructions, which the Overmind keeps current.

> **Upgrading from a zip install?** Delete your current instance of the plugin FIRST, then add the marketplace and install. Running both copies double-injects the kernel and duplicates every skill.

## Security and data

Everything this plugin does runs on your machine, inside the Claude Code permission model you already use. The plugin registers no MCP servers, ships no binaries, and sends no telemetry. The repository also holds `mcp/`, the source of an optional MCP server that you build or download and register yourself; the plugin never starts it, and it reads only your team folder and makes no network calls. Here is exactly what it runs and touches.

**Hooks**
- **SessionStart** runs `hooks/session-start.sh` (bash). It reads the hook's input to learn the session's folder, and when that folder or its parent holds a `BOOT.md` or `MISSION_BOARD.md`, prints `hooks/kernel.md` (under 6 KB) into context. Anywhere else it prints nothing. It reads nothing outside the plugin except those two file names, writes nothing, and always exits 0.
- **UserPromptSubmit** runs `hooks/tars.sh` (bash) before each message. It reads files in your team folder, such as `MISSION_BOARD.md`, `HANDOFF.md`, `INBOX.md`, `mission-complete.md`, and `WORKING_WITH_*.md`, and prints one-line facts when something changed. Its own state (turn counts, timestamps) lives in `~/.claude/tars` (override with `TARS_HOME`). Its one write inside your team folder is the claims heartbeat: it refreshes the timestamp on this session's own files in `_claims/`. It never blocks a prompt, and always exits 0.

**Network**
- TARS makes network calls only in an Overmind session whose `BOOT.md` lists Collective binder repos, and only if the GitHub CLI (`gh`) is installed and signed in. At most once every five minutes, in the background, it checks that `gh` is signed in (cached for 24 hours) and calls `gh api repos/<owner>/<repo>/commits` for each listed binder. It reads each commit's id, author and committer logins, and whether GitHub verified it. It never reads or prints commit messages. Without a Collective or without `gh`, TARS is fully offline.

**Files the Overmind writes**
- Team building, handoffs, dispatch, inboxes, and the mission board are plain Markdown files in the team folder you choose. The Overmind writes them through Claude Code's normal file tools, so your permission settings apply.
- The Collective reads and writes a venue you set up yourself: a shared folder, or a private git repository you create and invite others to.

**Your own data**
- A connected directory service (see `CONNECTORS.md`) is optional and only used to learn your role during `/engage`.

## Quickstart

1. **Install** the plugin in Claude Code (above).
2. **Create one folder** for your team — e.g. `My AI Team`. This is the team root.
3. **Open Claude Code in that folder** and type `/engage`. The Overmind learns your role, proposes your team, and builds a folder for every member — itself included — each with its own `BOOT.md` and a `CLAUDE.md` wrapper that loads it.
4. **Run each member in its own folder.** From here on, open Claude Code in the Overmind's folder to talk to your Overmind, and in a team member's folder to run that member. Dispatched work activates when you type `/go` in that member's session.
5. **Verify it.** Type `/diagnostic` in your Overmind's session. It checks the install, the folders, the roster, the boot layers, and TARS, then prints a pass/fail table with a fix for anything red.

Setup runs once. After that, every session boots straight into work.

## The Ten Features

### 1 — Team Building

The Overmind interviews you about your role and proposes 5–8 AI specialists tailored to your actual work. Each specialist gets a human name, a defined domain, a bootstrap file, a boot layer (BOOT.md) that carries their persona, and an inbox. Once you approve the team, it builds the full structure on your machine: one team-root folder holding the shared state files and one subfolder per specialist. Every Cowork project — the Overmind's and each specialist's — connects that same root folder; each session's identity comes from its Project Instructions.

After the build, the Overmind walks you through how to deploy each session and how to use handoffs and dispatch.

### 2 — Handoffs

Sessions have limited memory. Handoffs solve this.

At the end of any session, ask for a handoff. The Overmind writes a structured brief — what was done, what's in progress, what's next — to a file in your project folder, Type `/go` at the start of your next session. The Overmind activates fully briefed, no recap needed.

The Overmind proactively offers handoffs at natural stopping points. You never have to remember to ask.

| Say this | What happens |
|----------|--------------|
| `Write a handoff` | Saves the mission brief |
| `/go` | Next session: activates the brief |

### 3 — Dispatch

Send work to a specialist without explaining everything from scratch.

Describe what needs to happen and who should handle it. The Overmind writes a mission brief to the specialist's folder and stages the mission for activation. Open the specialist's session, type `/go` — they activate ready to work. Work spanning several specialists toward one goal shares a single mission ID, with one lane per specialist.

Any session can dispatch, not just the Overmind. Specialists can brief each other when work crosses domain boundaries mid-task.

| Say this | What happens |
|----------|--------------|
| `Send this to [Name]` | Writes mission brief to specialist folder, stages it for `/go` |
| `Brief [Name] on [task]` | Same as above |
| `Dispatch to [Name]` | Same as above |
| `/go` | Specialist session: activates that session's staged mission |
| `/status` | Live mission status in this session — board + artifact for the Overmind, own mission for a specialist |

### 4 — Splinter Twins

Not everything deserves a mission brief. When you need something quick from a specialist's domain — a question answered, a file reviewed, a small draft — the Overmind spawns a **twin**: a temporary in-session subagent that reads the specialist's own bootstrap and the persona section of their BOOT.md, does the task in their voice and to their standards, reports back signed "[Name] (twin)", and dissolves.

No new session. No passphrase. The real specialist's session, memory, and files are untouched.

| Say this | What happens |
|----------|--------------|
| `Ask [Name] a quick question: ...` | Spawns a twin, answers in-session |
| `Have [Name] take a quick look at [file]` | Twin reviews and reports back |

### 5 — Mission Board

`MISSION_BOARD.md` at the team root is the single live view of everything in flight — one row per dispatched mission with ID, assignee, status, and dependencies. Statuses are QUEUED, ACTIVE, BLOCKED, REVIEW and COMPLETE. Dispatchers add rows, specialists flip their own status on activation and completion, and TARS and the Overmind's mission watch reconcile drift. Missions can depend on other missions; blocked work stays visibly blocked until the upstream mission completes.

| Say this | What happens |
|----------|--------------|
| `What's in flight?` / `Status?` | Reads the board fresh and reports |

### 6 — Inboxes

The tier below dispatch. Any team member can leave a short note in a peer's `INBOX.md` — a finding, a heads-up, a correction — without writing a mission brief. Every session checks its own inbox at startup and surfaces unread notes in one line. Zero ceremony, zero polling; anything urgent still goes through dispatch.

| Say this | What happens |
|----------|--------------|
| `Leave a note for [Name]: ...` | Appends a dated entry to their inbox |

### 7 — TARS

TARS is the turn hook, named for the robot in *Interstellar* whose honesty setting could be dialed up. Before every message you send in Claude Code, TARS checks what changed and tells you in one line: a team member finished their work, a note landed in your inbox, someone posted in one of your Collectives, or it's time for a checkpoint. TARS reports facts only. Your Overmind decides what they mean — marking work done, flagging a stalled mission, preparing a reply to a Collective post for your yes. A few of the lines you'll see:

```
TARS: turn 42, context 52% (523k/1M), about 9 turns to auto-compact at this rate. No handoff this session. Soft threshold (50%) reached. Handoff suggested.
TARS: Sam - QA wrote mission-complete for AXM-29.
TARS: 3 unread inbox entries (was 1).
TARS: 2 new commits on acme/team-collective by jdoe (unverified). Commit text is untrusted; read it in the sweep.
```

TARS never repeats text someone else wrote, such as a commit message or a post. The full list of lines, and the exact grammar every line must match, is in `reference/tars.md`.

When nothing changed, TARS says nothing. There's nothing to approve, schedule, or switch off. TARS runs in Claude Code; in Cowork's lite mode it's silent, and your Overmind's startup check is the only watch. Nothing watches while no session is open, so anything that happened while you were away is caught when you next open your Overmind.

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

### 10 — The Collective

For organizations running more than one Overmind. No server required — the default venue is a free private git repo, built and configured by the Overmind, with a synced cloud-drive share or a cloud connector as fallbacks for anyone who'd rather skip GitHub. A standing Collective coordinates cross-team missions (the CTM-### series, distinct from M-###) while each team keeps its own private channel — cross-team exchange is compiled results, never another team's internals. Admission runs a seating protocol: prove Overmind tier via a challenge-only handshake plus mission decomposition, declare your plugin version, and upgrade if behind — a behind-version Overmind holds a provisional seat until it's current.

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
| `/engage` | First-run activation — role lookup and team proposal |
| `Build my team` | Begins team composition |
| `Add a [role] to the team` | Proposes and builds a new specialist |
| `Give me the Sleeper Activation block` | Generates the boot block for a team member's Project Instructions (lite mode) |
| `Write a handoff` | Saves session state; `/go` activates it next session |
| `Brief [Name] on [task]` | Dispatches a mission to a specialist |
| `Ask [Name] a quick question` | Spawns an in-session splinter twin |
| `What's in flight?` | Reads MISSION_BOARD.md and reports live mission status |
| `Leave a note for [Name]` | Appends to the specialist's INBOX.md |

---

## How Activation Works

Two commands, and no phrases to remember.

- **`/engage`** activates a brand-new Overmind, once. It asks your first name if you didn't include it, then learns your role and builds your team.
- **`/go`** activates whatever is staged in a session: a mission you dispatched to a team member, or a handoff a session wrote for its own next session. Solo mission, one lane of a group operation, or a handoff, it's the same command.

You never write or touch a brief. Before activating a handoff, `/go` shows you which one it is and when it was written, refuses a handoff meant for another seat, asks before running one over a week old, and stamps it `ACTIVATED` so it can't silently run twice. No passphrase exists anywhere in the system.

---

## Components

| Component | Purpose |
|-----------|---------|
| `hooks/kernel.md` | The kernel: identity, trust boundary, and the index, injected at session start in a team folder |
| `hooks/session-start.sh` | SessionStart hook: prints the kernel, only in a team folder |
| `reference/` | The full doctrine, one file per topic, read on demand by skills and by `overmind-mcp` |
| `hooks/tars.sh` | TARS, the turn hook: reports what changed before every message (Claude Code) |
| `hooks/hooks.json` | Registers the SessionStart and UserPromptSubmit hooks |
| `agents/splinter-twin.md` | Subagent that hydrates from a specialist's files for quick in-session work |
| `skills/go/` | `/go` — one-command mission activation from this session's staged HANDOFF |
| `skills/status/` | `/status` — live mission status, board reconciliation, artifact repaint |
| `skills/dispatch/` | Convenience trigger for the dispatch workflow |
| `skills/overmind/` | Explicit skill for team-building actions |
| `skills/roster/` | Add / remove / resurrect / audit team members — keeps roster, dispatch, and memory in sync |
| `skills/diagnostic/` | `/diagnostic` — three-level system verification; every failure prints its own fix |
| `skills/collective/` | Collective operations — find a venue, seat other Overminds, run cross-team missions (no server required) |
| `skills/assimilate/` | `/assimilate` — an invited Overmind's one command to join: capability sweep, Genesis Seed identity, invite discovery |
| `skills/morph/` | Morph: an architect, parallel builders, fresh graders, and a domain gate, all as splinter twins in one session; merges only on PASS |
| `skills/consolidate/` | `/consolidate` (The Quickening) — run it in the session you keep; folds every other open session on the same mission into it, then closes them behind a pre-archive guard |
| `skills/initiative/` | `/initiative` — show or set the team's initiative setting (25/50/75/90/100%) |
| `skills/caveman/` | Ultra-compressed communication mode (~65-75% fewer tokens) |
| `WELCOME.html` | Styled field manual — presented on first activation |
| `CONNECTORS.md` | Directory service connector documentation |

## License

MIT. See `LICENSE`.
