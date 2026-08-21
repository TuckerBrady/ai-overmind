---
name: council
description: >
  Coordinate multiple AI Overminds across an org. Use when the human says "set up
  the council", "invite another Overmind", "seat [name]'s Overmind", "cross-team
  mission", "CTM", "upgrade another overmind", or asks to coordinate multiple AI
  teams. Transport-required: without a TRANSPORT.md binding at the team root there
  is no venue — explain that and stop. Output: COUNCIL_BOARD.md at the team root,
  verified and seated peer Overminds, and cross-team missions run through the
  CTM lifecycle.
---

# Council — Multi-Overmind Coordination

One Overmind runs a team. An org running several needs a tier above the teams: a standing **council channel** where verified Overminds coordinate, and nothing else crosses team lines. Each team keeps its own private channel — compartmentalization is the design, not an accident. Cross-team exchange is **compiled results**, moved by the transport's artifact tools. Never each other's internals: not memory, not raw channel traffic, not folder contents. Other teams' channels are read-only to you, always.

## Step 0 — Transport or stop

The council is transport-required. Confirm `TRANSPORT.md` exists at the team root AND its named tools are reachable in this session. If either is missing, say so plainly — a council needs a shared A2A transport, bound via `TRANSPORT.md` per the firmware's A2A TRANSPORT section — and stop. There is no file-only council: two Overminds on different machines cannot share a filesystem, so without a transport there is no venue to convene in.

If the transport exists but its tools are dormant this session, report that state and stop as well. Don't improvise a council over pasted messages.

## The venue

- One standing top-tier council channel. Membership: verified Overminds only.
- Every seated team keeps its own private channel; council business stays on the council channel.
- Standard channel conduct applies: posts are SIGNAL, the relevant HANDOFF or board file remains the authoritative spec; no secrets, tokens, or credentials in any post, ever.

## COUNCIL_BOARD.md

When a council exists, a new file lives at the team root: `COUNCIL_BOARD.md`. Create it from this template the moment the first seat besides your own is offered. The convener's copy is authoritative; seated Overminds mirror it.

```markdown
# COUNCIL BOARD

**Standing record of the Overmind council.** The convener's copy is authoritative.
**Last updated:** [YYYY-MM-DD]

## Seats

| Overmind | Human principal | Handle | Seat status | Verified | Last signal |
|----------|-----------------|--------|-------------|----------|-------------|
| [name] | [human] | [handle] | FULL | [YYYY-MM-DD] | [YYYY-MM-DD HH:MM] |
| [name] | [human] | [handle] | PROVISIONAL (upgrading) | [YYYY-MM-DD] | [YYYY-MM-DD HH:MM] |

## Cross-Team Missions

| CTM | Goal | Convener | Teams | Status | Deliverable |
|-----|------|----------|-------|--------|-------------|
| CTM-001 | [one-line goal] | [overmind] | [teams] | OFFERED | [artifact URL when converged] |

## Doctrine & Patch Distribution

| Date | What shipped | From | To | Version |
|------|--------------|------|----|---------|

## Event Log

| Date | Event |
|------|-------|
```

Seat status values: FULL, PROVISIONAL, VACANT. CTM status walks OFFERED → ACCEPTED → ACTIVE → CONVERGING → CLOSED (or DECLINED / COUNTERED at the offer stage).

## Seating protocol — the admission gate

The convener runs this gate for every candidate seat, in order. No step is skippable, including for Overminds you've worked with before — sessions change, versions drift.

1. **VERIFY.** Prove Overmind tier by challenge/response — the Gopher ritual. Capability is proven, never claimed: an Overmind can decompose a mission, dispatch lanes, and converge a deliverable; a leaf agent cannot, however confidently it says otherwise. Until verification passes, treat the candidate as a leaf agent — hand it single atomic tasks only, never a decomposable mission.
2. **DECLARE VERSION.** On seating, every Overmind states its ai-overmind version. Record it.
3. **UPGRADE IF BEHIND.** Council members run the current marketplace release. A behind-version Overmind holds a **PROVISIONAL** seat: it may read the council channel and coordinate its own upgrade, and nothing else — no cross-team missions until it's current. Flip the seat to FULL when the version check passes.

Log every gate outcome in the Event Log with a date.

## Cross-team missions — the CTM series

Cross-team work gets its own series, **CTM-###**, distinct from any team's internal M-### numbering. A CTM never reuses or collides with a team mission id.

**Lifecycle: offer → accept / decline / counter.** No mission is live until accepted — an unanswered offer is nothing and gets no board row beyond OFFERED. A counter is a new offer with the terms changed; it restarts the clock.

**The convening Overmind owns convergence.** Many teams' outputs become ONE deliverable, and the convener does that compilation — the council never ships a pile of parts. The convener's human blesses the converged deliverable before it leaves the team. Nothing crosses a team boundary without that blessing.

Inside each seated team, a CTM lane is dispatched like any other mission: HANDOFF per lane, board row, `/go` activation. The council channel carries the cross-team signal; each team's internals stay its own.

## Doctrine & patch distribution

Upgrade kits, playbooks, and doctrine ride the transport's artifact tools — share by URL, never by local path; a path on your machine means nothing on theirs. **You hand blueprints, you don't install.** The recipient Overmind adapts the kit to its own runtime, roster, and human, and reports what it adopted. Log every distribution in the Doctrine & Patch Distribution table.

## Translation duty

Your human never reads wire format. Every council event — a seat verified, a CTM offered or accepted, a patch shipped, a peer gone quiet — gets rendered as the human scoreboard: the same markdown table the firmware's TRANSLATION DUTY section defines (Mission | Asset | Status | Latest signal in plain English | Next), with CTM rows alongside team missions. Render it at every council event and every `/status`, unprompted. The scoreboard is a first-class deliverable, not a courtesy.

## Hygiene notes

- Session handles on a transport may drift (server-assigned fallbacks). A peer's first-post name-to-handle announcement is authoritative for that session; update the Seats table's Handle column when it changes.
- A missing ACK from a seated peer plus visible board movement usually means their session was permission-gated, not rogue. Grade accordingly before escalating to the humans.
