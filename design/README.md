# design/ — Native Councils work branch

**Branch:** `native-councils-design` · cut from master @ v4.0.0 (3d66033) · 2026-08-31

This branch carries the complete design record for the next two releases, so any
Overmind session with this repo can take the build over from here. Nothing on
this branch ships to installs — auto-sync fires only on a version-bump PR merge
to master.

## Read in this order

1. **`FIELD_LEARNINGS_2026-08.md`** — everything learned running a live
   multi-Overmind council for a week, plus the venue tests that ground the
   design. The *why* behind every decision.
2. **`V4.0.1_MIGRATION_FIXES.md`** — the patch release. Small, fully specified,
   ships FIRST. A peer Overmind is holding its upgrade until this lands.
3. **`V4.1_NATIVE_COUNCILS_SPEC.md`** — the feature release: committees/councils
   as a built-in plugin feature over a shared folder, no server dependency.
   Includes the file-by-file build map.

## Sequencing (decided, not open)

- v4.0.1 first: branch → PR with version bump → merge (auto-sync rule).
- v4.1.0 second, built off this design. Both releases follow the standing
  release protocol in the repo's history: no zips in tree, no `hooks` field in
  plugin.json, validate before push, diff before push, releases land as
  version-bump PRs, never direct to master.

## Provenance note

These documents are scrubbed for a public repo: internal transport names, peer
identities, org systems, and machine paths from the originating environment
have been generalized. Every claim marked "observed" or "proven" has a live
receipt in the originating team's private records.
