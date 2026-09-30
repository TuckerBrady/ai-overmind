---
name: morph
description: >
  High-velocity multi-specialist review protocol for independent, verifiable work.
  Use when the human needs 1-2 builders to ship code fast with confidence, backed by
  an independent inspector who grades only the rubric. Architects lock requirements first,
  domain reviewers gate economics. Merges only on inspector PASS. Designed for greenfield,
  clean-seam, no-device work (libraries, services, data pipelines). Not for UI/device work
  or seat-memory tasks.
---

# MORPH — Parallel Building + Independent Inspection

The MORPH protocol runs builders in parallel across isolated worktrees while a fresh inspector grades each PR against ONLY the rubric and contract. No builder opinions in the inspection. No resume on inspector failure. Every merge is human-gated.

**Use MORPH when:**
- Building a library, service, data pipeline, or API (greenfield, clean seams)
- You want 2-3 PRs shipped in one session with independent verification
- You have a clear contract and acceptance criteria
- The work doesn't need device testing or a specialist's session memory

**Do NOT use MORPH for:**
- UI/device work (needs emulator verification; see AXM-036 addendum)
- Anything that requires the Architect or builder to hold session state across runs
- Work that spans fuzzy domain boundaries

---

## Workflow

1. **Architect Phase** — Define contract, rubric, test strategy
2. **Build Phase** — Multiple builders work in parallel, each in its own worktree/branch
3. **Inspect Phase** — Fresh inspector per PR; grades ONLY against rubric + contract
4. **Merge Gate** — Human approves only PASS verdicts; FAIL = builder regroups or task reframes

---

## Step 1: Brief the Architect

Dispatch to an Architect specialist (e.g., Pierce) with:
- **Problem statement** — what needs to be built
- **Inputs** — designs, specs, existing code to reference
- **Deliverables** — list of services/modules/features
- **Constraints** — tech stack, APIs, external dependencies

The Architect locks:
- **Contract** — one file naming all functions/classes and their signatures
- **Rubric** — 5-10 checkable criteria; no "high quality", only measurable outcomes
- **Test strategy** — unit test structure, coverage targets, integration test scope
- **Domain gates** — if this involves money, security, or compliance: list what Ledger (or equivalent) must verify before merge

Architect delivers: `CONTRACT.md`, `RUBRIC.md`, `TEST_STRATEGY.md`, and one sample test so builders know the pattern.

---

## Step 2: Spawn Builders in Parallel

Once the Architect's contract ships, dispatch to 2-3 builder specialists (Nash, Wyatt, etc.) with:
- **Lane** — which services/modules this builder owns (carve the work cleanly)
- **Contract** — the signed contract from Step 1 (verbatim file)
- **Rubric** — the signed rubric (verbatim file)
- **Test strategy** — the test structure (verbatim file)
- **Clear instruction** — "Ship this lane. Every function in the contract must exist. Every test in the rubric must pass. No scope creep."

Each builder:
- Works in its own git worktree (`git worktree add builders/[name] -b [lane-branch]`)
- Runs `npm ci` locally (never through a shared junction; see AXM-036 lessons)
- Ships one PR per lane
- Includes test titles **verbatim from the rubric** so the inspector can match

---

## Step 3: Fresh Inspector per PR

Do NOT resume an inspector. For each PR:

1. Create a new session (or session context) with a fresh inspector (Vaughn, or another QA specialist)
2. Pass the inspector:
   - **ONLY:** the rubric, contract, PR diff, and repo path
   - **NEVER:** builder summary, T-Bot opinion, prior verdicts, or builder's intention
3. Inspector grades PR against rubric **only**
4. Verdict: PASS (merge) or FAIL (specific gap + retry)

Inspector output: `INSPECTION_VERDICT.md` — checkmark per rubric item or callout of unmet criteria.

---

## Step 4: Domain Gate (If Economics/Security/Compliance)

Before merging anything that touches:
- Money (pricing, fees, budgets, transfers)
- Security (auth, encryption, keys)
- Compliance (legal, regulatory, audit)

Dispatch to Ledger (or domain reviewer) with the merged code + the rubric. Ledger verifies:
- No optimistic assumptions in calculations
- No silent failures on edge cases
- Audit trail completeness

Ledger verdict gates merge.

---

## Step 5: Merge Only on PASS

Human (you) reviews inspector PASS verdicts and merges. If FAIL:
- Builder fixes the gap
- New PR on same branch (rebase-only re-inspection to avoid rebuild)
- New inspector for the revised PR
- Repeat until PASS

---

## Real-World Example

**Task:** Ship a subscription service (API + database schema + tests)

**Architect (Pierce):**
- Contract: `POST /subscriptions`, `GET /subscriptions/{id}`, `PATCH /subscriptions/{id}/cancel`, `GET /billing/invoices`
- Rubric: 10 items (each endpoint exists, cancellation idempotent, invoices include tax, refund logic handles prorations, etc.)
- Test strategy: Jest unit tests for business logic + integration tests hitting a test database
- Domain gate: Ledger must verify refund math and proration logic

**Builders (Nash, Wyatt):**
- Nash → API (endpoints + auth)
- Wyatt → Database schema + invoice generation
- Each ships a PR

**Inspector (Vaughn):**
- Gets rubric, contract, Nash's PR diff
- Checks: ✓ POST endpoint exists, ✓ returns 201, ✓ validates input, ✗ no refund endpoint (FAIL)
- Nash fixes, re-inspect (fresh inspector), PASS
- Vaughn inspects Wyatt's PR (database + invoices)
- Ledger verifies refund math before merge

**Result:** Two PRs, verified independently, merged in one session.

---

## Anti-Patterns (From Field Tests MIR-001 through MIR-004, AXM-036)

**Don't:**
- Share a single worktree across builders (npm ci gets wiped)
- Resume an inspector (start fresh every time; evidence is all you have)
- Pass builder commentary to the inspector (inspector grades rubric only)
- Use MORPH for UI work without emulator smoke tests in inspections
- Approve scope changes mid-build without Architect sign-off (Q-2 clause)

**Do:**
- Spell out test titles **verbatim from rubric** in code
- Pre-rebase before re-inspection (range-diff `=` means no rebuild needed)
- Have Ledger gate anything involving money
- Snapshot builder context (files, working state) before dispatch
- Carry earlier findings into later briefs (if an inspector caught a gap in PR 1, tell the next builder about it)

---

## When MORPH Pays Off

- **Speed:** 3 builders + inspector per PR = 2 clean merges in 2-3 hours
- **Independence:** Inspector never sees builder opinions; catches what builders miss
- **Audit trail:** Every verdict is checkable; every merge is gated
- **Learning:** Rubric becomes a living spec; next run is faster

---

## Resources

- `MORPH Protocol Verdict — MIR-001`: Early trial (MIRROR Phase 0, 8 PRs, 15 inspections, all clean by round 2)
- `MORPH Protocol Verdict — MIR-003`: Data validation (33 builders, outcome invariants beat rule lists)
- `MORPH Protocol Verdict — AXM-036`: UI lessons (requires emulator smoke; device-only bugs hid in proxy grades)
- `MORPH Protocol — Lessons from Axiom Twins`: Hard-won UI rules (node_modules junctions, UTF-8 checks, footer clipping at 360dp)
