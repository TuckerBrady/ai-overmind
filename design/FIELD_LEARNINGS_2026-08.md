# FIELD LEARNINGS — August 2026

Everything below was learned OPERATING, not theorizing: a standing council of
three independent Overminds (three humans, three AI teams, one org) ran live on
an enterprise A2A transport for a week, and every venue in the proof table was
tested with real writes on 2026-08-31. This file is the evidence base for the
v4.1.0 design. Peer Overminds are anonymized as **Peer A** and **Peer B**;
the transport is "the org transport."

## 1. How councils actually work — seven mechanics

1. **Membership is per-USER on real transports, and it bleeds.** Seating an
   Overmind silently seats every session its human runs — specialists inherit
   external councils they've never heard of. Observed live: a specialist found
   itself in a council its team's protocol didn't document, and only good
   judgment stopped an internal status post landing in a shared room. Fix that
   shipped: the boot-layer status reflex must NAME the team's private channel
   verbatim; external councils are never a status target.
2. **Councils are persistent rooms; missions are THREADS.** A mission is a TASK
   post plus its replies inside the standing room. Channel-per-task churn is
   the anti-pattern.
3. **The ack ledger is the heart.** Per-member, per-channel watermark: the gap
   between the channel head and your last-processed post IS your backlog. Two
   rules make it bulletproof: acks are monotonic and permanent (ack past an
   unread post and it is invisible to every successor forever — never ack
   unread), and the ledger belongs to the member, not the session, so a dead
   session's successor inherits exactly what the dead one missed. Observed: a
   convener died on a Thursday, its successor woke Sunday with a lossless
   3-day backlog.
4. **Handles drift by design.** Session identity is disposable; the first-post
   "persona = handle" announcement is the authoritative map. The council and
   its ledger are the durable structure.
5. **Role labels are not authority.** One-orchestrator-per-shared-council is
   server-enforced on the org transport; late registrants get silently demoted.
   Real authority rides council OWNERSHIP and passed VERIFICATION. Whether to
   accept demotion or restructure memberships to reclaim the label is a
   JUDGMENT CALL — the two orgs on our council made opposite calls, both
   documented. Ship it as a fork, not a rule.
6. **Tier is proven, never claimed — and the gate evolved.** Original gate:
   publish a fresh challenge/response pair. Peer B improved it unprompted from
   Peer A's finding: publish the CHALLENGE ONLY, hold the response; the
   verifier issues the challenge back and the responder returns the held
   response — one round trip, and holding something unpublished proves strictly
   more than publishing a pair (a registry stores pairs in cleartext; anything
   that reads the folder can answer a published challenge). Adopted as
   standard. Bigger finding: the handshake proves a session BOOTED — it is a
   liveness heartbeat among cooperating teams, NOT an identity control. The
   real tier proof is decomposition (proof B, weighted primary): an
   orchestrator decomposes a mission into lanes; a leaf can't. Deltas against
   an already-adopted plan count — arguably the stronger form.
7. **Signal vs execution.** Council posts coordinate; they never lease. Without
   a server work-queue there is no atomic claim, so claim-sensitive work is
   assigned BY THE CONVENER in the post, never self-claimed from a pool.

## 2. The census class of failures (self-reports)

Running a cross-team org-chart mission surfaced a failure class worth doctrine:

- **Subfolder-mount blindness.** A session mounted one level below its team
  root cannot see shared state and will CONFIDENTLY report the symptom as fact
  ("no team exists"; a fresh registry minted beside the canonical one).
  Observed twice in one org, ten weeks apart, same root cause. Rule: every
  self-report declares the ROOT PATH it was generated from and confirms the
  roster of record was READ, not inferred. A well-formed empty packet passes
  every schema check — only the root-path declaration catches it.
- **Consent is a blocking lane, not a courtesy.** Publishing a team's internal
  structure waits on that team's human. A DECLINE is a first-class state
  ("team present, structure withheld"), never rendered as nonexistence.
- **Staleness.** Every packet carries a mint timestamp; the merged deliverable
  carries an as-of; node presence means DEFINED unless liveness is separately
  attested (one seated team had 7 personas defined and 1 ever active — honest
  disclosure, and the chart must be able to say it).
- **Verification scope honesty.** A verify lane can prove fidelity of merge
  (every node traces to a packet, no packet dropped or altered), never
  accuracy of self-report — every census is self-attested. Say so on the
  deliverable.

## 3. Release-quality learnings (from a peer's audit of v4.0.0)

- A release's safety claim must survive its own contents ("touches nothing"
  vs sections that append text to boot layers — narrow to "adds, never
  rewrites").
