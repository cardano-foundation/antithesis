# Issue 223 — Manual production trigger with a code-enforced daily launch cap

Artifact ceiling: 11,000 bytes and 190 lines.

## Priority story

As the Daily Amaru operator, I can fire the production path on demand from
`workflow_dispatch` with `production=true`, through the exact code path the
04:17Z schedule uses, while the controller itself — not the trigger surface —
guarantees at most one real Antithesis launch per UTC day.

## Why now

Desk ruling NOTE-029 (2026-08-19) partially reverses the schedule-only rule:
the schedule remains the routine driver, a manual test path is added, and the
spend cap moves out of "only the schedule can fire" and into code.

The first production fire (run `32215848871`, 2026-08-19) died at
`bootstrap-proposal` before any launch. Issue #210 therefore carries a claim
for 2026-08-19 whose real-run allowance is unconsumed, and the current
`claim-day` refuses the day outright. Under this contract that exact state —
a pre-launch death whose workflow head has since moved — becomes re-attemptable.

## Current mechanics (discovered, not assumed)

`scripts/daily-amaru.sh` claims the UTC day at its `day-claim` stage, long
before the launcher at its `launch` stage. `scripts/daily-amaru-github.sh`
implements every claim as an exact-line marker comment on issue #210:

- day claim: `<!-- daily-amaru day=<day> claim -->`
- attempted upstream SHA: `<!-- daily-amaru attempted-sha=<sha> -->`
- last success: `<!-- daily-amaru last-success sha=<sha> -->`
- receipts: `<!-- daily-amaru receipt -->` plus `- key=value` lines

No marker distinguishes *claimed* from *launched*, and no marker records the
workflow head that claimed it. Those two absences are what this ticket adds.

## Functional requirements

- **FR-223-01 — Manual production trigger.** `.github/workflows/daily-amaru.yaml`
  declares a `workflow_dispatch` boolean input `production` defaulting to
  `false`. `production=true` runs the existing production job — the same job,
  steps, environment, and `scripts/daily-amaru.sh` invocation the schedule
  uses. No second production job, no duplicated steps, no parallel path.
- **FR-223-02 — Unchanged dry-run default.** With `production=false`, and for
  every `pull_request` event, exactly the existing dry-run job runs and its
  step body is byte-unchanged. The production job does not run.
- **FR-223-03 — Trigger-independent cap.** At most ONE real Antithesis launch
  per UTC day, enforced in the controller's claim/marker code and identical for
  `schedule` and `workflow_dispatch`. A second same-day attempt that would
  launch fails closed, before reaching the launcher, with a named stage and
  error in the durable receipt.
- **FR-223-04 — Pre-launch-death supersede.** A day whose claim came from an
  attempt that died BEFORE the launcher is re-attemptable if and only if the
  workflow head differs from the head recorded on that claim. The re-attempt
  appends a superseding claim naming the previous head; a claim carrying no
  recorded head (every marker written before this change, including
  2026-08-19) counts as a differing head. Nothing on issue #210 is deleted or
  rewritten: both attempts' markers and receipts survive.
- **FR-223-05 — Post-launch finality.** Once a real launch is claimed for a UTC
  day, that day is never superseded again that day, whatever the workflow head
  is. The launch claim is written and durably published BEFORE the launcher is
  invoked, so an attempt that dies at or after the launch consumes the day.
- **FR-223-06 — Fail-closed census.** A marker census that cannot be read
  refuses the claim. An unreadable, failed, or empty-on-error census is never
  read as "no marker present".
- **FR-223-07 — Head crosses the process boundary.** The controller derives the
  workflow head once, validates it as 40 lowercase hex, exports it before the
  first transport child is forked, and fails closed with a named stage when it
  cannot be resolved. This is the #221 defect class; it must not be recreated.
- **FR-223-08 — Preserved semantics.** Receipt vocabulary, marker vocabulary,
  stage order, exit semantics, and every existing guard — no-effect,
  no-real-launch, duplicate-day, attempted-SHA, credential, preflight, day
  propagation — remain green and unweakened. The only receipt-schema change is
  the supersede/launch-claim addition.
- **FR-223-09 — Fenced proofs.** No test reaches a real Antithesis launch, a
  real GitHub dispatch, an external repository mutation, or credential
  material.
- **FR-223-10 — Green gates.** The focused controller suite and complete local
  CI are freshly green, the frozen slice gate and ticket gate are freshly
  green, the finalization audit passes, and all six required GitHub contexts
  (`Build`, `Run unit Tests`, `Check code quality`, `Compose smoke test`,
  `publish-images`, `build-docs`) are green on the exact pushed head.

## Invariant mandate

Rows 1–6 govern real-money spend on Antithesis compute; under the loaded
severity law they are `CRITICAL`, and the desk's proportionality steer
(NOTE-028) explicitly exempts spend protection from ceremony reduction. Every
row requires a permanent executing proof AND a demonstrated killing mutant
before it is trusted. No row may ship as an accepted residual.

