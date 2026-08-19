# Issue 221 — Daily Amaru derived-day propagation

Artifact ceiling: 7,000 bytes and 160 lines.

## Priority story

As the Daily Amaru operator, I let the scheduled controller derive its own UTC
day and observe that every transport child receives exactly that validated day,
while the durable issue #210 day claim and stage receipts survive a downstream
transport failure.

## Root cause and incident

Scheduled run `32215848871` on head `7ac049e748ff83ab12dee2864343510d6fb9541e`
recorded stage `bootstrap-proposal`, `outcome=FAILED`, `error=proposal-failed`.
The underlying child error was
`scripts/daily-amaru-github.sh:185: DAILY_AMARU_DAY is required`.

`scripts/daily-amaru.sh` assigns `day=${DAILY_AMARU_DAY:-$(date -u +%F)}` as a
plain shell variable. `transport_call` forks a child process, which cannot see a
non-exported variable. The transport operations `propose-bootstrap` and
`prepare-consumer-repin` bind `${DAILY_AMARU_DAY:?DAILY_AMARU_DAY is required}`
and therefore abort whenever the workflow does not supply the day itself.

The scheduled workflow deliberately supplies no day: #213 made the controller
the sole deriver so no external `date` stands before the first receipt
boundary. Every existing controller case in `tests/test-daily-amaru.sh` injects
`DAILY_AMARU_DAY`, so the complete suite was green while the only production
shape — an omitted day — was never exercised.

## Functional requirements

- **FR-221-01 — Exported derived day.** After `scripts/daily-amaru.sh` derives
  and validates its UTC day, it exports exactly that value as
  `DAILY_AMARU_DAY` before the first transport child is forked.
- **FR-221-02 — Workflow-shaped proof.** A permanent regression omits
  `DAILY_AMARU_DAY` from the controller environment, supplies a deterministic
  fake `date`, and proves the derived day is the exact value observed by both
  the `propose-bootstrap` and `prepare-consumer-repin` transport paths.
- **FR-221-03 — Killing mutant.** Removing only the propagation, and nothing
  else, makes that regression fail with the production fingerprint
  `DAILY_AMARU_DAY: DAILY_AMARU_DAY is required` and the production receipt
  triple `stage=bootstrap-proposal`, `outcome=FAILED`, `error=proposal-failed`.
  The mutation proves it applied before its red is believed; the repaired path
  rejects it.
- **FR-221-04 — Receipts survive failure.** The same omitted-day regression
  proves that, through a forced downstream transport failure, the issue #210
  day claim carries the derived day and the ordered stage receipts are still
  published. No receipt behavior, marker vocabulary, or ordering is weakened,
  bypassed, or replaced.
- **FR-221-05 — Non-drifting seam.** The deterministic transport fixture
  requires the day in exactly the operations the production transport requires
  it in, reconciled mechanically from the production transport source, so the
  fixture cannot silently stop being able to observe the defect.
- **FR-221-06 — Preserved guards.** Existing no-effect, no-real-launch,
  duplicate-day, attempted-SHA, credential, receipt, and failure guards remain
  green and unweakened.
- **FR-221-07 — Fenced effect surface.** The new proof reaches no real
  launcher, no GitHub dispatch, no external repository mutation, and no
  credential material.
- **FR-221-08 — Green gates.** The focused controller suite and complete local
  CI are freshly green, the frozen slice gate and ticket gate are freshly
  green, the finalization audit passes, and all six required GitHub contexts
  are green on the exact pushed head.

## Invariant mandate

All four rows are operational process-boundary, evidence, receipt-continuity,
and effect-fence truths. They do not constrain chain state, money, or a
signature, so under the loaded severity law they are classified `ADVISORY`.

**Ticket-specific acceptance floor.** Advisory severity does not lower this
ticket's bar. Every one of the four rows requires a permanent executing proof
and a demonstrated killing mutant before acceptance. No row may become an
accepted residual on the ground that its severity is advisory.

- **INV-221-DERIVED-DAY-CROSSES-PROCESS** (ADVISORY). With `DAILY_AMARU_DAY`
  absent from the controller environment, the validated controller-derived day
  is the exact value observed inside every named transport child.
  *Fails as:* a transport child observes an absent, empty, or different day.
  *Succeeds as:* both named operations report the exact derived day in the
  effect log, and the derived day equals the deterministic fake date.
- **INV-221-PROPAGATION-PROOF-NONVACUOUS** (ADVISORY). The fake date is
  distinguishable from the real system UTC day and from every day literal
  already used by the suite; the remove-propagation mutant is proved applied
  and recreates the exact production failure; the fixture's day requirement is
  reconciled against the production transport's.
  *Fails as:* the proof passes against the mutant, the mutation silently does
  not apply, the observed day could have come from an injected constant, or the
  fixture requires the day in a different operation set than production.
  *Succeeds as:* a printed census naming the derived day, its source, the
  matched operation set, and the rejected mutant.
- **INV-221-RECEIPTS-SURVIVE-FAILURE** (ADVISORY). Under an omitted day and a
  forced downstream transport failure, the #210 day claim carries the derived
  day, the stage receipts are published in their existing order, and the final
  receipt is an honest failure receipt.
  *Fails as:* a missing or mis-dated day claim, a dropped or reordered stage
  receipt, or a success-like outcome on a failed run.
  *Succeeds as:* the receipt oracle accepting the durable receipt plus a
  printed ordered stage-receipt census.
- **INV-221-SCOPE-AND-EFFECT-FENCE** (ADVISORY). The candidate touches only the
  declared paths and reaches no real launch, dispatch, external repository
  mutation, or credential material.
  *Fails as:* any changed path outside the fence, or any real-launch, clone,
  PR-create, merge, or workflow-run effect in the new cases.
  *Succeeds as:* a mechanical path census and a zero-effect census.

## Rejection behavior

The controller must still reject an invalid supplied day before exporting
anything, must still classify a missing first-boundary command as
`runner-preflight` without claiming the day, and must still fail the run when a
transport child fails. Exporting the day changes no stage, marker, or exit
semantics.

## Non-goals

No workflow edit, receipt-schema change, controller or transport redesign, real
launch, dispatch, MOOG or Antithesis submission, same-day rerun, issue #210
marker removal, or work on `lambdasistemi/amaru-bootstrap`, t75, cadence, #212,
#208, #207, or #206.
