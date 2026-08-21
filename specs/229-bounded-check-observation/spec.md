# Bounded-wait bootstrap check observation

Issue: cardano-foundation/cardano-node-antithesis#229 · parent epic #205
Frozen main base: `9094d548fb338950bc42f231babf72d745dd969f`

Artifact ceiling: 8,000 bytes and 180 lines.

## Context

Daily fire run 32470212421 pushed the coherent bootstrap candidate from PR
#87 and read its checks about three seconds later. GitHub had not reported the
required checks yet, so the single observation emitted
`bootstrap check is not uniquely successful ...: Build`. Later check activity
contradicted that verdict. This is the epic ledger's observation-race class:
an observer must distinguish pending from absent and allow the system time to
report.

## Requirements

- **R229-1 — explicit observation states.** `require-bootstrap-checks`
  distinguishes `pending`, `successful`, `failed`, and `never-reported` for
  every existing required bootstrap check on the exact candidate head.
- **R229-2 — behavior-derived bound.** A pending or not-yet-reported
  observation is retried only inside a finite window derived from observed or
  declared check duration evidence. A bare fixed wait unrelated to that
  evidence is not acceptable, and every wait has a named terminal outcome.
- **R229-3 — transport is not a verdict.** API/transport errors inside the
  observation window are retried and remain distinguishable from check
  failure, success, and absence. Exhaustion fails closed and names transport
  exhaustion.
- **R229-4 — exact success.** The operation proceeds only when each unchanged
  required check is present exactly once for the candidate, completed, and
  successful.
- **R229-5 — named fail-closed result.** A concluded non-successful check fails
  closed naming `failed` and the check. A check still absent when the derived
  window closes fails closed naming `never-reported` and the check. Ambiguous
  or duplicate terminal observations never proceed.
- **R229-6 — contracts stay fixed.** Required-check membership, candidate
  construction, receipt keys, cap/supersede semantics, credentials, and the
  Amaru bootstrap repository are unchanged.

## Rejection behavior

- Never treat an empty or partial census as an immediate failed check.
- Never treat a transport error as success, failure, or absence.
- Never wait without a behavior-derived deadline or hide the terminal state
  behind the old conflated `not uniquely successful` message.
- Never exercise a real launch, real proposal, credential, or external write
  from the proof harness.

## Invariants

All rows are `BLOCKING`; this gate controls unattended integration.

| ID | Observable truth | Demonstrated failure | Observable success |
|---|---|---|---|
| INV-229-1 | A not-yet-reported required check is pending, not failed or absent | the first census omits a required check | a later injected successful census proceeds and records at least two observations |
| INV-229-2 | The observation terminates within a window derived from supplied behavior/duration evidence | a never-reporting transport remains empty | the operation exits non-zero after the derived window, names `never-reported` plus the missing check, and records the bounded poll count |
| INV-229-3 | A completed failed check is terminal and named | a later census concludes one required check unsuccessfully | the operation exits non-zero naming `failed` and that check without waiting past the terminal observation |
| INV-229-4 | Transient transport errors are retryable observations, not verdicts | the injected transport fails before returning an in-progress or successful census | a later valid census is consumed; persistent errors terminate as named transport exhaustion |
| INV-229-5 | Success remains exact-head, exactly-once, all-required success | wrong-head, duplicate, partial, or non-success rows are supplied | only one completed-success row per unchanged required check permits progress |
| INV-229-6 | The fire-4 mutant stays killable | a verified-applied mutant restores the immediate single-shot read | it reproduces the three-second/not-yet-reported failure shape, while the shipped path passes the same sequence |
| INV-229-7 | Proof boundaries are hermetic and non-spending | a proof inherits host transport/time tools or reaches a real launch/write | injected census, clock, and sleep boundaries account for every observation and zero real effects |

## Observable success

- A workflow-shaped injected checks transport proves pending→success,
  pending→failure, never-reported-at-deadline, transient-error→success, and
  persistent-error exhaustion.
- The not-yet-reported negative control explicitly fails if the first missing
  census is classified as failure or terminal absence.
- A verified-applied immediate-read mutant reproduces fire-4's exact class.
- `just test-daily-amaru` is green with no network, credentials, publication,
  or Antithesis launch.
- Local cold Nix realization is omitted by authority; all required hosted
  contexts must be green on the exact pushed head.

## Scope

Owned production surface is `scripts/daily-amaru-github.sh` at
`require-bootstrap-checks`; `scripts/daily-amaru.sh` may change only if needed
to preserve a distinct named state in the existing receipt. Focused tests,
fixtures, and `specs/229-*` are owned. Required-check membership, candidate
build/proposal behavior, receipt schema, cap/supersede behavior, credentials,
real launches, and every amaru-bootstrap file are forbidden without a Q.
