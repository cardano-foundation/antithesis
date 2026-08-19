# Fix transport stdout pollution and make bootstrap proposal re-attempt-safe

Issue: cardano-foundation/cardano-node-antithesis#225 · parent epic #205
Base: `01f96e4` (carries #223 cap/supersede)

## Context

The first `production=true` fire (run 32261172699) progressed past every prior
failure point and then died at `bootstrap-proposal: malformed-candidate-sha`
with the day's launch allowance unconsumed. Two independent defects are exposed.

## Requirements

### R-225-1 — transport value channel

The transport returns operation values on stdout. A value-returning operation
must emit **exactly** its value there and nothing else, whatever any subcommand
it invokes writes to its own stdout.

- R-225-1a: every value-returning operation named in `data-model.md` emits its
  exact value on stdout when every external command it invokes is noisy on both
  streams.
- R-225-1b: the separation is one structural mechanism owned by the transport,
  not per-subcommand redirection. A newly added operation that writes a value
  with a plain `printf` to fd 1 must lose that value (loud, testable) rather
  than silently inherit a polluted channel.
- R-225-1c: the audit covers **every** operation in the `case` dispatch, not
  only `propose-bootstrap`. Known unfired instances of the same class are
  recorded in `data-model.md`.

### R-225-2 — re-attempt-safe bootstrap proposal

`propose-bootstrap <upstream-sha>` is idempotent per upstream SHA. Given the
per-SHA proposal branch on the bootstrap remote:

- R-225-2a **adopt**: the branch exists and its delta from its merge base with
  `origin/main` is exactly `flake.lock`, whose stock `pragma-org/amaru` node is
  locked to `<upstream-sha>` → return that branch head, create no commit, push
  nothing, and reuse the existing PR through the existing find path.
- R-225-2b **foreign**: the branch exists with any other content → fail with the
  stable named red `foreign-proposal-branch` on the diagnostic stream, emit no
  value, and leave the remote branch untouched. Never force-push or overwrite.
- R-225-2c **fresh**: the branch is absent → today's create/commit/push/PR path,
  unchanged in observable outcome.

## Rejection behaviour

- A polluted value channel must not be repairable by relaxing the controller's
  validation. The controller's `^[0-9a-f]{40}$` guards stay as they are.
- A foreign proposal branch is terminal for the run. It is never renamed,
  deleted, force-updated, or worked around.

## Observable success

- `nix develop --quiet -c just ci` green in the issue worktree.
- All six required PR contexts green on the exact pushed head.
- The regression proves both classes closed with mutants: a pollution-restoring
  mutant reproduces exactly `malformed-candidate-sha`; adopt, foreign and fresh
  are each shown able to fail.

## Constraints (from the issue and the parent brief)

- Same code path for `schedule` and `workflow_dispatch`; no probe-only fork.
- No receipt-schema change; `receipt_keys` in `scripts/daily-amaru.sh` unchanged.
- Issue #210 receipts preserved.
- The existing ab PR#81 must be adoptable by the re-attempt, not duplicated.
- No real Antithesis launch from tests; no network; no credentials.
- The #223 one-launch-per-day cap and the #221/#219/#223 guarantees untouched.
- `lambdasistemi/amaru-bootstrap` is read-only evidence. Adoption is proven with
  local fixtures and mutants, never by touching the live PR or branch.
- A history-reading check must survive a shallow checkout.

## Invariants

Each must be proved able to fail. "Fails when" is the observable red.

| ID | Invariant | Fails when | Holds when |
|---|---|---|---|
| INV-225-A1 | A value-returning operation's stdout is exactly its value | any subcommand's stdout reaches the transport's stdout | the controller's capture matches the operation's declared value shape byte-for-byte |
| INV-225-A2 | The value channel is closed for **every** value-returning operation in `D-225-2`, not only the fired one | any listed operation, run with noisy external commands, emits more or less than its value | the census over the complete table is green, and the table is the complete `case` dispatch |
| INV-225-A3 | The fired defect is reproducible and closed | a mutant restoring the `propose-bootstrap` pollution does **not** reproduce `malformed-candidate-sha` — that would mean the proof is not observing the real defect | the mutant reproduces exactly `bootstrap-proposal: malformed-candidate-sha`, and the unmutated code does not |
| INV-225-B1 | An existing valid per-SHA proposal branch is adopted | a same-SHA re-attempt commits, pushes, force-updates, opens a second PR, or returns a head other than the existing branch's | the emitted value is the existing branch head, the remote ref is byte-identical afterwards, and the existing PR URL is reused |
| INV-225-B2 | A foreign branch is a loud named red | foreign content is adopted, overwritten, force-pushed, or reported as a generic failure | the run fails with `foreign-proposal-branch` on the diagnostic stream, emits no value, and the remote ref is unchanged |
| INV-225-B3 | An absent branch still takes the create path | the fresh path regresses in observable outcome | branch created, single `flake.lock` commit pushed, PR opened, head emitted |
| INV-225-B4 | Classification precedes mutation | the branch is classified after a local commit or after a push attempt | the foreign case is detected with zero write effects recorded against the remote |
| INV-225-C1 | One code path for `schedule` and `workflow_dispatch` | a probe-only fork or a mode-conditional branch appears in the proposal path | the existing routing proof stays green with no new mode conditional |
| INV-225-C2 | No real Antithesis launch from tests | any proof reaches a real workflow dispatch | the effect censuses record zero real launches |
| INV-225-C3 | #210 receipts preserved | `receipt_keys`, a stage name, or a controller validation regex changes | the receipt field set and order are identical to base `01f96e4` |
