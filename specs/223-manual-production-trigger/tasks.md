# Tasks — Issue 223 manual production trigger and daily launch cap

Artifact ceiling: 3,000 bytes and 70 lines.

## Slice S223-01 — Manual production trigger with a code-enforced daily cap

- [x] **T2231** Commit an executable RED proof of every invariant row against
  the unchanged base: routing census, dry-run byte-identity, cap under both
  triggers, supersede in all four states (unchanged head, changed head, legacy
  headless claim, post-launch day), fail-closed census, and head propagation.
- [x] **T2232** Add the typed `workflow_dispatch` boolean input `production`
  (default `false`) and route `production=true` to the existing production job,
  leaving the dry-run job's step body byte-unchanged and serialising the
  concurrency group per the plan.
- [x] **T2233** Derive, validate, and export the workflow head in
  `scripts/daily-amaru.sh` before the first transport child, refusing an
  unresolvable or malformed head at its own named stage with nothing claimed.
- [x] **T2234** Implement the fail-closed marker census and the three claim
  operations with the supersede rule in `scripts/daily-amaru-github.sh`, and
  order the launch claim before the launcher in the controller.
- [x] **T2235** Bring the deterministic fixture to the production claim-operation
  set, reconciled mechanically, and prove every protection able to fail with an
  applied-then-rejected mutant.
- [x] **T2236** Keep every existing guard green and pass the frozen slice gate,
  the ticket gate, complete local CI, a fresh independent audit, the final
  tree/diff checks, and all six required contexts on the exact pushed head
  without dispatch, launch, spend, merge, or same-day rerun.

The ticket owner checks these entries only after an exact candidate receives a
fresh audit verdict and an acceptance decision. The parked commit owner then
includes the task stamp in the single final squashed behavior commit.

S223-01 ships with one accepted residual, `FU-223-EFFECT-CENSUS-CONTROL`
(`INV-223-SCOPE-AND-EFFECT-FENCE`, ADVISORY): the whole-suite effect census
discovers its own subject with `find` and never requires the discovered set to
be non-empty, so a pattern matching nothing would print `effect_artifacts=0
forbidden_effects=0` — absence of evidence rendered as evidence of absence.
Owner: the #205 epic invariant ledger. Property class: a census that discovers
its own subject must assert the subject set is non-empty and be shown able to
detect a positive. The green that ships establishes that 117 effect artifacts
were inspected and none carried a forbidden effect or credential sentinel, and
that the path half of the fence rejects an injected out-of-fence path; it does
not establish that this census would notice a forbidden effect. The underlying
no-effect property remains independently protected by the pre-existing per-case
business-effect guards, proved to fire.
