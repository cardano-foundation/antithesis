# Issue 213 — Daily Amaru scheduled preflight

Artifact ceiling: 8,000 bytes and 180 lines.

## Priority story

As the Amaru fault-injection desk, I need the scheduled Daily Amaru controller
to enter its fail-closed state machine with an explicit dependency and
short-lived identity contract, so every UTC day produces either a legitimate
decision or a loud durable failure receipt.

## Root causes

- The scheduled job relied on the stock Ubuntu runner for `rg`; the transport
  rejected the runner before its first operation, so neither the controller
  nor its receipt state was reachable.
- The scheduled job injected an absent repository secret as the single
  cross-repository identity. No runtime-minted, repository-scoped App token
  existed for `lambdasistemi/amaru-bootstrap`.
- One identity value was conceptually shared across the bootstrap repository
  boundary and same-repository consumer work, despite those boundaries having
  different authorities.

## Functional requirements

- **FR-213-01 — Explicit runner contract.** The scheduled workflow provisions
  every non-shell command required by the production controller and transport.
  Missing commands are controller precondition failures, not setup exceptions.
- **FR-213-02 — Exact incident reproduction.** Scheduled-context controls for
  2026-08-02 and 2026-08-03 reproduce
  `daily-amaru-github: missing command: rg` from base `311dfc1`, then prove the
  repaired controller exits non-zero with a durable receipt for that same
  missing-command condition.
- **FR-213-03 — Dedicated App interface.** Production references repository
  variable `DAILY_AMARU_APP_ID` and Actions secret
  `DAILY_AMARU_APP_PRIVATE_KEY`, and mints a runtime token restricted to
  `lambdasistemi/amaru-bootstrap` with only `actions:read`, `checks:read`,
  `contents:write`, `pull_requests:write`, and `metadata:read`.
- **FR-213-04 — Identity separation.** The dedicated App token is usable only
  for the bootstrap boundary. Same-repository comments, consumer preparation,
  and consumer observation use the workflow's short-lived repository token.
- **FR-213-05 — Missing identity is RED.** Absent App inputs or an unsuccessful
  token-mint step leave the bootstrap identity empty and still invoke the
  controller. The controller exits non-zero at the identity stage and emits a
  specific failure receipt before any bootstrap/consumer mutation or launch.
- **FR-213-06 — Receipt durability.** Every broken precondition records UTC
  day, precise stage, `outcome=FAILED`, and a specific error in a local receipt
  that the workflow publishes durably even when the GitHub transport cannot
  publish its ordinary issue receipt.
- **FR-213-07 — No secret persistence.** The App private key and minted token
  are never printed, placed in a receipt/state artifact, written through
  `$GITHUB_ENV`, committed, or reused outside the scheduled controller step.
- **FR-213-08 — Side-effect exclusion.** Missing-tool and missing-identity
  controls reach zero bootstrap proposal, image, consumer-repin,
  integration, fake-launch, and real-launch operations.
- **FR-213-09 — Fixed-path census.** The repaired changed path performs exactly
  one fake launch and zero real launches in verification. Existing unchanged,
  duplicate-day, attempted-SHA, exact-head, fail-closed stage, and positive
  producer-census controls remain green.
- **FR-213-10 — CI reachability.** Pull-request CI executes the scheduled
  context contract and its negative controls on the exact candidate head.
  Presence of workflow text without an executing proof is insufficient.
- **FR-213-11 — Resource and live boundaries.** Verification records `/` and
  `/run` byte deltas, stops below 30 GiB free on `/`, stops a command consuming
  more than 8 GiB, uses `/code` for scratch, and performs no workflow dispatch
  or real launch.

## Invariant mandate

- **INV-213-01 — Preflight precedes business effects.** A dependency failure is
  observed before attempt claim, bootstrap/image/consumer mutation,
  integration, or launch; its failure receipt is still reachable.
- **INV-213-02 — A silent failure cannot pass.** A missing receipt, missing
  required field, `outcome` other than `FAILED`, vague error, or zero exit from
  a broken precondition makes the gate red.
- **INV-213-03 — App scope is singular.** The minted bootstrap token names one
  owner and one repository and cannot authorize the cna consumer boundary.
- **INV-213-04 — Identity failure remains inside the state machine.** Missing
  or unusable App configuration becomes `stage=identity` with a specific
  error, not a skipped step, setup-only exception, or inferred success.
- **INV-213-05 — Credentials are ephemeral.** Only a step output-to-step-env
  binding carries the minted token; no durable output can contain it.
- **INV-213-06 — Broken paths cannot launch.** Both broken-precondition
  controls prove zero fake and real launch reachability and zero business
  mutation reachability.
- **INV-213-07 — The fixed path is non-vacuous.** Passing evidence reports the
  exact two seeded days, required receipt fields, dependency census, mutation
  census, one fake launch, and zero real launches.
- **INV-213-08 — Existing safety contracts survive.** Bare origin/ref,
  exact-SHA/day-cap semantics, exact-head checks, producer census, failure
  ordering, fault duration, and protected launch shape are unchanged.
- **INV-213-09 — Production wiring executes the proof.** The pull-request job
  invokes the focused suite and the scheduled job invokes the same controller
  contract; orphaned assertions are red.

## Rejection behavior

The controller must reject missing commands, missing identity, malformed
observations, duplicate/attempted work, invalid exact-head evidence, zero
producer census, failed integration, and launch failure with a non-zero exit
and stage-specific receipt. A precondition failure may write its failure
receipt and concurrency bookkeeping; it may not reach bootstrap, image,
consumer, integration, or launch effects.

## Scope

Owned implementation is limited to the Daily Amaru workflow, controller,
GitHub transport, focused tests/fixtures, and Daily Amaru documentation.
`testnets/**`, compose/image pins, MOOG/Antithesis workflows, cna#212,
amaru-bootstrap#75, and cna#206–#208 behavior are excluded.

The dedicated App's creation, installation, permission approval, secret
placement, and live proof remain an operator gate. This ticket implements the
interface and loud missing-input behavior only; it does not satisfy or bypass
that external gate.
