---
name: morph
description: >
  Morph: build a whole package of code in one Overmind session with splinter twins. An architect
  twin locks the contract and rubric, builder twins work in parallel in their own git worktrees,
  a fresh grader twin inspects every pull request against the rubric alone, and a domain twin
  gates anything that computes money. Merges only on a PASS. Use when the human says "/morph",
  "morph this", "run a morph", "build this with twins", or hands over greenfield, clean-seam work
  (a library, a service, a data pipeline, a CLI) with clear acceptance criteria. Not for UI or
  device work without an emulator, and not for work that needs a specialist's live session memory.
  No MCP server required.
---

# MORPH — build with twins, merge on evidence

Morph turns one Overmind session into a small engineering org. The Overmind is the orchestrator.
Everyone else is a **splinter twin** (`agents/splinter-twin.md`) spawned in this session: no
dispatch, no extra sessions for the human to open, no human courier between steps.

The one idea that makes it work: **independence is a property of the inputs, not of the model.**
A grader that never sees the builder's summary, the orchestrator's opinion, or an earlier verdict
catches what the builder missed, even when it's the same model.

## Does Morph need the MCP server?

No. Morph runs on splinter twins, and twins work with or without `overmind-mcp`. When the server is
connected, a twin boots through its `boot` tool and reads the board with `board`. When it isn't, the
twin reads the seat's `BOOT.md` and its `@` imports from disk. Same behavior either way. The server
is an optional convenience (see `mcp/README.md`), never a prerequisite.

What Morph does need:
- Claude Code with the Agent tool (twins are subagents).
- `git`, and a repository the builders can branch from.
- A code host for pull requests (GitHub with the `gh` CLI is the tested path; plain branches work
  if the human reviews locally).

## When to use it

**Use Morph for:** greenfield or clean-seam code with checkable outcomes. Libraries, services, data
pipelines, CLIs, API clients. Work that splits into two or more lanes with a clear boundary.

**Don't use Morph for:**
- **UI or device work, unless inspections carry device evidence.** A grader reading a diff can't
  see a clipped footer at 360dp or a crash on level entry. If you must, every UI criterion needs
  emulator screenshots in the inspection, and the orchestrator smokes the build before a human does.
- **Work that needs a specialist's live session memory** (an open browser flow, a half-finished
  conversation). Twins know only what's on disk. Dispatch instead.
- **Fuzzy domains** where nobody can write a checkable rubric yet. Explore first, then Morph.

## Roles

Pick each role from your roster by lane. A team without a matching seat uses a generic twin with a
role description instead.

| Role | Usually | Tier | Job |
|---|---|---|---|
| Orchestrator | the Overmind | the session | Carves lanes, briefs twins, keeps the board, merges on PASS |
| Architect | your systems or requirements seat | `deep` | Locks contract, rubric, test strategy |
| Builders | your developer seat | `standard` | One lane each, own worktree, own branch, one PR |
| Grader | your QA seat, in GRADE mode | `standard`, `deep` on a third round | Grades one PR against the rubric only |
| Domain reviewer | your finance, security, or compliance seat | `deep` | Gates anything that computes money or touches secrets |

Tiers follow the firmware (Worker tiers, under SPLINTER TWINS): graders and anything touching money
or security never tier down.

## The run

### Wave 0 — frame it (orchestrator)

1. Write down the deliverable in one line and decide what kind it is: a **library** (graded by its
   tests) or something **runnable** (graded by running it on real input). Runnable deliverables
   need a criterion that runs them end to end, or a CLI that silently falls back to fixtures will
   pass every test.
2. Open one row on the board for the run. Record the human's merge go for this mission on the
   board, so later merges don't stall waiting for a fresh approval.
3. Make a scratch folder per twin (`morph/<mission>/<twin-name>/`). A shared scratch folder
   collides mid-round.

### Wave 1 — the architect locks the contract

Spawn the architect twin with the problem, the inputs, and the constraints. It delivers, as files:

- **`CONTRACT.md`** — every module, function, and type with signatures, lane ownership, and the
  **clauses** below.
- **`RUBRIC.md`** — 5 to 10 numbered criteria per lane, each checkable from the deliverable alone.
  Never "high quality". Each criterion names the test that proves it.
