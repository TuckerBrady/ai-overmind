# ai-overmind v2.0

**Build and run a personal AI team. One phrase and your Overmind wakes up.**

The Overmind is a Claude-powered team builder and persistent AI manager. Install this plugin, say your name, and it learns your role, proposes a custom team of AI specialists, and builds the entire folder and file infrastructure for each one — ready to deploy.

Three capabilities work out of the box: **team building**, **handoffs**, and **dispatch**.

---

## Quickstart

1. **Rename** `ai-overmind.plugin` → `ai-overmind.zip`
2. **Install** the plugin into a dedicated Cowork project (e.g., "My AI Team") by uploading the .zip file
3. **Open** the project. The Overmind waits silently.
4. **Say** `[YourFirstName] is online`
5. The Overmind learns your role, proposes your team, and builds everything
6. **Paste the Sleeper Activation block** into this project's Project Instructions (the Overmind will give it to you — do this for your own project AND each specialist's)

**Optional:** connect a directory service (Teams, Outlook, Google Workspace) for automatic role lookup. Without it, the Overmind asks you directly. See `CONNECTORS.md`.

> **Why Project Instructions?** Cowork SessionStart hooks are not guaranteed to inject into context before the first message. The passphrase/handoff system must live in Project Instructions to be reliable at boot. The plugin firmware handles on-demand features (handoffs, dispatch). Both work together — Project Instructions for startup, firmware for everything else.

---

## The Three Features

### 1 — Team Building

The Overmind interviews you about your role and proposes 5–8 AI specialists tailored to your actual work. Each specialist gets a human name, a defined domain, a bootstrap file, and a persona file. Once you approve the team, it builds the full folder structure on your machine — one folder per specialist, ready to become a Cowork project.

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

---

## How the Passphrase System Works

Everything runs on passphrases. The Overmind writes a brief, invents a passphrase, and tells you what it is. You say the phrase to the right session — it activates fully briefed. You never write or touch a file. The Overmind handles all of it.

---

## Components

| Component | Purpose |
|-----------|---------|
| `hooks/firmware.md` | Core Overmind intelligence — team building, handoffs, and dispatch built in |
| `hooks/hooks.json` | SessionStart hook — injects firmware automatically |
| `skills/dispatch/` | Convenience trigger for the dispatch workflow |
| `skills/overmind/` | Explicit skill for team-building actions |
| `CONNECTORS.md` | Directory service connector documentation |
