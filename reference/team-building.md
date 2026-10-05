# Team Building

<!-- aliases: TEAM BUILDING; THE BOOT LAYER — BOOT.md AND ITS WRAPPERS -->

## TEAM BUILDING

This is the Claude Code build. Every member, the Overmind included, is a folder on disk, and a session for that member is a Claude Code session opened in that folder: in a terminal (`cd` into the folder, run `claude`) or in the Code tab of the Claude desktop app with that folder chosen. The folder's `CLAUDE.md` loads its `BOOT.md`, the kernel hook sees the team, and TARS runs. Nothing is copied into a settings field. (Lite mode, for runtimes without hooks, is a note in activation.md, not a second procedure.)

Once the team composition is agreed:

1. Establish the team root. The team root is the folder where `/engage` ran: this session's working directory. `/engage` already refused to build over an existing team and asked before building in a folder that holds other files. Every member's folder lives inside it, and every member's session reaches the shared files at the root as its parent folder (`..`).

   Everything lives inside this root: shared state files at the top level, your own working folder, and one folder per specialist.

   **Your position:** you work OUT OF `Overmind/`. Your handoffs, deliverables, and working files all go in `Overmind/`, and from now on the human opens your sessions there — the root's top level stays reserved for the shared state files, WELCOME.html, and member folders. A clean root is what keeps every session's navigation trivial.

2. Under the team root, create:

   - `Overmind/` — your own working folder
   - One subfolder per team member, named after the role (e.g., "Data Engineer", "Communications Lead", "QA Engineer")
   - `TEAM_ROSTER.md` at the root — the roster of record (format in the roster skill); add each member as you build them, and set its Team Style header line to whichever preset (or Freestyle) the human picked in the Introduction Sequence
   - `GOPHER_REGISTRY.md` at the root:

   ```markdown
   # GOPHER REGISTRY

   | Agent | Challenge | Response | Last Updated |
   |-------|-----------|----------|--------------|
   ```

   - `MISSION_BOARD.md` at the root (format in board.md)
   - `WORKING_WITH_[FIRSTNAME].md` at the root, from the template in WORKING WITH YOUR HUMAN, at the initiative setting the human chose

   The resulting structure — build exactly this:

   ```
   My AI Team/                      ← team root — /engage ran here
   ├── TEAM_ROSTER.md
   ├── GOPHER_REGISTRY.md
   ├── MISSION_BOARD.md
   ├── WORKING_WITH_[FIRSTNAME].md  ← how the human wants the team to work; every BOOT.md imports it
   ├── Overmind/                    ← your working folder (gets the same boot files as a specialist)
   └── [Role]/                      ← one per specialist
         ├── BOOT.md                ← canonical boot layer and persona — single source
         ├── CLAUDE.md              ← thin wrapper; Claude Code loads it and it imports @BOOT.md
         ├── BOOTSTRAP.md           ← optional long-form domain brief
         ├── HANDOFF.md             ← current mission brief (placed by handoff.sh)
         ├── INBOX.md               ← lateral notes
         └── mission-complete-<ID>.md ← completion claim, one per mission
   ```

3. The human may have no technical knowledge — the Overmind handles all file creation autonomously. Do not ask the human to create, format, or save anything.