- **`TEST_STRATEGY.md`** — structure, coverage floor, and one sample test so builders copy the
  pattern.

Contract clauses every Morph carries:
- **No gaming the checks.** A builder may not rename, obfuscate, or split a string to get past a
  grep, skip or weaken a test, or special-case a fixture. Any of these is an automatic FAIL.
- **No scope without a clause.** A builder who thinks the contract is wrong stops and says so. The
  orchestrator may not approve new scope in chat; only a new contract version can.
- **Outcome invariants over case rules** wherever inputs can be adversarial. A property that must
  hold for every input (with a seeded fuzzer and a positive control that proves the fuzzer can
  fail) beats a growing list of per-case rules, which never converge.

Before any builder spawns, run two checks:
- **Gap pass.** A second, fresh architect twin reads the contract cold and lists what a builder
  would have to guess. Fix those first.
- **Rubric dry run.** For every criterion, ask: could a grader check this with only the rubric, the
  diff, and the repo? If not, rewrite it. Repeat this at every contract version.

### Wave 2 — builders, in parallel

Spawn one builder twin per lane, two or three at a time. Each brief carries the contract, the
rubric, and the test strategy **verbatim as files**, plus:

- its lane and nothing else
- its own git worktree and branch: `git worktree add ../<repo>-<lane> -b morph/<lane>`
- **its own dependency install in that worktree** (`npm ci`, `pip install`, whatever the stack uses).
  Never link or junction a shared `node_modules`; an install through a junction wipes the shared
  copy.
- test titles copied **verbatim** from the rubric, so the grader can match them
- every finding a grader has made on an earlier lane, so the same mistake isn't made twice
- "Ship one PR. Every contract item exists. Every rubric test passes. No scope creep. If the
  contract is wrong, stop and say so."

On Windows, have every text check force UTF-8. A default-encoding read can pass a check it should
fail.

### Wave 3 — a fresh grader per PR

For every PR, spawn a **new** grader twin in GRADE mode. Never resume one. Its prompt carries only:

- the rubric
- the contract
- the PR (or branch) and the repo path

Never the builder's summary, the orchestrator's opinion, or a previous verdict. The grader checks
every criterion against the code itself, one line each (`N. PASS|FAIL — evidence`), and ends with
`RESULT: PASS` or `RESULT: FAIL (n of m failed)`. A criterion with no evidence is UNVERIFIED, which
is a FAIL. The orchestrator never grades its own fix.

Grade coverage as well as correctness. A run can pass every test while silently dropping part of
the input; a criterion should count what went in against what came out.

### Wave 4 — domain gate

Anything that computes money, fees, prices, budgets, or balances, or touches keys, auth, or
compliance, goes to the domain reviewer twin after the grader passes it. It looks for optimistic
defaults, silent failures on edge cases, and missing audit trail. In field runs this gate caught
most of the high-severity economic flaws that code graders had passed. For money, it is not
optional.

### Wave 5 — merge

Merge only on a grader PASS (and a domain PASS where it applies). On a FAIL:

1. The builder fixes the gap on the same branch, with an outcome test for the fix. Fixes open new
   boundary holes if they don't.
2. If branch protection needs the branch up to date, rebase first. When `git range-diff` shows the
   patch unchanged (`=`), a cheap re-inspection of the gates is enough; otherwise a fresh grader
   grades it again.
3. Merge one PR at a time, rebasing the next onto the new base.

A twin nearing the end of its context gets replaced by a fresh one that reads the state from
files on disk. Keep the contract, rubric, and verdicts in files for exactly this reason.

## Reporting

At the end, write one verdict file for the run: PRs merged, inspection rounds, what the graders
and the domain gate caught that builders missed, and what to change in the next contract. Tell the
human in three or four lines, with the link to the merged work.

## Anti-patterns

- Resuming a grader, or telling it what the builder intended.
- One worktree or one scratch folder shared between twins.
- Approving scope mid-build without a new contract version.
- Fixing a text defect sentence by sentence instead of sweeping for the figure.
- Grading UI by reading code, then handing the build to a human untested.
- Skipping the domain gate because "the math looked fine".
