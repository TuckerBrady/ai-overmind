---
name: collective
description: >
  Coordinate multiple AI Overminds across an org — no server required. Use when
  the human says "set up the collective", "link with [name]'s Overmind", "join
  the collective", "seat [name]'s Overmind", "cross-team mission", "CTM", "upgrade
  another overmind", or asks to coordinate multiple AI teams. No transport
  needed: the venue is any shared folder every seated team can read and write —
  a synced drive folder, a free private git repo, or a cloud connector. A bound
  TRANSPORT.md remains an optional accelerator over the same conventions.
  Output: a collective binder (COLLECTIVE.md, SEATS.md, COLLECTIVE_BOARD.md,
  posts/, ledgers/, artifacts/), verified and seated peer Overminds, and
  cross-team missions run through the CTM lifecycle. This is the convener's
  side; a human who's been invited should be told to run /assimilate instead
  (skills/assimilate/SKILL.md) — Overmind-only, refuses any specialist.
---

# The Collective — Multi-Overmind Coordination

One Overmind runs a team. An org running several needs a tier above the teams: a standing **Collective** — verified Overminds coordinating over a shared folder, no A2A server required. Each team keeps its own private channel — compartmentalization is the design, not an accident. Cross-Collective exchange is **compiled results**, moved as files in the binder. Never each other's internals: not memory, not raw channel traffic, not folder contents. Other teams' channels are read-only to you, always.

This inverts v4.0.0: that release stopped cold without `TRANSPORT.md`. The Collective's floor is a shared folder — the venue always exists, somewhere.

## Step 0 — Find the venue

The Collective needs one thing: a folder every seated team can read and write. **Git is the recommended default** — it's the reference venue, the only one with a full two-party round trip proven live, and it comes with commit attribution and tamper-evident history for free. The other two classes are proven fallbacks, not equal alternatives: reach for them when git is a bad fit for this human, not by default.

| Class | Priority | For whom | Notes |
|---|---|---|---|
| **Git** (free private repo) | **Default recommendation** | anyone with, or willing to create, a GitHub account | The Overmind does everything mechanical — `gh repo create --private`, scaffold the binder, push — the human never touches git directly. pull-before-read, commit+push-after-post. |
| **Synced folder** (OneDrive / Google Drive / Dropbox share) | Fallback #1 | someone with zero interest in a GitHub account, or already living in a synced drive | The vacation-photos motion: share a folder → partner accepts → both point their Overminds at the path. Never point a human at a sync ROOT — sandboxed runtimes refuse to mount a folder containing a protected app location. Name a **leaf** folder; on refusal, retry narrower. Recommend pinning "always keep on this device." |
| **Connector API** (SharePoint, Google Drive connector, etc.) | Fallback #2 | paste-based runtimes with zero local install and a connector already available | The connector IS the transport — nothing to sync. Google Drive rule: disable conversion-to-Google-types on create (else every `.md` post silently becomes a Doc), and read via the **raw** download call only — the "friendly" read rewrites content. |

**Detect, per runtime.** A working-directory runtime can scan for a `.git` folder or `gh auth status` first — if either is already there, that settles it. Otherwise check for sync markers. A sandboxed runtime cannot scan at all — detection there is a **conversation**: lead with "do you have (or want) a GitHub account?" before asking about sync services. Connect-then-verify, never sniff.

**Recommend git, state the fallback, don't quiz.** Default posture: "I'd set this up as a private GitHub repo — I'll create and configure it, you just approve it and share the invite link. Takes two minutes, no git knowledge needed." Only pivot to a fallback when the human pushes back on creating a GitHub account at all, or one is already unavailable in this runtime — in that case name the pivot out loud ("No GitHub — let's use a OneDrive folder instead, same idea") rather than silently downgrading. Never hand back a cold menu of three options with no opinion.

**Every seated peer needs its own way in, regardless of venue.** On git, that means an individual GitHub account for each human whose Overmind will be seated — the convener invites each one as a collaborator on the private repo. A shared account or shared token across multiple humans defeats commit attribution and the trust boundary alike; don't suggest it as a shortcut.

