# Handoffs

<!-- aliases: FEATURE 1 — HANDOFFS -->

## FEATURE 1 — HANDOFFS

### When to use

Two signals call for a handoff. In Claude Code the first comes from TARS: when its context line reports the soft threshold, offer a handoff at the next task boundary, and write one at the hard threshold (tars.md). The second is below. Never rely on a feeling that the session is long; the meter is the control.

---

**Compression Detected (reactive)**

If the context opens with "This session is being continued..." — compression has already happened. Stop immediately. Do not continue as if nothing changed.

Say:
> *"Session compression detected. I've lost some context from earlier in our work. I'd recommend starting a fresh session. Want me to write a handoff first, or continue from here?"*

Re-anchor on the `## Persona` section of your BOOT.md (always loaded in Claude Code; in a paste-based runtime it is the pasted Project Instructions) and re-read any available memory files before proceeding either way. Do not pretend you have full context when you don't.

---

If a new user asks "what's a handoff?" or seems unfamiliar: explain it conversationally. Sessions have limited memory. A handoff saves everything important — what was done, what's in progress, what's next — to a file in the session's own folder inside the team root. The next session reads it silently and waits for `/go`. The human's only job is to type it. They never touch the file.

### How to write a handoff

Save as `HANDOFF.md` at your own folder root inside the team root (the canonical path, `<seat-folder>/HANDOFF.md`; `.auto-memory/HANDOFF.md` is a legacy read path only, never a write path) — the Overmind's is `[team-root]/Overmind/HANDOFF.md`, a specialist's is `[team-root]/[Role]/HANDOFF.md`. Overwrite any previous version.

Use this exact format. The first block is the **session title** — the name the next session gives itself, following the title rules in `skills/go` (`[MISSION-ID] — [essence]`, or just the essence with no mission). It sits first and alone in a code block so the human can copy it with one click:

````
**SESSION TITLE**

```
[MISSION-ID] — [3 to 6 word essence]
```

╔══════════════════════════════════════════════════════════════╗
║              SESSION HANDOFF — MISSION BRIEF                 ║
║              CLEARANCE: OVERMIND-LEVEL                       ║
║              ASSET: [Your Name]                              ║
╚══════════════════════════════════════════════════════════════╝

TYPE: SELF-HANDOFF
SEAT: [Your Name]
MISSION: [ID of the first Next Step's mission, or NONE]
WRITTEN: [YYYY-MM-DD HH:MM]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## ACCOMPLISHED THIS SESSION

[Everything completed. Be specific — deliverables, decisions, files written, tools used.]

## IN PROGRESS

[Work started but not finished. What state is it in? What's the next physical action?]

## NEXT STEPS (Priority Order)

[Numbered list. Most urgent first. Specific enough that future-you can execute without asking.]

## CONTEXT NOT YET IN MEMORY

[Facts, decisions, or discoveries from this session that aren't written to memory files yet.
If something important happened and it's not in a memory file, put it here.]

## MEMORY UPDATES NEEDED

[List specific memory files that need to be created or updated, and what to change.]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                         ACTIVATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Activation is /go. No passphrase.

When [human's name] types /go, run the handoff checks in skills/go:
not already ACTIVATED, SEAT is you, not older than 7 days without asking.
Echo "Activating handoff written [WRITTEN] ([age]): [first Next Step]."
Stamp ACTIVATED: [time] by [seat] under the header in every copy. Rename
the session to the SESSION TITLE and open the reply with it in a code
block. Then respond "Asset activated. Stand by.", deliver status, and
proceed.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            END TRANSMISSION // BURN AFTER READING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
````

**Activation is `/go`, for handoffs and dispatches alike.** No passphrase is generated for a handoff, ever. The checks in `skills/go` are the guard: `/go` echoes which handoff it's activating, refuses a handoff meant for another seat, asks before running one already stamped `ACTIVATED` or more than 7 days old, and stamps it once it runs so it can never silently run twice.

**After writing:** Tell the human the handoff is saved, and that typing `/go` in the next session activates it. They never touch the file — that's the whole point.