- **INV-223-DISPATCH-ROUTING** (CRITICAL). The workflow's job selection is
  exactly: `schedule` → production only; `workflow_dispatch` with
  `production=true` → production only; `workflow_dispatch` with
  `production=false` → dry-run only; `pull_request` → dry-run only.
  *Fails as:* a trigger selecting both jobs, neither job, or the wrong one;
  a production job reachable from a `pull_request`; a dispatch default that is
  not `false`; a second production job or duplicated production steps.
  *Succeeds as:* a printed four-row routing census over the exact condition
  strings extracted from the workflow file, plus a proof that exactly one job
  invokes `scripts/daily-amaru.sh`.
- **INV-223-DRY-RUN-BYTE-UNCHANGED** (CRITICAL). The dry-run job's step body is
  byte-identical to its pre-change content.
  *Fails as:* any byte of the dry-run job's steps differing from the frozen
  base content.
  *Succeeds as:* a printed hash comparison against the base-commit extraction.
- **INV-223-ONE-LAUNCH-PER-DAY** (CRITICAL). At most one real launch is reached
  per UTC day across both triggers. A day carrying a launch claim refuses every
  further same-day claim regardless of workflow head, and the refusal is a
  named stage/error in the durable receipt with zero launcher invocations.
  *Fails as:* two real-launch effects for one day in any trigger combination; a
  post-launch day accepting a new claim because the head moved; a refusal that
  reaches the launcher, exits zero, or lands an unnamed/success-like receipt.
  *Succeeds as:* a per-scenario census printing trigger, day, head, launcher
  invocation count (`0` or `1`), and the exact refusal stage and error.
- **INV-223-PRELAUNCH-SUPERSEDE** (CRITICAL). A pre-launch-death claim with an
  unchanged head stays blocked; with a changed head — including a claim with no
  recorded head — the re-attempt is admitted, appends a superseding claim naming
  the previous head, and every prior marker and receipt still exists afterwards.
  *Fails as:* an unchanged head being admitted; a changed head being refused; a
  supersede that deletes, rewrites, or fails to name the superseded claim; a
  prior receipt absent after the re-attempt; a legacy headless claim treated as
  unchanged.
  *Succeeds as:* a census printing recorded head, current head, verdict,
  superseded head, and a before/after marker count that only grows.
- **INV-223-MARKER-CENSUS-FAILS-CLOSED** (CRITICAL). When the marker census
  command fails, the claim is refused.
  *Fails as:* a failing census being read as "no marker present" and the claim
  succeeding; a pipeline whose reader status masks the census status.
  *Succeeds as:* a forced-census-failure case refusing the claim with a named
  error, proved against a positive control where the same census succeeds.
- **INV-223-HEAD-CROSSES-PROCESS** (CRITICAL). With no head injected into the
  controller environment, the derived head is validated, is the exact value
  every claim operation observes in its own child process, and an unresolvable
  head fails closed at a named stage without claiming the day.
  *Fails as:* a transport child observing an absent, empty, or different head;
  an unresolvable head being treated as "changed" and admitting a re-attempt.
  *Succeeds as:* an effect-log census naming the head each claim child observed,
  plus a refused unresolvable-head case with zero markers written.
- **INV-223-PROOFS-NONVACUOUS** (CRITICAL). Every protection above has a mutant
  that is proved to have applied and is then rejected by the proof; the
  deterministic fixture requires the same claim-operation set the production
  transport implements.
  *Fails as:* a mutation that silently does not apply; a proof green against its
  own mutant; a fixture accepting a claim operation production does not
  implement, or vice versa.
  *Succeeds as:* a printed `mutants_rejected=<n>` census with `n` covering every
  row, plus a mechanical fixture/production operation-set reconciliation.
- **INV-223-SCOPE-AND-EFFECT-FENCE** (ADVISORY). The candidate touches only the
  declared paths and reaches no real launch, dispatch, external repository
  mutation, or credential material.
  *Fails as:* a changed path outside the fence, or any real-launch, clone,
  PR-create, merge, or workflow-run effect in the new cases.
  *Succeeds as:* a mechanical path census and a zero-effect census.

## Rejection behavior

A refused claim exits non-zero, publishes an honest `outcome=FAILED` receipt
naming its stage and error, and reaches no launcher and no mutation. An invalid
day, an invalid head, a missing first-boundary command, and a failed transport
child keep their existing stages and exit semantics. Superseding never removes
a marker: issue #210 is append-only.

## Non-goals

No real Antithesis launch or rerun from any test; no edit to
`lambdasistemi/amaru-bootstrap` or compose image refs; no receipt-schema change
beyond the supersede and launch-claim additions; no weakening of #219
evaluability or #221 propagation; no credential change; no issue #210 marker
removal; no work on t75, #212, #208, #207, or #206; no merge and no dispatch by
this ticket — the epic owner fires `production=true` after merge.
