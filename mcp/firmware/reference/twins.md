# Splinter Twins

<!-- aliases: FEATURE 3 — SPLINTER TWINS (IN-SESSION) -->

## FEATURE 3 — SPLINTER TWINS (IN-SESSION)

Not every task deserves a mission brief. When the human needs something quick from a specialist's domain — a question answered, a file reviewed, a small artifact drafted — spawn a **twin** instead of dispatching.

A twin is a subagent (the `splinter-twin` agent shipped with this plugin) that hydrates itself from the specialist's own files at spawn time. When the team engine is connected (the `overmind-mcp` server; its tools show up as `mcp__overmind__*`), the twin calls `boot` with the seat name and gets the specialist's BOOT.md with every `@` import inlined. Without it, the twin reads BOOT.md and each imported file by hand. Either way it takes the `## Persona` section as its voice (falling back to a legacy `feedback_[name]_persona.md` only if that BOOT.md has no Persona section), does the task in their voice and to their standards, returns a report signed "[Name] (twin)", and dissolves. The real specialist's session, memory, and files are untouched. A twin skips the boot layer's session-start sequence entirely: it is not a session.

**How to spawn one:** invoke the `splinter-twin` agent with a prompt that names the specialist, gives their seat name and the absolute path to their folder, and states the task. The seat name lets the twin boot through the team engine; the folder path is its fallback. Example prompt: *"You are a twin of Sam, Data Analyst. Seat: Sam. Their folder: [team-root]/Sam - Data Analyst/. Task: sanity-check the utilization math in [file] and flag anything off."*

**Twin vs. dispatch — the test:**
- Fits inside this session, needs only what's in the specialist's files, no follow-up state → **twin**
- Produces real deliverables, needs their browser/tools/session memory, runs long, or the human will ask about it later → **dispatch**

Twins never write to the specialist's HANDOFF.md, INBOX.md, mission-complete.md, the Gopher Registry, or the Mission Board (see Splinter Twins and Gopher in gopher.md). If a twin's findings matter to the real specialist, drop a note in their inbox after the twin reports back.

If the roster has no specialist for the domain, don't fake one with a twin — twins hydrate from real specialist files or not at all. Handle it yourself or propose a roster addition.

### Worker tiers — the right model and effort for the job

Not every twin or dispatched session needs the same horsepower. (Borrowed from Claude Managed Agents, where an orchestrator hands reading-heavy work to a cheaper worker.) Three tiers, each a model plus an effort level. **The Overmind picks the tier itself, from the task, without asking the human**, and writes it into the brief with a one-line reason.

| Tier | Use it for | Twin (Agent tool `model`) | Dispatched session (model · effort) |
|---|---|---|---|
| `light` | Sweeps, checklist audits, inbox and file triage, data entry, summarizing reading-heavy material. The output is facts, not judgment. | `haiku` for pure reading; `sonnet` when it has to weigh things | Sonnet · `low` (`medium` if it has to weigh things) |
| `standard` | The default. Building, writing, analysis, grading, anything written for the human. | `inherit` (the spawner's model) | Leave the session as opened |
| `deep` | Design decisions others will build on, root-cause hunts, security review, large multi-file changes, a problem with no precedent on the team, and any task where a previous attempt failed | `opus` | The most capable model the picker offers · `xhigh` |

**Picking the tier: the first rule that matches wins.**

1. A previous attempt at this task failed, or a lane failed its rubric grade twice → `deep`.
2. Security review, a design or architecture decision other work will build on, or a bug whose cause is unknown → `deep`.
3. A grader, anything written for the human, or anything touching money, health, legal, or security → `standard` at least, never lower.
4. The work is reading and reporting facts, with no judgment in the output → `light`.
5. Anything else → `standard`.

Torn between two tiers, take the higher one. A wrong `light` costs a redo; a wrong `deep` costs a little extra usage.

**Applying it.**

- **Twins:** pass the model with the spawn (the Agent tool's `model` parameter). Twins can't take an effort level; the model carries the tier.
- **Dispatched sessions:** a session cannot change its own model or effort. The Claude desktop app refuses that, so a session never silently re-prices its own turns. The Overmind applies the tier from outside, once, when the lane activates (watch rule 2). Find the session with `mcp__ccd_session_mgmt__list_sessions`: `/go` titles it with the mission ID. Then call `set_session_model` and `set_session_effort` on it (both deferred, so load them through tool search). The model must be an ID the app's picker offers. `get_session` shows the current one, and a wrong ID returns the valid list. The app asks the human to approve a change to a session this one didn't start: one click, and that is the only thing the human does. Record `tier applied` in the board note. No session tools (the terminal CLI, lite mode): tell the human in one line instead. Example: "Nash's lane is tier `deep`: set its model to Opus and effort to Extra high."
- **`standard` changes nothing.** The session runs as the human opened it.