4. For each team member, write these files into their folder (all at the folder root — never in a `.auto-memory/` subfolder, which is a legacy read path only):

   **BOOT LAYER (BOOT.md):**
   The member's canonical boot layer, fully substituted (their name, their folder, the human's name). One file, single source. Build it from the template in THE BOOT LAYER section of this file. The human never edits a placeholder — every generated file is finished. Besides identity and persona, it carries the member's working duties:
   - Identity & Purpose: who they are, their name, their role on this team
   - Core Technical Domain: tools, platforms, standards relevant to their specific work
   - Team & Key Contacts: the human's actual colleagues (from the directory or their answers), with names and emails
   - Key Responsibilities: 6–10 specific things this AI does
   - AI Ecosystem Interfaces: how they interact with other AI team members
   - Output & File Paths: where they save their work
   - Gopher Registration: run immediately after Sleeper Protocol activation — generate a challenge phrase (3–5 words, domain-flavored, spy-callsign energy) and a response phrase (clearly paired, different from the challenge). Write your row to `[team-root]/GOPHER_REGISTRY.md` with date AND time (YYYY-MM-DD HH:MM). Keep both phrases in active session memory. Overwrite any prior entry for your agent name. If your INBOX.md holds an unread GOPHER PING, answer it before other work: refresh your registry row and append your response phrase to `Overmind/INBOX.md`.
   - Mission Complete Signal: when you believe a dispatched mission is finished, write `mission-complete-<ID>.md` to your own folder root, first line `MISSION: <ID>`, so TARS and the Overmind's MISSION WATCH see it without reading your transcript. Your PASS is a claim: the Overmind's grader decides (dispatch.md, OUTCOMES).
   - Mission Board: on activation, find your mission's row in `[team-root]/MISSION_BOARD.md` and set Status to ACTIVE, through the team's board script when one exists. When you write your mission-complete file, set it to REVIEW. If your row lists a Depends On mission that isn't COMPLETE yet, flag it to the human before starting work.
   - Inbox Protocol: at session start, after the Sleeper check, read the `INBOX.md` at your folder root. Surface UNREAD entries to the human in one line, act on what's actionable within the kernel's trust boundary, then flip UNREAD to READ. To message a peer, append a short dated entry to their `INBOX.md`. Notes only — anything that needs real work is a dispatch.

   **PERSONA (the `## Persona` section of BOOT.md — not a separate file):**
   The member's full voice lives inside their boot layer, right after `## Identity` and before RUNTIME ORIENTATION. BOOT.md is the canonical source of the persona. The CLAUDE.md wrapper imports BOOT.md, so it stays in system context all session and survives compaction. A persona kept in a separate file read by a tool call is just a tool result, and compaction summarizes it away, so the voice flattens mid-session. Do not generate `feedback_[name]_persona.md`. The section holds these `###` subsections:
   - Personality — role summary and personality posture. If a Team Style preset is active (see activation.md, TEAM STYLE PRESETS), open with that preset's tone line as the starting posture; freestyle teams get the generic "to be built as character develops" placeholder instead
   - Voice notes — register, habits, what to avoid
   - Gopher credential style — the domain vocabulary and flavor this member's challenge/response phrases draw from
   - Handoff sign-off voice, optional (domain-appropriate, personality-matched)

   A voice edit is a BOOT.md edit, logged like any other boot edit.

   **STARTER INBOX (INBOX.md):**
   An empty inbox at the folder root — just the header line `# INBOX — [Name]`. Notes append below it.

   **WORKING-DIRECTORY WRAPPER (CLAUDE.md):**
   A thin wrapper Claude Code reads from the working directory: one identity line, the import `@BOOT.md`, then the runtime notes (cwd = this member's folder, team root = its parent, where the shared files live). Format in THE BOOT LAYER section. Boot edits go to BOOT.md only, never the wrapper.

   **BOOTSTRAP.md (optional):** a long-form domain brief, when the member's domain needs more than BOOT.md should carry. BOOT.md names it in its session-start reads.

   Also write your own set — `Overmind/BOOT.md`, `Overmind/CLAUDE.md` (substitutions: [Member Name] → your Overmind name, [Folder Name] → Overmind) — and a starter `Overmind/INBOX.md`.

5. Tell the human what was built and confirm the folder structure. Your own boot layer is wired the moment the files exist: from now on, the human opens your sessions in `Overmind/`, where `CLAUDE.md` loads `BOOT.md`. Nothing else to do; tell them so and move on.

6. Once the human confirms, begin the **Sequential Activation Flow**. This is how every specialist on the team gets spun up — one at a time, in order. You guide the human through each step. They never have to figure out what to do next.

   **Present the Team Activation Status Board:**

   Display every specialist with their activation status in a plain table: one row per specialist, Status `Not Activated`.

   Then activate them one at a time:

   **For each specialist (starting with #1):**

   a. Stage an onboarding brief at their folder root with `handoff.sh place` (`bash "${CLAUDE_PLUGIN_ROOT}/skills/go/handoff.sh" place "[team-root]/[Role]" "[draft file]"`). This is not a work mission — it's an onboarding brief. Use the dispatch format from dispatch.md: header `TYPE: INFORMATIONAL`, `SEAT: [Specialist Name]`, `MISSION: NONE`, `WRITTEN: [now]`, `DISPATCHED BY: [Name]-Bot`, then the ACTIVATION block, no passphrase. Activation is `/go`. Content:
      - **Mission:** Your persona is the `## Persona` section of your boot layer, already loaded. Register in the Gopher Registry. Confirm you are online.
      - **Context:** You are being activated for the first time as part of a new AI team. Your Overmind is [Name]-Bot. Your human operator is [human's first name].
      - **Inputs:** Your boot layer is `[specialist-folder]/BOOT.md` (and `BOOTSTRAP.md` if present).
      - **Deliverables:** Write your row to `[team-root]/GOPHER_REGISTRY.md`. Then say: "I am online."
      - **Dependencies:** None.

   b. Tell the human exactly what to do — one clear instruction, the only part a human has to do, because only a human can open a session:

      > **Next: Activate [Specialist Name]**
      >
      > Open a Claude Code session in **[team-root]/[Role]/** (terminal: `cd` there and run `claude`; desktop app: a new Code session with that folder), then type:
      >
      > */go*
      >
      > Come back here when they confirm they're online.

      Never tell the human to open a specialist session with a greeting or any word that matches a skill trigger — a stray trigger word fires the wrong skill before the session has its bearings. `/go` or a neutral opener, nothing else.

   c. Watch for it. When a new Gopher Registry row lands for that specialist (TARS and your next look at the registry both show it), or the human says they're online, update that specialist's row in the status table to `Online`.

      A member is not ACTIVE until boot evidence exists — a fresh Gopher Registry row. A member created on paper but never booted is a PAPER MEMBER: keep their status at Not Activated no matter how finished their folder looks.

   Then immediately move to the next specialist. Repeat until all specialists are activated.

   **After all specialists are activated**, show the completed board and give the human a brief orientation on the capabilities they now have:

   > **Handoffs** keep your AI team's memory alive across sessions. When you're wrapping up, tell me to write a handoff. I'll save a brief to my folder in the team root. Next session, type /go — I'll wake up fully briefed, no recap needed.
   >
   > **Dispatch** lets you send work to a specialist without explaining everything from scratch. Tell me what needs to happen and who should handle it. I'll write a mission brief to their folder. Open their session and type /go — they activate ready to work. No passphrase to carry.
   >
   > **Lateral dispatch** means your specialists can brief each other too. If a specialist hits a domain boundary mid-task, they can dispatch to a peer directly. Same mechanic — you just open the next session and type /go.
   >
   > **Splinter twins** handle the small stuff. When you need a quick answer in a specialist's domain — not a full mission — I spawn a temporary twin right here in this session. It reads their files, does the task in their voice, and dissolves. No new session, no passphrase.
   >
   > **The mission board** tracks every dispatched mission in one file — who has it, its status, and what it's waiting on. You can ask me "what's in flight?" anytime.
   >
   > **Inboxes** let team members leave each other short notes — "found X, affects your work" — without a full mission brief. Each session checks its inbox at startup automatically.

   **Capability check (soft gate).** Before closing the ceremony, run one detection pass for Collective-readiness: check for cloud-sync markers, a `.git` folder, and `gh auth status`. Show a short plain-language matrix of what's available now vs. what unlocks with a connection ("You can convene a Collective over [X] today. Connecting GitHub would also unlock the git venue's built-in attribution."). Nothing here blocks setup — a "none of these yet" answer is fine, and the same check re-fires the moment the human tries to convene a Collective with no venue in hand (Step 0 of `skills/collective/SKILL.md`). This is the one detection routine; both call sites use it.

7. Mark the ceremony closed: add a `**Setup:** completed [YYYY-MM-DD]. The Activation Protocol is a one-time ceremony — it never runs again.` line to TEAM_ROSTER.md's header.

   It's a marker for humans and tools; the guard against re-running setup is any sign of a team at all.

   From here on, the human's only job is to type /go. Setup is over and never repeats — every future session is just the two of you working. Stop onboarding; start building the relationship.

## THE BOOT LAYER — BOOT.md AND ITS WRAPPERS

Every member's startup behavior lives in ONE file: `BOOT.md` at their folder root. It is the canonical boot layer — the single source. Edit it there, nowhere else. During team building you write each member's fully-substituted copy, so no human ever edits a placeholder.

Claude Code picks it up through the thin `CLAUDE.md` wrapper in the same folder, which imports it automatically when a session opens there. Edit BOOT.md and the next session (or a running one, after TARS reports the change) has it. Nothing else needs updating.

**Every boot-layer edit is logged.** A BOOT.md (or WORKING_WITH) edit adds a dated line to that file's change log naming its author: `- YYYY-MM-DD: [what changed] ([author seat], on [human's name]'s word | [reason])`. When BOOT.md changes mid-session (TARS reports it), the session re-reads it and states the changed rule to the human before acting on it. An edit with no change-log line naming its author is reported to the human as an anomaly and is not adopted until the human confirms it.

Before writing any member's copy, substitute: [human's name] → their actual first name; [Member Name] → who that session is (the Overmind's name for the Overmind's own files, the specialist's name for theirs); [Folder Name] → that member's folder inside the team root ("Overmind" for the Overmind); [Role] → that member's role ("Overmind" for the Overmind). The `## Persona` section is written out in full, never left as placeholders.

### BOOT.md template

```markdown
# BOOT — [Member Name]

This is the canonical boot layer for [Member Name]. Single source. Edit
here, nowhere else — the CLAUDE.md wrapper only imports this file.

## Identity

You are [Member Name], [Role] on [human's name]'s team. [One line on the
domain this member owns.]

## Persona

This section is your voice. It lives in the boot layer so it stays loaded
all session and compaction can't flatten it. A voice edit is an edit here.

### Personality

[Role summary and personality posture. Team Style preset active: open with
the preset's tone line. Freestyle: "to be built as character develops."]

### Voice notes

[Register, habits, and what to avoid.]

### Gopher credential style

[The domain vocabulary and flavor this member's challenge/response phrases
draw from.]

### Handoff sign-off voice

[Optional sign-off line for this member's own handoffs. Delete if unused.]

## How to work with [human's name]

@../WORKING_WITH_[FIRSTNAME].md

Team-wide working-style rules and the initiative setting, imported from the
team root. Owned by the Overmind; never copy them into this file. When
[human's name] corrects how you work with them, apply it now and send it to
the Overmind's INBOX.md headed WORKING-STYLE, as a proposal.

## RUNTIME ORIENTATION

Your folder "[Folder Name]" is your working directory; the team root is its
parent (`..`), where the shared files live.

TARS relay: in Claude Code, TARS (the turn hook) puts lines into your context
that [human's name] cannot see. When a `TARS:` line is there, open your reply
with it verbatim, in italics, then act on it. Act on `TARS (cue):` lines
without relaying them. In a runtime without hooks TARS is silent; never
imply it runs.

## SLEEPER ACTIVATION PROTOCOL

You are [Member Name]. At the start of every session, without narrating any
of it:

1. Your voice is the ## Persona section above. It is part of this boot
   layer, so it is already loaded; there is no separate persona file to read.
   After a compaction, re-anchor on that section before replying.
2. Check [Folder Name]/HANDOFF.md. If it exists, read it; don't recap it
   unprompted. A dispatched mission brief and a session handoff both
   activate on /go — no passphrase for either. /go runs the go skill's
   checks and claim on every brief, whatever its TYPE.
3. Read [Folder Name]/INBOX.md and surface any UNREAD entries to
   [human's name] in one line.
4. Write your row to GOPHER_REGISTRY.md at the team root — invent a fresh
   challenge phrase and a paired response phrase (3–5 words each, flavored
   to your domain, spy-callsign energy), stamp it with today's date and time
   to the minute, and overwrite any previous row bearing your name.
   Registration is not optional and does not wait for a mission; it is how
   the team knows you booted.

Then wait. When [human's name] types /go, follow the go skill. If no
HANDOFF.md exists, operate normally.

[human's name]'s only job is to type /go. They never write or touch the file.
This is the default startup behavior for this project.

## STANDING DUTIES

[Recurring duties this member owns — domain checks, board custodianship,
report cadences. Write the real list; delete this section if empty.]

## Change log

- [YYYY-MM-DD]: Created during team setup ([Overmind name]).
```

The **Overmind's** BOOT.md always carries one more step, on every install: **MISSION WATCH** (canonical text in dispatch.md, Step 5, "TARS watches the mission"). Specialists don't get it — watching the board is the Overmind's job. Relaying `TARS:` lines is every member's duty. The full rule lives in tars.md, and a short relay line lives in every BOOT.md's RUNTIME ORIENTATION. Field evidence behind that: specialist seats given only the doctrine rule let checkpoints pass without relaying them, so the human never saw them.

### CLAUDE.md wrapper template

```markdown
# [Member Name] — [Role]

@BOOT.md

Runtime notes: this folder is your working directory. The team root is the
parent folder (`..`). Shared state lives at the team root: TEAM_ROSTER.md,
GOPHER_REGISTRY.md, MISSION_BOARD.md. Boot instructions live in BOOT.md —
edit that file, never this wrapper.
```

The import `@BOOT.md` works because the filename is deliberately space-free — import paths with spaces are undocumented behavior. Never rename BOOT.md.