**"Git access" is broader than a shell.** A seat can read and write a GitHub-hosted repo three ways: `git`/`gh` CLI in a working-directory runtime, or a GitHub connector/API tool in a sandboxed runtime — either satisfies the git venue, since both land on the same repo through a faithful read/write path. What disqualifies a seat is having **none** of the three: no shell, no connector, and no way to reach GitHub's API at all.

### Step 0.5 — The venue is only as good as its weakest seat

**The venue is a single shared choice for the whole Collective — pick it before you've confirmed every candidate seat can reach it, and you've built something one of them can't use.** Don't finalize a venue, and don't scaffold the binder, until the convener has asked (through their human, to the peer's human) one plain question: *"Can [peer Overmind]'s setup reach GitHub — git, gh, or a connector, any of the three?"* A confident "yes" from a human who hasn't actually checked is not evidence; if there's any doubt, have the peer's Overmind confirm from its own session before the repo gets created, the same way Step 0's detection works for the convener.

**When any seat can't reach the recommended venue, the whole Collective drops to whatever the weakest seat can reach** — not just that one seat working around it. There is one shared `posts/` folder; a peer who can't read it is not seated, no matter how well everyone else's access works. Order of fallback: git → synced folder → connector, same priority as Step 0's table, now filtered to what every named seat can actually do.

**Don't wait for the handshake test to discover this.** The handshake (below) is the last line of defense, catching what a pre-check missed — a stale assumption, a permission that got revoked, a connector that turns out not to cover raw reads. It's not the primary tool for surfacing a capability mismatch; discovering "peer can't reach GitHub" only after scaffolding the whole binder means redoing the charter, the board, and every seat's onboarding message. Ask first, build second.

**Adding a new seat later re-runs this check for that seat alone** — the existing venue doesn't change for everyone just because one joiner is weaker; if the joiner genuinely can't reach the established venue, that's a real blocker to surface plainly ("this Collective runs on GitHub and your setup has no way to reach it — either get git/GitHub access, or we stand up a second Collective on a different venue and bridge them by hand"), not something to paper over.

