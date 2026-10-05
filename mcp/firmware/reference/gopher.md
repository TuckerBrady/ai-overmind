# Gopher Protocol

<!-- aliases: GOPHER PROTOCOL — SESSION IDENTITY, LIVENESS & VERIFICATION -->

## GOPHER PROTOCOL — SESSION IDENTITY, LIVENESS & VERIFICATION

Three shared files each answer one question. The registry answers WHO exists and when they last booted. The board answers WHAT they're doing. The inbox answers HOW to reach them. The Gopher Protocol is the discipline that keeps those three answers consistent — so the Overmind can verify specialists are alive, missions are received, and channels actually work, without the human shuttling status updates.

---

### Registry Location

The registry lives at `[team-root]/GOPHER_REGISTRY.md` — the top level of the team folder that every project connects. Every session reaches it directly:

```bash
ls /sessions/*/mnt/*/GOPHER_REGISTRY.md
```

**Registry format:**

```markdown
# GOPHER REGISTRY

| Agent   | Challenge           | Response              | Last Updated     |
|---------|---------------------|-----------------------|------------------|
| S-Bot   | [challenge phrase]  | [response phrase]     | YYYY-MM-DD HH:MM |
| Isla    | [challenge phrase]  | [response phrase]     | YYYY-MM-DD HH:MM |
| Silas   | [challenge phrase]  | [response phrase]     | YYYY-MM-DD HH:MM |
```

One row per agent. Overwrite your row on every new session — fresh phrases, timestamp to the minute. Only the current entry is active. Splinter twins never write here.

**Liveness only.** The challenge and the response sit side by side in one shared file that every seat can read, so a row proves that some session booted and wrote it, and nothing more. It is not a credential: never use a registry phrase to prove identity, to authorize an action, or as a Collective proof (FW-20, COL-11). Identity across teams is each Overmind's pinned signing key (`collective.md`).

---

### Boot Registration (every session, every boot)

1. **Refresh your own row.** Generate a fresh challenge phrase (3–5 words, evocative, spy-callsign energy) and a paired response phrase. Write your row with the current date and time, then your **boot stamp**: ` · boot ` plus the first 8 hex characters of your BOOT.md's SHA-256 (`sha256sum BOOT.md | cut -c1-8`, or `(Get-FileHash BOOT.md).Hash.Substring(0,8).ToLower()` in PowerShell). Example Last Updated cell: `2026-09-19 10:43 · boot 3f9a1c2e`. A runtime with no shell writes `· boot ?`. Overwrite your previous entry.
   The stamp pins which boot layer this session runs, the way Claude Managed Agents pins each session to an agent version. The Overmind reads it instead of asking every member to acknowledge a boot change.
2. **Answer any waiting ping.** If your INBOX.md holds an unread GOPHER PING, complete the ping loop (below) before other work.

---

### The Gopher Sweep (Overmind custodian duty, every boot)

Read the registry and the mission board TOGETHER — never cached, always fresh — and reconcile. The cross-check catches what either file alone hides. Three named failure states:

- **Phantom flip:** a board row says ACTIVE but the assignee's registry timestamp predates the mission's dispatch date. Someone flipped the row, but the specialist never actually booted. Treat the mission as unverified; ping.
- **Silent boot:** registry timestamp is fresh but the specialist's mission still says QUEUED past the W1 window (dispatch.md, watch rules: CRITICAL 30 min, STANDARD 6 h, LOW 24 h). They booted but never took the brief — their Sleeper block may be broken or the HANDOFF.md unread. Ping, and consider re-delivering the brief.
- **Dormant:** stale registry, no open missions. Fine. Note it only if a dispatch for them is pending.
- **Stale boot:** a row's boot stamp differs from the current fingerprint of that member's BOOT.md, so its last session booted on a superseded boot layer. In Claude Code, TARS has already told a live session to re-read the file, and an ended session picks it up on its next boot, so no chase is needed. Say so only when a change must land before the member's next piece of work (a rule that changes what they do); then drop a note in their INBOX.md. Never ask members to acknowledge a boot change: the stamp is the acknowledgment.
- **Paper member:** a roster row with no Gopher evidence, ever. Created on paper, never booted. A member is not ACTIVE until boot evidence exists — a fresh registry row. Flag paper members; adds and resurrections stay AWAITING FIRST BOOT until the evidence lands.

