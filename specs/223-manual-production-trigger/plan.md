# Plan — Issue 223 manual production trigger and daily launch cap

Artifact ceiling: 6,000 bytes and 130 lines.

## Strategy

Two absences in the current marker vocabulary cause the whole ticket: a marker
cannot say *this day already spent its launch*, and a marker cannot say *which
workflow head claimed it*. Add exactly those two facts, then let the existing
claim boundary — which already runs before every effect — carry the cap.

The trigger surface stays dumb. `production=true` selects the existing
production job and nothing else; every spend decision is made by
`scripts/daily-amaru.sh` and `scripts/daily-amaru-github.sh`, so the guarantee
is identical for a schedule and a dispatch by construction rather than by two
matching conditions.

## Ordering constraint that makes the cap fail closed

The launch claim is published BEFORE the launcher runs. An attempt that dies
between claiming and launching has consumed the day. This deliberately
over-counts rather than under-counts: an unspent day costs one day of latency,
a double launch costs real money.

Symmetrically, an unresolvable current head refuses the claim. Only a *recorded*
head may be absent (legacy markers); the *current* head never may.

## Live boundary

GitHub's expression evaluator is not executable here. The proof extracts the
exact `if:` condition strings from the workflow and evaluates them with a small
pure truth table, so a wrong condition in the file is caught, while the
evaluator itself is the residual. The first real `production=true` dispatch —
fired by the epic owner after merge, never by this ticket — is that boundary's
smoke. Keep both conditions simple enough to read as a truth table.

`inputs.production` is the boolean-typed dispatch input. `github.event.inputs.production`
is the string form and must not be used: it is `'false'`, which is truthy.

## Slice S223-01 (single, bisect-safe)

Trigger input, routing, head derivation, the three claim operations, the
fixture, and the proofs land together. Splitting them would ship a trigger
without its cap or a cap without its trigger; neither half is safe to merge
alone, and NOTE-029 wants the smallest honest whole thing today.

Order inside the slice:

1. RED: the complete executable proof of every invariant row, red for the
   right reason against the unchanged base.
2. GREEN: workflow input and routing; controller head derivation, export, and
   claim-gate ordering; transport census and the three claim operations;
   fixture parity.
3. Mutants: each protection shown able to fail, each mutation proved applied.

## Constraints

- `tests/test-daily-amaru.sh` is the home for every new proof: it is the only
  proof this repository executes in hosted CI (the `Daily Amaru contract dry
  run` job), and it already owns both controller cases and workflow-file
  assertions. `tests/test-workflow-validation.sh` runs only in local CI; do not
  put a spend protection where hosted CI cannot see it.
- Reuse the existing harness vocabulary — `run_case`, `run_hermetic_case`,
  `assert_no_launch`, `assert_no_mutation`, the receipt oracle, the
  applied-then-rejected mutant pattern. Do not build a second framework.
- The production transport is exercised with the deterministic fake `gh`
  fixture, never a real one.
- Keep the production job's job id `daily-amaru-scheduled` stable. Its `name:`
  may become `Daily Amaru production run`; that context is not merge-required
  (the six required contexts are fixed and unrelated).
- `concurrency.group` drops `github.event_name` so a dispatch and a schedule on
  the same ref serialize instead of racing the check-then-write claim. A queued
  dry run behind a production run is accepted cost.
- `DAILY_AMARU_ALLOW_REAL` is set by the existing suite and read by nothing.
  It is a dead variable, not a protection; do not build on it and do not change
  it here. Reported to the epic invariant ledger as an observation.

## Risks

- **Same-day attempted-SHA block.** Requirement 3 is unsatisfiable in practice
  unless the attempted-SHA marker supersedes under the same rule: after the
  2026-08-19 pre-launch death, upstream may not have moved, so a re-attempt
  would die at `launch-attempt` even with the day superseded. The supersede
  rule therefore governs every pre-launch gate marker — day claim and
  attempted-SHA claim alike. Ticket-owner ruling, reported upward, not a scope
  change: without it the issue's own acceptance bullet cannot be met.
- **Check-then-write race.** Two runners can both read an unclaimed day. The
  concurrency group removes the realistic case; the pre-launcher claim narrows
  the remainder. Residual, named, not eliminated.