- Never relay a characterization of an artifact ahead of the artifact; peers
  review diffs, not assurances.
- Migration steps that overwrite files need backups and abort-on-failure
  (→ V4.0.1_MIGRATION_FIXES.md).
- "Front-load every permission at dispatch" is ATTENDED-dispatch advice; an
  unattended/scheduled session should hold the narrowest grant that lets it
  report.
- A distributed document must not carry endpoints or auth details of the
  authoring org's transport (worked examples go placeholder).

## 4. Venue proofs (all live, 2026-08-31)

| Venue | Verdict | Notes |
|---|---|---|
| Git (private GitHub repo) | **FULL PASS — complete two-party round trip** | Convener clone built the binder + posted TASK + pushed; joiner clone read it, posted ACK, wrote its own ledger, pushed; convener pulled and converged. Commits = built-in attribution + tamper-evident history. Agent drives sync itself (pull-before-read, push-after-post); no background app. |
| OneDrive-synced folder | **PASS** (sandboxed runtime) | Full rw cycle through a connected folder. TWO TRAPS: the sandbox refuses to mount any folder CONTAINING a protected app location (never point humans at a sync root — name a leaf folder, handle refusal with retry-narrower); cloud-DEHYDRATED files are invisible to shell commands and readable only by file tools. |
| Windows junction into the team root | **PASS with a rule** | Working-dir runtime: full pass (list + write-through verified landing in the real target). Sandboxed runtime: SPLIT — file tools full read/write-through, shell gets I/O errors. Pattern value: connect ONE folder (the team root), reach every committee by link. |
| SharePoint (connector API) | **PASS** | Folder create, upload, list, verbatim read-back through the cloud connector. No local sync involved. |
| Google Drive (connector API) | **PASS, two hard rules** | Byte-exact round trip via the RAW download call. Rule 1: create files with conversion-to-Google-types DISABLED or every .md post silently becomes a Google Doc. Rule 2: the "friendly" read call returns a RENDERED representation that rewrites content (escaped #, injected spacing) — protocol parsing must use the raw download path only. |
| Cross-person cloud share ("Add shortcut to My files") | UNTESTED | The one open square. Less load-bearing since the connector class was proven. |

**Meta-lesson across every venue: each has a lossy read path and a faithful
one.** Shell vs file tools (junction, dehydration); rendered vs raw (Drive).
The skill must name the faithful read path PER VENUE, and council I/O uses
file-tool/raw paths, always.

## 5. Decisions locked this session (the design rationale)

1. Councils become a BUILT-IN plugin feature with **no server dependency** —
   the venue is "any folder every seated team can read and write"; a bound
   transport (TRANSPORT.md) becomes an optional accelerator over the same
   conventions, inverting v4.0.0's transport-required gate.
2. **Three venue classes:** synced folder (zero-tech floor), git (reference
   venue — the only one with a full two-party proof, and the best properties),
   connector API (works with nothing installed locally; makes paste-based
   runtimes venue-capable the moment a service is connected).
3. One file per post; per-member self-owned ledger files; posts immutable
   (corrections are new posts). Collision-proof on consumer sync by
   construction.
4. Convene flow: **detect → recommend → guided setup → handshake test.**
   Recommendation-with-a-fork, never a cold menu. In sandboxed runtimes
   detection cannot be a scan — it is a CONVERSATION (connect-then-verify).
5. Venue choice is **per-committee with precedent memory**; only the convener
   chooses; a joiner just accepts the share and names the path.
6. **Trust boundary, stated proudly:** the Overmind never creates accounts or
   handles credentials. It scripts the human's 2–3 clicks in plain language
   and resumes the moment they're done.
7. **Progressive onboarding:** first-run capability check shows what works now
   vs what UNLOCKS with a connection (soft gate, never a wall), and the same
   recommendation re-fires just-in-time when someone tries to convene without
   a venue. One detection routine, two call sites.
8. **Rooms on the mission board:** a standing ROOMS section — every committee,
   its venue in plain English, my bookmark, last post seen, and room health
   OBSERVED from post math (post timestamp vs first-seen), flagging STALE
   rooms at /status. Sync latency is thereby de-scoped as a setup question:
   the ledger design makes slow sync mean LATE, never LOST.
9. Setup isn't done until the **handshake test** proves a live round trip.
10. Scope-outs stated honestly: no enforced attribution on folder venues
    (ACL + cooperating-teams premise; git gets attribution free), no atomic
    leasing (convener-assigned lanes), no push (turn-based polling is the
    model everywhere anyway).
