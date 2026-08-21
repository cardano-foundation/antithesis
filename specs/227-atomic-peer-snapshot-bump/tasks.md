# Tasks — Issue 227 atomic peer-snapshot bump

Artifact ceiling: 3,000 bytes and 70 lines.

## Slice S227-01 — Atomic resolved bootstrap proposal

- [ ] **T2271** Commit a complete executable RED proof for the exact PR #86
  lock-only shape, a verified-applied skip-resolver mutant, inconsistent pin
  tuples, split/extra paths or commits, and injected resolver failure.
- [ ] **T2272** Invoke the cloned bootstrap repository's unmodified shipped
  resolver after the Amaru override and pair the lock with exactly its selected
  configurations revision and regenerated record.
- [ ] **T2273** Create and adopt only one-commit proposals whose changed-path
  census is exactly `flake.lock` plus
  `nix/peer-snapshots/resolution.json`; reject every incoherent branch as
  foreign.
- [ ] **T2274** Preserve resolver failure as
  `error=peer-snapshot-resolution-failed` with zero push/PR/launch effects and
  no receipt-schema, cap, supersede, credential, workflow, resolver, or anchor
  change.
- [ ] **T2275** Pass the frozen gate and direct full Daily Amaru suite, receive
  a fresh independent audit, finalize one behavior commit, and obtain all
  required hosted contexts on its exact head. Name the A-001 local cold-Nix
  omission in the gate receipt and PR body.

The ticket owner checks these tasks only after a fresh audit passes the exact
candidate. The parked commit owner then includes this task stamp in the final
squashed commit.
