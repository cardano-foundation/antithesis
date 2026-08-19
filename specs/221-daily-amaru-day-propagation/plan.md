# Plan — Issue 221 Daily Amaru derived-day propagation

Artifact ceiling: 6,000 bytes and 150 lines.

## Technical context

Frozen base `7ac049e748ff83ab12dee2864343510d6fb9541e`; refreshed
`origin/main` and the GitHub API head both resolve to it. Lane worktree
`/code/cardano-node-antithesis-issue-221`, branch
`fix/221-daily-amaru-day-propagation`.

Baseline `nix develop --quiet -c just ci` at that base exits 0 in 17.4 s
(evidence `evidence/baseline-ci.log` under the ticket runtime root), so the
starting tree is green and any red is caused by this ticket.

`scripts/daily-amaru-github.sh` and `.github/workflows/daily-amaru.yaml` are
read-only contract surfaces. The workflow supplying no day is correct by #213:
no external `date` may stand before the controller's first receipt boundary.
The defect is entirely on the controller side of the process boundary.

## Architecture decisions

- The controller keeps deriving and validating the day exactly as today and
  additionally promotes that validated value into the process environment,
  before the first `transport_call`. Nothing else about derivation, validation,
  ordering, staging, receipts, identity, or launch changes.
- The transport contract is unchanged: the day continues to travel in the
  process environment, never as a command-line argument, and never through a
  file. See `modules-model.md` and `data-model.md`.
- The deterministic fixture transport becomes able to observe the seam. It
  binds the day with the identical expansion the production transport uses, in
  exactly the operations production binds it in, and records the observed value
  in the existing effect log. The operation set is derived mechanically from
  the production transport source rather than restated by hand, so the fixture
  cannot drift into being unable to fail.
- No function signature is created or changed, so no `functions-model.md` is
  introduced. `modules-model.md` and `data-model.md` carry the only changed
  rows.

## Proof strategy

One bisect-safe slice. The commit owner writes the complete RED proof first and
watches it fail for the stated reason before any production edit.

The permanent regression exercises the production shape the suite never had:

1. **Success path, day omitted.** A deterministic fake `date` is prepended to
   `PATH`; `DAILY_AMARU_DAY` is absent from the controller environment. The
   controller must run to completion through the fixture transport, and both
   `propose-bootstrap` and `prepare-consumer-repin` must report the exact
   derived day. The fake day is a fixed past date, distinct from the real
   system UTC day and from every day literal already used by the suite, so an
   observed match cannot come from an injected constant or from the real clock.
2. **Failure path, day omitted.** The same shape with a forced downstream
   transport failure at the bootstrap proposal. The #210 day claim must carry
   the derived day, the ordered stage receipts must still be published, the
   durable receipt must satisfy the existing receipt oracle as an honest
   failure, and no launcher may be reached.
3. **Killing mutant.** A copy of the controller with only the propagation
   removed, proved applied, must fail case 1 with stderr fingerprint
   `DAILY_AMARU_DAY: DAILY_AMARU_DAY is required` and the production receipt
   triple `stage=bootstrap-proposal` / `outcome=FAILED` /
   `error=proposal-failed` — the exact shape of run `32215848871`.
4. **Fixture reconciliation.** The set of transport operations that bind
   `DAILY_AMARU_DAY:?DAILY_AMARU_DAY is required` in the production transport
   is computed from source and must equal the set that binds it in the fixture,
   and must be non-empty. This is the permanent guard against the fixture
   quietly losing the ability to observe the defect.

Each case prints a machine-readable census line so a pass carries evidence and
selection is provable. The frozen slice gate greps those census lines, checks
that the export exists exactly once and lexically precedes the first
`transport_call`, enforces the changed-path fence, and runs the focused suite
plus complete local CI.

## Slice

- **S221-01 — Export the derived day and permanently prove the omitted-day
  path.** Proof, production, and fixture-observability change land in one
  bisect-safe commit; splitting them would leave a committed proof that cannot
  run or a production change with no proof.

## Constraints and risks

- The fixture is test infrastructure, not the production transport: its
  authority over the contract comes only from the reconciliation in step 4.
  Without that reconciliation the mutant could stop being killable without
  anything going red.
- Prepending a fake `date` must not disturb the rest of the seeded command
  surface; only the controller's own `date -u +%F` derivation is redirected.
- The new cases must not alter existing log-count assertions. Existing
  `mutation:` patterns are unanchored at their right edge, so appended fields
  are compatible; the commit owner must verify that rather than assume it.
- Schedule pressure toward `2026-08-20T04:17Z` does not weaken RED/GREEN,
  audit, exact-head CI, or guarded merge. The controller must not be fired
  after merge.

## Status

- **Completed:** lane, green baseline, ticket contract, frozen falsified gate.
- **Current:** commit-owner campaign for S221-01.
- **Blockers:** none.