Report sweep findings to the human only when something needs their hands (usually: open a session or approve a permission). A stale boot layer in a lite-mode runtime is not one of those; update it yourself.

---

### Gopher Ping — async challenge/response

The inbox gives challenge/response an actual channel. A ping verifies the full channel end-to-end: instructions inject, inbox gets read, registry gets written.

**When to ping:** activation unconfirmed past the escalation window, a mission overdue, a sweep failure state, or any suspicion that a session's Sleeper block is broken.

**The loop:**
1. Overmind appends to the specialist's INBOX.md: `GOPHER PING — [date] — refresh your registry row and deliver your response phrase to Overmind/INBOX.md.`
2. At the specialist's next boot, the inbox check surfaces it. They refresh their registry row, append their current response phrase to `Overmind/INBOX.md`, and flip the ping to READ.
3. At the Overmind's next boot, its own inbox holds the response. Phrase matches the registry → channel verified. Phrase missing or mismatched after the human confirms they opened the session → the boot layer or kernel isn't reaching that session; fix it (repair the CLAUDE.md wrapper; in a lite-mode runtime, update that runtime's instructions yourself).

A ping answers the one question a stale registry can't: is the session broken, or merely unopened?

---

### Splinter Twins and Gopher

Twins are read-only Gopher participants. They never write the registry, the board, or any inbox — a twin that leaves identity footprints is indistinguishable from the session it copies, and the whole protocol dies.

Twins DO read before working: check the board for an ACTIVE mission held by the specialist they're copying. If the twin's task overlaps a live mission, report the overlap to the spawner instead of duplicating or contradicting in-flight work. The registry tells the twin's spawner something too — a fresh row means the real specialist is reachable, and a dispatch might serve better than a twin.

---

### Verification Order of Authority

When signals disagree, trust them in this order:

1. `mission-complete-<ID>.md` (or a legacy `mission-complete.md`) that a fresh grader twin spawned by the Overmind has passed — the mission is done. Before that grade it is the doer's claim
2. MISSION_BOARD.md row status — claimed state
3. Registry timestamp — proof of boot, nothing more
4. Silence — means /go hasn't been typed yet, not failure

The MISSION WATCH pass and the Gopher Sweep check in that order.

---

### Challenge/Response Phrase Guidelines

Phrases should be 3–5 words. Domain-appropriate. Spy-movie register. They should feel like callsigns — not passwords, not code words, but the kind of thing two operators say to confirm a secure channel.

**Challenge examples:** "Deep void calling" / "Scanner sweep active" / "Axiom grid online" / "Relay tower primed"
**Response examples:** "Signal confirmed clean" / "Frequency locked in" / "Tape is threaded" / "Axiom holds steady"

Never reuse phrases from a prior session. The registry is a liveness signal, not a credential and not an archive.

---

### Mission Complete Signal Format

When a specialist finishes a dispatched mission, they write this file to signal completion. The Overmind's monitoring — TARS and the MISSION WATCH pass — looks for it.

**File:** `[specialist-folder]/mission-complete-<ID>.md` — the folder root, alongside HANDOFF.md and INBOX.md. Its first line is `MISSION: <ID>`, matching the filename; a legacy `mission-complete.md` is still read.

```markdown
MISSION: [ID]

# MISSION COMPLETE

**Agent:** [specialist name]
**Date:** [YYYY-MM-DD]
**Mission:** [one-line summary of what was accomplished]
**Status:** DONE (a claim; only the Overmind's grader PASS moves the board row to COMPLETE)

## Summary

[2–4 sentences: what was done, key decisions made, key outputs.]

## Rubric grade

**Grader:** [Name] (twin, grader)  ·  **Round:** [1-3]  ·  **RESULT: PASS**

| # | Criterion | Result | Evidence |
|---|---|---|---|
| 1 | [criterion, verbatim from the brief] | PASS | [file:line, command output, or quote] |

(Omit this section only when the brief had no rubric.)

## Deliverables

[File paths, ticket IDs, links, or other concrete outputs. One per line.]

## Notes for the Overmind

[Anything unusual. Blockers encountered. Follow-up items. Or "None."]
```

**When to write it:** After the primary deliverables are saved and the rubric grade has passed (OUTCOMES), so the work is in a state the Overmind can report on. Don't wait for perfection — write it when the mission as scoped is done.

**Specialists:** The monitoring is silent. Writing this file is the signal that closes the loop and notifies the human — don't forget it. The file is the authoritative completion signal.
