# Tasks — Issue 221 Daily Amaru derived-day propagation

Artifact ceiling: 3,000 bytes and 70 lines.

## Slice S221-01 — Export the derived day and prove the omitted-day path

- [x] **T2211** Commit an executable RED proof that, with `DAILY_AMARU_DAY`
  absent and a deterministic fake `date` supplying the day, the controller
  fails with the production fingerprint
  `DAILY_AMARU_DAY: DAILY_AMARU_DAY is required` at
  `stage=bootstrap-proposal` / `outcome=FAILED` / `error=proposal-failed`.
- [x] **T2212** Make the deterministic fixture transport observe the day seam
  with the production expansion, and permanently reconcile the operation set
  that requires the day against `scripts/daily-amaru-github.sh`.
- [x] **T2213** Export the validated derived day from `scripts/daily-amaru.sh`
  before the first transport child, changing no other controller semantics.
- [x] **T2214** Prove permanently that both `propose-bootstrap` and
  `prepare-consumer-repin` observe the derived day, that the remove-propagation
  mutant is applied and rejected, and that the issue #210 day claim and ordered
  stage receipts survive a forced downstream failure with no launcher reached.
- [x] **T2215** Keep every existing guard green and pass the frozen slice gate,
  the ticket gate, complete local CI, a fresh independent audit, the final
  tree/diff checks, and all six required contexts on the exact pushed head
  without dispatch, launch, spend, merge, or same-day rerun.

The ticket owner checks these entries only after an exact candidate receives a
fresh audit verdict and an acceptance decision. The parked commit owner then
includes the task stamp in the single final squashed behavior commit.

T2214 ships with one accepted residual, `CNA205-DAY-SOURCE-NONCE-01`: the
regression cannot distinguish an implementation that invokes and discards the
declared date source and then recomputes an equivalent day. Owner: the #205
epic invariant ledger. The green that ships beside it proves the day crosses
the process boundary, not that it was consumed from the declared source.
