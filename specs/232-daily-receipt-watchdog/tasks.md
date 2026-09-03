# Tasks — Issue 232 independent daily receipt watchdog

Artifact ceiling: 3,000 bytes and 75 lines.

## Slice S232-01 — Independent able-to-fail watchdog

- [ ] **T2321** Commit the complete executable RED proof for absent, repeated
  absent, restored present, no-producer-run, timestamp/day/marker matching,
  pagination, boundary failures, and public-safe evidence.
- [ ] **T2322** Add the independently scheduled watchdog workflow with its own
  UTC schedule, minimal permissions, non-cancelling concurrency, direct script
  caller, always-uploaded evidence, and proof-only manual path.
- [ ] **T2323** Implement previous-UTC-day derivation and complete canonical
  receipt observation against dated cna#210 receipt comments without consuming
  producer run, property, digest, or correlation state.
- [ ] **T2324** Implement fail-closed `PRESENT`/`ABSENT`/`ERROR` verdicts and
  canonical marked-incident reconciliation with idempotent per-day history and
  no automatic closure.
- [ ] **T2325** Permanently prove the alarm fires and exits non-zero when the
  synthetic receipt is omitted, repeated absences update one incident, restored
  presence is visibly green, and absence is detected when no producer run
  exists.
- [ ] **T2326** Wire the focused proof and mutation controls into canonical CI,
  preserve every producer/cna#202 boundary, and pass the immutable slice gate
  plus fresh independent audit.
- [ ] **T2327** Finalize one behavior commit, push the exact accepted head,
  obtain required hosted contexts, merge through protection, then run the
  proof-only workflow on the exact merged head and retain its red/green
  artifact identity.

The ticket owner checks these tasks only after a fresh audit passes the exact
candidate. The parked commit owner then includes the task stamp in the final
squashed commit.