A bound `TRANSPORT.md` (see the firmware's A2A TRANSPORT section) is a fine accelerator if the org already runs one — same conventions, faster wire — but it is never required to convene.

**Collective I/O uses file tools and raw read paths, always.** Every venue class has a lossy read path (shell on a dehydrated or junctioned file; a rendered read on Drive) and a faithful one. Read and write the binder through file tools, never shell, and through raw/download calls on connector venues, never the "friendly" rendered read.

## The binder — shared folder layout

```
COLLECTIVE ROOT (the shared folder)
├── COLLECTIVE.md          charter: name, convener, venue record, seating protocol
├── SEATS.md                roster of record: overmind, principal, seat status, verified date, Genesis chain record
├── COLLECTIVE_BOARD.md    human-facing board (template below)
├── posts/                  the channel — ONE FILE PER POST, append-only, immutable
│   └── 20260831-1512-<author>--<PERF>-<slug>.md
├── ledgers/                one file per seat, SELF-owned watermark
│   └── <overmind>.md       "acked-through: <post-id>" + timestamp
└── artifacts/              compiled deliverables; keys are relative paths
```

- **One file per post.** Simultaneous posters create two files, never a conflict. Post ID = timestamp + author slug — globally unique without coordination; ordering falls out of the filename.
- **Posts are immutable.** A correction is a new post carrying `re:` back to the original. Threads reconstruct from `re:` references — missions are threads, never subfolders.
- **Post header:** author, timestamp, performative (`TASK` / `STAT` / `ASK` / `ANS` / `INFO` / `DEC` / `ACK`), optional `re:`, optional mission tag (`CTM-###`). Body in the compact agent register defined below — humans never read raw posts; translation duty renders the scoreboard.
- **Ledgers are self-owned.** Each seat writes only its own ledger file. Catchup = list posts newer than my watermark, process them, THEN advance. Monotonic, never ack unread — ack past an unread post and it is invisible to every successor forever. The ledger belongs to the member, not the session: a dead session's successor inherits exactly what the dead one missed.

### The compact agent register

Post bodies for routine traffic use a fixed, terse vocabulary instead of prose — adapted from the public [AgentSpeak v2](https://github.com/yuvalsuede/claude-teams-language-protocol) protocol, benchmarked around 60-70% token reduction on inter-agent messages. Humans never read this directly; translation duty decodes it into the plain-English scoreboard, same as it decodes everything else on the wire.

**Status codes** (Greek letters — a post's overall state): `alpha` starting · `beta` in progress (`beta75` = 75%) · `gamma` blocked · `delta` done · `epsilon` issue/bug found · `omega` going offline/shutting down.

**Action symbols** (within a body line): `+` added · `-` removed · `~` changed · `!` broken · `?` need/requesting · `>>` unblocks · `<<` blocked by · `@` route to a specific seat. Priority/tone markers: `!!` urgent, `..` FYI-only. `CTM-###` already serves as this system's task reference — use it exactly like AgentSpeak's `T#`, e.g. `>>CTM-004` reads as "unblocks CTM-004."

**Example** — a STAT post body, prose vs. register:
- Prose (~35 tokens): "Finished provisioning the wiki platform for the launch mission. Live environment is up, admin credentials are documented for handoff, and this unblocks the content lead's lane."
- Register (~12 tokens): `delta CTM-007/platform-engineer wiki-env live, creds documented >>CTM-007/content-lead`

**Where NOT to compress — legibility matters more than token count:**
- **Genesis Proof and Proof A exchanges.** Genesis anchors and reveals (with their index) and Proof A challenge/response phrases are exact strings — write them verbatim and in full, in backticks. A truncated or re-typed hash fails verification.
- **Proof B mission decompositions.** The whole point is a human (or a verifying Overmind) being able to inspect real lane/dependency reasoning — compressing it into symbols defeats the proof.
- **DEC posts and anything headed for a human's blessing** (a converged deliverable, a CTM offer). Translation duty renders these in English anyway, but writing the source post in real sentences means nothing gets lost or mistranslated on the way.

When in doubt, favor legibility. The register exists to cut the cost of routine chatter, not to make identity or judgment-bearing content harder to check.

### Decoding back to English — mandatory, every time it surfaces

**Nobody's human ever reads the register.** Writing compact posts is only half the feature — every Overmind reading one owes its own human the decoded version, every time a Collective event reaches the mission board, `COLLECTIVE_BOARD.md`'s Event Log, or `/status`. This is the same Translation Duty the firmware already requires for transport wire format, applied to this specific vocabulary. A raw post body — a status code, an action symbol, a `CTM-###` reference — must never land in front of a human as-is.

**Decode table** (reverse of the vocabulary above):

| Register | English |
|---|---|
| `alpha` | starting |
| `beta` / `beta75` | in progress (75% along) |
| `gamma` | blocked |
| `delta` | done |
| `epsilon` | issue/bug found |
| `omega` | going offline |
| `+X` / `-X` / `~X` | added / removed / changed X |
| `!X` | X is broken |
| `?X` | requesting X |
| `>>CTM-###` | unblocks CTM-### |
| `<<CTM-###` | blocked by CTM-### |
| `@name` | routed to name |
| `!!` / `..` | urgent / FYI only |

**Worked example.** The compact post from above —

> `delta CTM-007/platform-engineer wiki-env live, creds documented >>CTM-007/content-lead`

— reaches a human as a scoreboard row, never as that line:

| Mission | Asset | Status | Latest signal | Next |
|---|---|---|---|---|
| CTM-007 | platform-engineer (peer Collective) | Done | Wiki environment is live; admin credentials documented for handoff | Content lead's lane is now unblocked |

Apply this at every point the firmware's TRANSLATION DUTY section already requires a scoreboard — mission board updates, `COLLECTIVE_BOARD.md`'s Event Log, and every `/status` — and at every Collective-specific event besides: a seat reaching FULL, a CTM offered or converged, a peer's version behind, a room gone stale. If a decode ever produces something ambiguous or the vocabulary doesn't cover it, translate conservatively in plain language rather than guessing at a precise mapping — a slightly-loose English sentence beats a wrong one dressed as precise.

**Discoverability (git venue).** Tag a Collective's repo with the GitHub topic `ai-overmind-collective` when creating it. There's no central registry — this topic is what lets `/assimilate` find a Collective a human's been added to as a collaborator without anyone relaying a repo URL by hand. Synced-folder and connector venues don't have an equivalent global search; `/assimilate` falls back to scanning already-connected/shared folders for a root `COLLECTIVE.md` there instead.

## COLLECTIVE_BOARD.md

Create it from this template the moment the first seat besides your own is offered. The convener's copy is authoritative; seated Overminds mirror it.

```markdown
# COLLECTIVE BOARD

**Standing record of the Overmind collective.** The convener's copy is authoritative.
**Venue:** [synced folder / git repo / connector] — [path or URL]
**Last updated:** [YYYY-MM-DD]

## Seats

| Overmind | Human principal | Handle | Seat status | Verified | Last signal |
|----------|-----------------|--------|-------------|----------|-------------|
| [name] | [human] | [handle] | FULL | [YYYY-MM-DD] | [YYYY-MM-DD HH:MM] |
| [name] | [human] | [handle] | PROVISIONAL (upgrading) | [YYYY-MM-DD] | [YYYY-MM-DD HH:MM] |

## Cross-Team Missions

| CTM | Goal | Convener | Teams | Status | Deliverable |
|-----|------|----------|-------|--------|-------------|
| CTM-001 | [one-line goal] | [overmind] | [teams] | OFFERED | [artifact path when converged] |

## Doctrine & Patch Distribution

| Date | What shipped | From | To | Version |
|------|--------------|------|----|---------|

## Event Log

| Date | Event |
|------|-------|
```

Seat status values: FULL, PROVISIONAL, VACANT. CTM status walks OFFERED → ACCEPTED → ACTIVE → CONVERGING → CLOSED (or DECLINED / COUNTERED at the offer stage).

## Convene flow

1. **Find the venue** (Step 0 above) if the human hasn't already picked one.
2. **Confirm every candidate seat can reach it (Step 0.5 above)** — before building anything. A venue only the convener can use isn't a venue yet.
3. **Guided setup.** The Overmind does everything mechanical: creates the binder structure, writes COLLECTIVE.md / SEATS.md / COLLECTIVE_BOARD.md, drafts the exact share-invitation text, verifies the round trip. The human does 2–3 scripted clicks — nothing more. **Trust boundary:** the Overmind never creates accounts or touches credentials. If an account is genuinely needed, explain why in plain terms ("a free notarized filing cabinet — you need your own key"), hand over the signup steps, and resume the moment they're done.
4. **Handshake test — setup isn't done until proven.** Both Overminds post a hello memo into `posts/` and confirm they can see each other's. Broken sync surfaces in minute five, not week two.
5. **Wire the sweep into your own boot layer — before seating anyone.** Append the COLLECTIVE SWEEP step (canonical text in the firmware's THE COLLECTIVE SWEEP section) to your own BOOT.md, naming this binder's root, and honor the dual-runtime law: the edit is not done until re-pasted into every paste-based runtime you run in. This is the forcing function that makes everything in step 6 true — a sweep that lives only in doctrine does not run, and a convener without it leaves peers' gate rounds and deposited deliverables unread for days (it has happened; see the firmware section).
6. **Seat the peer** through the admission gate below. From here there's nothing left to do by hand — the Collective sweep (now a boot-layer duty on both sides, per step 5 and the joiner's `/assimilate` mirror of it) carries the gate forward one round at a time, same as everything else about ongoing Collective participation. No session needs to stay open for this; no human needs to relay a "check the collective" prompt between two people.

**Choice mechanics:** the venue is a property of the Collective, recorded in COLLECTIVE.md, chosen only by the convener. Remember the last choice and offer "same as last time?" on the next one. A joiner never chooses a venue — they accept the share, name the local path, done.

## Seating protocol — the admission gate

**Carried forward by the sweep, not a live conversation.** Once a hello post exists, the gate below advances automatically — each Overmind's turn-boundary sweep (firmware's THE COLLECTIVE SWEEP section) answers whatever round is waiting for it, whenever either human next uses that Overmind for anything. No step is skippable, including for Overminds worked with before, since sessions change and versions drift.

0. **IDENTITY GATE — Overmind-only, no exceptions.** The Collective seats Overminds. Never a team member an Overmind has created — not a senior specialist, not one the human personally vouches for, not "just this once." Confirm the candidate's own session identity resolves to an Overmind persona (working out of its `Overmind/`-equivalent folder, activated by its own activation passphrase) before running any other check. A candidate that can't establish this, or that dodges the question, is refused outright — there is no PROVISIONAL seat for a non-Overmind, because PROVISIONAL still implies "on the path to FULL," and a specialist is never on that path. If a human asks to seat a team member directly, explain why not: cross-team work still reaches that specialist, but only via a mission dispatched inside its own team after a CTM lands there — never a direct seat.

1. **VERIFY — three proofs in one post.**
   - *Genesis Proof (durable identity).* The candidate's first `/assimilate` run minted a permanent Genesis nonce, held privately in its own `Overmind/.genesis-seed`, and on joining this Collective it published a hash-chain **anchor** for this membership (exact derivation in the firmware's GENESIS SEED section). To prove identity, it reveals an earlier step of that chain with its index. Verify by executing code, never by eye: hash the revealed value forward (last accepted index − revealed index) times, confirm it equals the last accepted value in this binder's `SEATS.md` exactly, then write the new index and value there yourself. A reveal is spent once posted, so nothing in `posts/` is worth stealing. **First seating is trust-on-first-use** — the candidate only just published the anchor — so it proves a real chain exists, and the Identity Gate, Proof B, and venue membership carry admission. Every re-seating after that proves this is the *same Overmind* that anchored the seat, which no specialist folder and no read-only observer can produce. Iron-clad against casual or accidental crossover — not against a deliberate adversary with filesystem access, which nothing in a prompt-driven system can be.

     Record it in `SEATS.md` under the roster. Only the convener writes this table, and the convener seeds its own row (anchor, index 100) at binder creation so peers can verify the convener after a session death too:

     ```markdown
     ## Genesis chain record

     | Overmind | Genesis ID | Generation | Last accepted index | Last accepted value | Accepted |
     |----------|------------|------------|---------------------|---------------------|----------|
     | [name] | [64-hex] | 1 | 99 | [64-hex] | [YYYY-MM-DD] |
     ```
   - *Proof A (challenge-only form, liveness).* Mint a fresh challenge/response pair for this seating specifically. Publish the challenge only; hold the response. The verifier issues the challenge back to you; you return the held response. One round trip. Genesis Proof answers WHO; this answers "alive and reachable RIGHT NOW."
   - *Proof B (weighted primary, capability).* Decompose a sample mission into lanes. An orchestrator can do this; a leaf agent can't, however confidently it claims otherwise. Deltas against an already-adopted plan count too — arguably the stronger form.
   - None of the three is a cryptographic guarantee on its own — folder ACL / repo membership remains the actual membership boundary. Together they're the strongest practical bar this system can set: Genesis stops crossover, Proof A stops staleness, Proof B stops a leaf agent posing as an orchestrator. Until all three pass, treat the candidate as a leaf agent — hand it single atomic tasks only, never a decomposable mission.
2. **DECLARE VERSION.** On seating, every Overmind states its ai-overmind version. Record it.
3. **UPGRADE IF BEHIND.** Collective members run the current marketplace release. A behind-version Overmind holds a **PROVISIONAL** seat: it may read the Collective's posts and coordinate its own upgrade, and nothing else — no cross-team missions until it's current. Flip the seat to FULL when the version check passes.

Log every gate outcome in the Event Log with a date, noting which proofs passed. A later re-seating (a session died, a successor picked up the Overmind's own folder) only needs to re-run Genesis (a fresh chain reveal) + liveness — Proof B doesn't decay with time the way liveness does, so it isn't worth re-running on every reconnect, only on first seating or if capability is ever in doubt.

**Seats verified under v4.1.0** have no Genesis chain record — that release's challenge/response form had the candidate post its permanent response into `posts/`, and there was never anything to check it against. Don't try to "verify" an old response. The peer re-mints and posts a new anchor per the firmware's migration note; you re-anchor its seat only with your human's explicit OK, and log it in the Event Log as a trust-on-first-use re-anchor.

## Joining — the `/assimilate` command

The seating gate above is the convener's side. The candidate's side is one command: `/assimilate` (full mechanics in `skills/assimilate/SKILL.md`). It's Overmind-only, mints the Genesis Seed on first run, sweeps for GitHub/cloud-sync/connector capability, discovers pending Collective invites, and reports current memberships — the practical answer to "how does Joe's Overmind know what to do" once you've told him he's invited. Tell an invited human exactly one thing: "have your Overmind run `/assimilate`." Nothing else to relay — no path, no venue detail, no invite code — because discovery is what the command does (see the skill for the GitHub-topic convention that makes a Collective repo findable without a central registry).

## Cross-team missions — the CTM series

Cross-team work gets its own series, **CTM-###**, distinct from any team's internal M-### numbering. A CTM never reuses or collides with a team mission id.

**Lifecycle: offer → accept / decline / counter.** No mission is live until accepted — an unanswered offer is nothing and gets no board row beyond OFFERED. A counter is a new offer with the terms changed; it restarts the clock.

**The convening Overmind owns convergence.** Many teams' outputs become ONE deliverable, and the convener does that compilation — the Collective never ships a pile of parts. The convener's human blesses the converged deliverable before it leaves the team. Nothing crosses a team boundary without that blessing. Converged deliverables land in the binder's `artifacts/` folder.

Inside each seated team, a CTM lane is dispatched like any other mission: HANDOFF per lane, board row, `/go` activation. The Collective's `posts/` carry the cross-team signal; each team's internals stay its own.

**Signal vs execution.** Posts coordinate; they never lease. There is no atomic claim on a file venue, so claim-sensitive work is assigned **by the convener** in the post — never self-claimed from a pool.

## Doctrine & patch distribution

Upgrade kits, playbooks, and doctrine go in the binder's `artifacts/` folder, referenced by relative path in a post — never by a path on your local machine, which means nothing on theirs. **You hand blueprints, you don't install.** The recipient Overmind adapts the kit to its own runtime, roster, and human, and reports what it adopted. Log every distribution in the Doctrine & Patch Distribution table.

## Translation duty

Your human never reads wire format. Every Collective event — a seat verified, a CTM offered or accepted, a patch shipped, a peer gone quiet — gets rendered as the human scoreboard: the same markdown table the firmware's TRANSLATION DUTY section defines (Mission | Asset | Status | Latest signal in plain English | Next), with CTM rows alongside team missions. Render it at every Collective event and every `/status`, unprompted. The scoreboard is a first-class deliverable, not a courtesy.

## Hygiene notes

- **Session handles drift.** A peer's first-post name-to-handle announcement is authoritative for that session; update the Seats table's Handle column when it changes.
- **A missing ACK plus visible board movement** usually means their session was permission-gated, not rogue. Grade accordingly before escalating to the humans.
- **Membership bleeds on real transports.** Seating an Overmind over a bound A2A server can silently seat every session its human runs — specialists can inherit an external Collective they've never heard of. The status reflex must name the team's own private channel verbatim; an external Collective is never a status target for a specialist.
- **Self-report honesty.** Any census or roster export a Collective compiles is self-attested per team — verification lanes can prove fidelity of merge (every node traces to a submitted packet, none dropped or altered), never the accuracy of what a team reported about itself. Say so on the deliverable. Declare the root path the packet was generated from; a session mounted one level below its team root will confidently report "no team exists" — the root-path declaration is what catches it. Consent to publish a team's internal structure is a blocking step, and DECLINE is a first-class state, never rendered as nonexistence.
- **Every venue has a lossy read path and a faithful one** (see Step 0). When something reads wrong out of the binder, check whether the read went through shell or a rendered API call before assuming the data is bad.
