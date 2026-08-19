# Tasks — Issue 223 manual production trigger and daily launch cap

Artifact ceiling: 3,000 bytes and 70 lines.

## Slice S223-01 — Manual production trigger with a code-enforced daily cap

- [ ] **T2231** Commit an executable RED proof of every invariant row against
  the unchanged base: routing census, dry-run byte-identity, cap under both
  triggers, supersede in all four states (unchanged head, changed head, legacy
  headless claim, post-launch day), fail-closed census, and head propagation.
- [ ] **T2232** Add the typed `workflow_dispatch` boolean input `production`
  (default `false`) and route `production=true` to the existing production job,
  leaving the dry-run job's step body byte-unchanged and serialising the
  concurrency group per the plan.
- [ ] **T2233** Derive, validate, and export the workflow head in
  `scripts/daily-amaru.sh` before the first transport child, refusing an
  unresolvable or malformed head at its own named stage with nothing claimed.
- [ ] **T2234** Implement the fail-closed marker census and the three claim
  operations with the supersede rule in `scripts/daily-amaru-github.sh`, and
  order the launch claim before the launcher in the controller.
- [ ] **T2235** Bring the deterministic fixture to the production claim-operation
  set, reconciled mechanically, and prove every protection able to fail with an
  applied-then-rejected mutant.
- [ ] **T2236** Keep every existing guard green and pass the frozen slice gate,
  the ticket gate, complete local CI, a fresh independent audit, the final
  tree/diff checks, and all six required contexts on the exact pushed head
  without dispatch, launch, spend, merge, or same-day rerun.

The ticket owner checks these entries only after an exact candidate receives a
fresh audit verdict and an acceptance decision. The parked commit owner then
includes the task stamp in the single final squashed behavior commit.
