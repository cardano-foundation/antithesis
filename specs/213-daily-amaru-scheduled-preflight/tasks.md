# Tasks — Issue 213 Daily Amaru scheduled preflight

Artifact ceiling: 4,000 bytes and 90 lines.

## Slice S213-01 — Scheduled preflight and identity boundary

- [ ] **T2131** Commit a complete executable RED proof covering both dated
  missing-`rg` incidents, silent-receipt rejection, missing identity, App
  wiring, credential non-persistence, effect counts, and CI reachability.
- [ ] **T2132** Make the scheduled dependency census explicit and ensure a
  missing required command exits non-zero with D213-01 before business effects.
- [ ] **T2133** Implement the dedicated D213-02 token-mint interface and keep
  D213-03 separate from same-repository identity without creating, installing,
  or configuring the App.
- [ ] **T2134** Preserve all existing controller guards while proving broken
  preconditions have zero business mutations/launches and the repaired changed
  path has exactly one fake and zero real launches.
- [ ] **T2135** Document the scheduled runner contract, dedicated App setup
  names/scope, loud failure behavior, secret handling, and still-open live gate.
- [ ] **T2136** Pass the immutable slice gate, full ticket gate, fresh Codex
  audit, final commit/tree proof, hosted exact-head checks, and resource census
  without a live dispatch or real launch.

The ticket owner checks these entries only after an exact candidate receives a
fresh `AUDIT-PASS`. The parked commit owner then includes the task stamp in the
single final squashed behavior commit.
