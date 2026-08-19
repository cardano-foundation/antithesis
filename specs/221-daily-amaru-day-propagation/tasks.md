# Tasks — Issue 221 Daily Amaru derived-day propagation

Artifact ceiling: 3,000 bytes and 70 lines.

## Slice S221-01 — Export the derived day and prove the omitted-day path

- [ ] **T2211** Commit an executable RED proof that, with `DAILY_AMARU_DAY`
  absent and a deterministic fake `date` supplying the day, the controller
  fails with the production fingerprint
  `DAILY_AMARU_DAY: DAILY_AMARU_DAY is required` at
  `stage=bootstrap-proposal` / `outcome=FAILED` / `error=proposal-failed`.
- [ ] **T2212** Make the deterministic fixture transport observe the day seam
  with the production expansion, and permanently reconcile the operation set
  that requires the day against `scripts/daily-amaru-github.sh`.
- [ ] **T2213** Export the validated derived day from `scripts/daily-amaru.sh`
  before the first transport child, changing no other controller semantics.
- [ ] **T2214** Prove permanently that both `propose-bootstrap` and
  `prepare-consumer-repin` observe the derived day, that the remove-propagation
  mutant is applied and rejected, and that the issue #210 day claim and ordered
  stage receipts survive a forced downstream failure with no launcher reached.
- [ ] **T2215** Keep every existing guard green and pass the frozen slice gate,
  the ticket gate, complete local CI, a fresh independent audit, the final
  tree/diff checks, and all six required contexts on the exact pushed head
  without dispatch, launch, spend, merge, or same-day rerun.

The ticket owner checks these entries only after an exact candidate receives a
fresh `AUDIT-PASS`. The parked commit owner then includes the task stamp in the
single final squashed behavior commit.
