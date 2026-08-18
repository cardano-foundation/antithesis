# Tasks — Issue 219 Daily Amaru workflow validation

Artifact ceiling: 3,500 bytes and 90 lines.

## Slice S219-01 — Evaluation repair and permanent workflow guard

- [x] **T2191** Commit and preserve an executable RED proof that actionlint
  rejects both exact merged `${{ runner.temp }}` scheduled-job-env bindings.
- [x] **T2192** Initialize Daily Amaru state and receipt paths only after runner
  allocation while preserving their values and all controller semantics.
- [x] **T2193** Add the pinned repository-wide Actions validator with complete
  `.yaml`/`.yml` enumeration, positive census evidence, narrow documented
  legacy baselines, and a non-zero empty-census result.
- [x] **T2194** Wire the validator into the required `Check code quality`
  context and the complete local CI command; prove the exact defect, empty
  census, and orphaned required-job caller are red.
- [x] **T2195** Keep the full Daily Amaru controller and named-credential
  controls green and document why runner-scoped paths are initialized only
  after allocation.
- [x] **T2196** Pass the frozen gate, complete local gate, fresh independent
  audit, final tree/diff checks, exact-head hosted Daily Amaru job census, and
  all six required contexts without App/secret setup, live dispatch, spend,
  merge, or production execution.

The ticket owner checks these entries only after an exact candidate receives a
fresh `AUDIT-PASS`. The parked commit owner then includes the task stamp in the
single final squashed behavior commit.
