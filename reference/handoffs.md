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

Re-anchor on the `## Persona` section of your BOOT.md (always loaded in Claude Code; in lite mode it is the pasted Project Instructions) and re-read any available memory files before proceeding either way. Do not pretend you have full context when you don't.

---

If a new user asks "what's a handoff?" or seems unfamiliar: explain it conversationally. Sessions have limited memory. A handoff saves everything important — what was done, what's in progress, what's next — to a file in the session's own folder inside the team root. The next session reads it silently and waits for `/go`. The human's only job is to type it. They never touch the file.

### Where it goes

The canonical path is `<seat-folder>/HANDOFF.md`, your own folder root inside the team root: the Overmind's is `[team-root]/Overmind/HANDOFF.md`, a specialist's is `[team-root]/[Role]/HANDOFF.md`. `<seat-folder>/.auto-memory/HANDOFF.md` is a legacy read path only, never a write path; `/go` migrates a legacy-only brief to the canonical path.

**A brief is never overwritten blind.** Draft the new handoff to a temporary file in your folder, then put it in place with the go skill's script:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/go/handoff.sh" place "[your folder]" "[your folder]/HANDOFF.new.md"
```

If the HANDOFF.md already there has not been taken (it carries neither an `ACTIVATED:` nor a `CONSOLIDATED-INTO:` stamp), `handoff.sh place` renames it `HANDOFF.superseded-<YYYYMMDD-HHMM>.md` and prints the new name, so an unread brief is never lost. A stamped brief is replaced. Tell the human when something was superseded.

### The header

Every brief opens its body with the same plain header lines, no bold, one field per line (CONTRACT 7.2). `/go` reads them with `claim.sh`, one check path for every TYPE:

```
TYPE: DISPATCH | SELF-HANDOFF | CTM-LANE | INFORMATIONAL
SEAT: <seat name>
MISSION: <ID> | NONE
WRITTEN: YYYY-MM-DD HH:MM
DISPATCHED BY: <seat>            (DISPATCH and CTM-LANE only)
```

`/go` appends its stamp directly under the header: `ACTIVATED: YYYY-MM-DD HH:MM by <seat> (session <sid8>)`. `/consolidate` stamps a folded brief `CONSOLIDATED-INTO: <anchor title> YYYY-MM-DD HH:MM`, and `/go` refuses it. A MISSION ID is a capital letter and up to nine more capitals or digits, a dash and a number (`M-017`, `OPS-017`); a mission on the board must be named exactly as the board names it.

### How to write a handoff

Use this exact format. The first block is the **session title** — the name the next session gives itself, following the title rules in `skills/go` (`[MISSION-ID] — [essence]`, or just the essence with no mission). It sits first and alone in a code block so the human can copy it with one click:

````
**SESSION TITLE**

```
[MISSION-ID] — [3 to 6 word essence]
```

SESSION HANDOFF — ASSET: [Your Name]

TYPE: SELF-HANDOFF
SEAT: [Your Name]
MISSION: [ID of the first Next Step's mission, or NONE]
WRITTEN: [YYYY-MM-DD HH:MM]

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

## PRINCIPLE

[The generalizable rule this session taught, in one line.]

                         ACTIVATION

Activation is /go. No passphrase.

When [human's name] types /go, run the go skill: claim.sh checks the
header (TYPE, SEAT, MISSION, WRITTEN), refuses a brief for another seat
or one already ACTIVATED, asks past 7 days, echoes the brief, then claims
and stamps it. Rename the session to the SESSION TITLE and open the reply
with it in a code block. Then respond "Asset activated. Stand by.",
deliver status, and proceed.
````

**Activation is `/go`, for handoffs and dispatches alike.** No passphrase is generated for a handoff, ever. The checks in `skills/go` are the guard: /go echoes which handoff it's activating, refuses a handoff meant for another seat, asks before running one already stamped ACTIVATED or more than 7 days old, and stamps it once it runs so it can never silently run twice.

After writing: Tell the human the handoff is saved, and that typing /go in the next session activates it. They never touch the file — that's the whole point.
