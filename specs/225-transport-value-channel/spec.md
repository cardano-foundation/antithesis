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

## Discovered constraint — the inherited scope fence

`tests/test-daily-amaru.sh` carries `issue_223_allowed_paths`, an allow-list of
every path permitted to differ from `pre_slice_base=cd8144b`. It was frozen for
#223 and now judges #225's tree: the planning commit alone reds it with
`changed path outside #223 fence`.

| ID | Invariant | Fails when | Holds when |
|---|---|---|---|
| INV-225-D1 | The daily-loop scope fence judges **this** slice, not a merged one | the fence's base or allow-list still describes #223, so a correct #225 candidate is rejected by construction; or the fence is weakened into something that cannot reject an out-of-scope path | the base is this slice's pre-slice base `01f96e4`, the allow-list is exactly the paths this slice changes, the existing `scope-path-outside-fence` mutant is still rejected, and `dry_run_steps_identical` still holds against the new base |

Re-basing the fence per slice is in scope for this campaign. Growing the
allow-list against an ever-older base is not: it would make the fence weaker
every ticket. Identifier naming is the commit owner's choice.

## Slice S2 — the boundary proof must be hermetic

`7c56594` was green under the local ticket gate and red in CI:
`FAIL: fixed controller recorded no bootstrap candidate (error=missing-command-rg rc=1)`
(run 32271362864). Reproduced locally by hiding `rg` from the fixture's PATH.

`prepare_case` builds `PATH="$bin:$PATH"`, so the boundary proof inherits host
binaries. The nix dev shell has ripgrep; the GitHub runner does not. The `just ci`
leg of the gate runs in the dev shell and therefore cannot observe this class at
all — the gate was green by construction, not by evidence.

This is the same root the submission-2 auditor proposed as CAND-225-3: the
fixture's PATH construction decides which binaries are actually invoked, and
nothing asserts the answer.

| ID | Invariant | Fails when | Holds when |
|---|---|---|---|
| INV-225-E1 | The boundary proof's verdict does not depend on any host-provided binary | removing a member of the transport's `scheduled_command_census` from the host PATH changes the proof's outcome | the fixture seeds every command the proof's operations need and inherits nothing; the proof produces the same verdict under a PATH containing only what it seeds |
| INV-225-E2 | The stand-ins are the binaries actually invoked (ratifies CAND-225-3) | a dangling symlink, a relative root, or an unseeded name silently reaches a real `gh`, `nix` or `docker` | before any operation runs, the proof asserts that `command -v` for each stand-in resolves inside its own bin, and this assertion is shown able to fail |

INV-225-E2 is the load-bearing half. E1 without E2 is a promise; E2 makes the
proof state, per run, which binaries it actually used.

### S2 mandate v2 — sharpened after submission 1's findings

Submission 1 (`3184b07`) fixed `rg` and left the class open. The audit
(`55881e6c…`) showed the fixture resolves each seeded command against the
inherited host PATH and, when one is absent, **fabricates** `#!/bin/sh\nexit 0`.
Nine of the fifteen `scheduled_command_census` members still changed the
proof's verdict when ablated, and the `jq` case produced
`error=proposal-failed` — an infrastructure failure reported as a domain
verdict, which is strictly worse than the `missing-command-rg` it replaced.

E1 and E2 keep their meaning. These clauses make the failure modes explicit and
add the evidence contract the third finding exposed.

| ID | Invariant | Fails when | Holds when |
|---|---|---|---|
| INV-225-E1 (v2) | Every seeded command is bound to a binary the proof **proved exists**, and the proof dies naming the command when it cannot | "seeded" means only that an entry exists in the bin; an absent command is silently replaced by a success-returning stand-in; ablating any member of the transport's `scheduled_command_census` changes the verdict | ablating **each** of the 15 census members in turn leaves the verdict identical to the unablated control, and a command that cannot be bound is a named, loud death |
| INV-225-E2 (v2) | The stand-ins are the binaries actually invoked, against **all three** named substitution modes | any of — a dangling symlink, a **relative** bin root, or a fabricated no-op substitute — is accepted; or any of the three has no mutant | each of the three modes is rejected, and each rejection is demonstrated by its own mutant |
| INV-225-E3 (ratifies CAND-225-5) | Every count in a proof marker is produced by the executed path it summarizes | a field is a constant, or a length of a declared list; deleting the code path the field reports leaves the marker byte-identical | deleting the reported path changes the number or reds the run, shown by a mutant that verifies its own edit applied |

INV-225-E3 is general, not local to this fixture: gate v3's own comment already
states the rule for `VALUE-CHANNEL` and the leg immediately below it did not
enforce it. That gap was the ticket owner's, and gate v4 closes it.

`tests/test-daily-amaru.sh`'s `seed_scheduled_path` carries the same
`stub_command` fallback. It is **out of scope here** — no assertion was shown to
mis-verdict because of it — and is routed to the epic owner with INV-225-E1's
property class attached.

## Slice S3 — the ablation count must be the ablation

The S2 owner campaign closed at submission 2/2. E1 v2 and E2 v2 are closed:
`stub_command` is gone from the fixture, an unbindable seeded command now dies
naming itself instead of mis-verdicting as `proposal-failed`, and all three
substitution modes are rejected with their own mutants.

One row stayed open. `census_ablated=` is the **loop trip count**, not the
ablation re-run. Deleting the only re-run call leaves `census_ablated=15`
unchanged while `seeded=` drops 792→462 and `standins_verified=` drops 136→76 —
proving those two are derived and this one is not. Gate v4's
`census_ablated>=15` leg is therefore satisfied by a run that never re-checked
a verdict under an ablated host PATH.

This is INV-225-E3's own class, recurring inside the field that was added to
close INV-225-E1 v2. That recurrence is the point: the rule was stated, enforced
in one place, and re-broken in the next field written. It closes mechanically or
it keeps coming back.

| ID | Invariant | Fails when | Holds when |
|---|---|---|---|
| INV-225-E3 (scope unchanged, now enforced on `census_ablated`) | Every count in a proof marker is produced by the executed path it summarizes | deleting the ablation re-run leaves `census_ablated` unchanged and the run green | deleting the ablation re-run either moves `census_ablated` or reds the run, proved by a mutant that verifies its own edit applied |

The intact code does perform the 15 re-runs — the 792→462 drop is the evidence.
This slice does not add coverage; it makes the marker require the coverage that
already happens, so a later edit cannot quietly remove it.
