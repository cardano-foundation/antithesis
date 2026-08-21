# Tasks — Issue 229 bounded bootstrap-check observation

Artifact ceiling: 2,500 bytes and 60 lines.

## Slice S229-01 — Bounded observation state machine

- [ ] **T2291** Commit a complete executable RED proof for
  not-yet-reported→success, not-yet-reported→failure, never-reported at the
  derived deadline, transient/persistent transport errors, and exact unique
  success.
- [ ] **T2292** Derive a finite observation window from candidate-relevant
  observed or declared check-duration evidence and expose executed poll/sleep
  counts so no fixed or unbounded wait can pass vacuously.
- [ ] **T2293** Make `require-bootstrap-checks` proceed only for all-required
  exact success and fail closed with distinct named `failed`,
  `never-reported`, and transport-exhausted outcomes.
- [ ] **T2294** Apply and kill the immediate single-shot mutant reproducing
  fire-4, including the explicit not-yet-reported negative control and
  hermetic zero-external-effect boundary.
- [ ] **T2295** Preserve required-check membership, candidate construction,
  receipt schema, cap/supersede semantics, credentials, and every forbidden
  surface; pass direct focused verification and a fresh independent audit.
- [ ] **T2296** Finalize one behavior commit, push the exact accepted head,
  and obtain all required hosted contexts while naming the authorized local
  cold-Nix omission.

The ticket owner checks these tasks only after a fresh audit passes the exact
candidate. The parked commit owner then includes the task stamp in the final
squashed commit.
