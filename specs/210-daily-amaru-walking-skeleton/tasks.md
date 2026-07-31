# Tasks — Issue 210 daily Amaru walking skeleton

## Slice 1 — Thin daily vertical controller

- [x] T2101 Add deterministic RED fixtures for changed, unchanged,
  zero/ambiguous observation, duplicate/same-day, same-SHA retry, and earlier
  stage failure behavior.
- [x] T2102 Implement one transport-injected daily state machine with an exact
  bare-upstream observation, durable day claim, last-success comparison, and
  fail-closed ordered stages.
- [x] T2103 Require an explicit cross-repository identity before mutation and
  implement the supervised exact-stock-pin, named bootstrap-check, SHA-image,
  and digest handoff without configuring credentials.
- [x] T2104 Implement atomic consumer repin preparation and exact-head named
  check verification with retained positive/non-zero #202 evidence; production
  must wait for guarded merge and expose no consumer self-merge operation.
- [x] T2105 Reuse the existing exact-main `cardano_amaru` workflow launch shape
  with duration one hour and faults enabled, while proving all tests/manual/PR,
  duplicate, failure, and pre-merge paths use only the fake launcher.
- [x] T2106 Produce the crude durable day receipt with exact revision, image,
  check, workflow, MOOG identity when observable, and honest partial/failure
  fields.
- [x] T2107 Wire one daily schedule, manual dry-run, and pull-request contract
  job to the same controller; add the operator document and all four exact
  replacement TODO owners.
- [x] T2108 Pass navigator-approved RED/GREEN, the immutable slice gate,
  ticket gate, commit gate, original #196/#202 hash checks, and create the one
  reviewed implementation commit.

## Ticket-owner finalization

The ticket owner stamps these tasks only after PAIR acceptance, then verifies
the exact amended commit, pushes it, refreshes the draft PR, and obtains
machine-recorded exact-head hosted checks. The epic owner owns independent
acceptance and guarded merge. Real MOOG submission is a post-merge parent
release, not an implementation task.
