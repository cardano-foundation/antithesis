# Issue 210 — Daily Amaru walking skeleton

## Priority story

As the Amaru fault-injection operator, I need one thin daily controller on
`cardano-node-antithesis` `main` that observes bare `pragma-org/amaru` main,
performs an observable exact-SHA no-op when it was already tested, and drives
one fail-closed bump/publish/repin/check/launch path when it changed.

This is deliberately provisional vertical value. The first changed execution
is lane-supervised under the desk-approved temporary trunk gate. It does not
claim the later hardening assigned to amaru-bootstrap#75 or cna#206–#208.

## User stories

### US1 — One explicit daily decision

Once per UTC day the controller resolves exactly
`https://github.com/pragma-org/amaru.git` `refs/heads/main` to one full SHA and
compares it with the last successfully tested SHA in its durable receipt
record.

- Equality emits one `UNCHANGED` receipt and reaches no mutation or launch.
- Inequality enters the changed path with the observed SHA frozen once.
- Zero, multiple, malformed, wrong-origin, or wrong-ref observations are red.
- A duplicate or second invocation for the same UTC day cannot submit a run.
- A launch already attempted for the same observed SHA cannot be retried
  automatically.

### US2 — Changed source reaches one guarded candidate

The changed path reuses the Milestone 1 operations:

1. propose the exact observed SHA as the stock Amaru input in
   `lambdasistemi/amaru-bootstrap` without changing fork/ref/patch semantics;
2. require the exact candidate's named hosted CI, then its SHA-tagged producer
   image and registry digest;
3. repin all `cardano_amaru` producer references atomically to that exact
   tag+digest;
4. require all named hosted checks on the exact consumer candidate head and
   mechanically record the positive non-zero #202 census before integration;
5. wait for lane-supervised guarded integration; the controller does not
   self-merge a generated repin PR while the platform gate/identity is absent;
6. from the exact merged consumer `main`, invoke the existing
   `cardano-node.yaml` `cardano_amaru` path once with duration `1` hour and
   faults enabled.

The production path requires an explicitly supplied cross-repository identity.
An absent identity is a red before any branch, PR, image, integration, launch,
or success receipt operation. This ticket does not create or configure that
credential.

### US3 — Crude, honest receipt

The controller creates or updates one crude durable day receipt on cna#210.
It records the UTC day, observed upstream SHA, bootstrap candidate/integrated
SHA, image tag and digest, consumer candidate/integrated SHA, exact-head check
evidence, #202 positive census, launcher workflow run, MOOG request/test
identity when observable, and outcome.

Partial and failed states stay visible. They are never translated into
`UNCHANGED`, launch success, run success, or a complete findings verdict.
Property completeness and missing-day alarms remain cna#206 work; #198
continues to classify a complete findings census only and is not weakened.

## Functional requirements

- FR-001: One workflow schedule fires at most once per UTC day. Manual dispatch
  is dry-run/fake-launch only.
- FR-002: Scheduled, manual dry-run, and test scenarios execute the same state
  machine through an injected transport.
- FR-003: Source resolution accepts only one 40-hex SHA for bare
  `pragma-org/amaru` `refs/heads/main`.
- FR-004: The day claim is durable and precedes every changed-path side effect.
- FR-005: Same-day duplicates, second submissions, same-SHA retries, and every
  failed earlier stage make the launch stage unreachable.
- FR-006: A cross-repository mutation identity is a required production input;
  missing or empty input fails before mutation.
- FR-007: The bootstrap proposal changes only the exact stock Amaru SHA and
  preserves bare-upstream semantics. Named bootstrap checks bind to the exact
  candidate head before image acceptance.
- FR-008: Image acceptance requires one full bootstrap SHA tag and one resolved
  lowercase `sha256` digest.
- FR-009: Consumer repinning changes every discovered producer reference to
  one identical `repository:tag@sha256:digest` value.
- FR-010: Before consumer integration, named hosted checks must all be success
  on the exact candidate head. The `publish-images` job must retain the #202
  command's positive, non-zero census output.
- FR-011: The temporary trunk gate requires epic-owner independent acceptance
  and guarded merge. Production code must not self-merge a generated consumer
  repin PR.
- FR-012: The only real launch shape is the existing workflow on exact merged
  `main`, `test=cardano_amaru`, `duration=1`, `no-faults=false`; it is called at
  most once and has no automatic retry.
- FR-013: No test, pull-request, failure, duplicate, manual, or pre-merge path
  can invoke a real launcher.
- FR-014: The merged #196 live-boundary command and #202 checker remain present
  and semantically unchanged.
- FR-015: Every provisional production mechanism carries exactly one tracked
  TODO naming `amaru-bootstrap#75`, `cardano-node-antithesis#208`,
  `cardano-node-antithesis#207`, or `cardano-node-antithesis#206`.

## Named consumer checks

For the temporary exact-head gate the controller records successful checks for
the candidate SHA, including the repository-standard current set:

- `publish-images` and `Compose smoke test` from
  `Build and push component images for cardano-node testnet`;
- `Build`, `Run unit Tests`, and `Check code quality` from
  `tracer-sidecar CI`;
- `build-docs` and `preview`.

The list is explicit rather than inferred from the currently absent required
status-check rules. Missing, duplicate/ambiguous, wrong-head, skipped,
cancelled, neutral, pending, or failing results are red.

## Provisional mechanisms and owners

- `TODO(amaru-bootstrap#75)`: replace the crude supervised stock-pin and image
  publication handoff with the validated producer contract.
- `TODO(cardano-node-antithesis#208)`: replace the minimal #202 plus retained
  #196 checks with complete exact-revision interface preflight.
- `TODO(cardano-node-antithesis#207)`: replace supervised generated-PR
  integration, provisional identity input, launch, and correlation with the
  guarded unattended pipeline after platform protection exists.
- `TODO(cardano-node-antithesis#206)`: replace the crude issue receipt with
  complete per-property accounting and an independent missing-day alarm.

## Observable acceptance

- Exact changed and unchanged fixtures both execute and emit distinct outcomes.
- Zero and ambiguous observations fail.
- Missing identity, wrong/missing exact-head checks, #202 zero/failure, failed
  earlier stages, duplicates, same-day second runs, and same-SHA retries all
  record zero real submissions.
- A fake success path records exactly one one-hour faults-enabled submission.
- The real launcher is structurally unreachable in every local/PR/manual test.
- The committed TODO census names all four replacement children and no
  anonymous production deferral.
- The feature PR passes the desk-approved exact-head gate and is handed to the
  epic owner; no real MOOG submission occurs before parent release on the exact
  merged revision.

## Scope boundaries

Do not alter MOOG installation/submission semantics, #196, #202, #198,
tracer-sidecar properties, Compose service behavior other than the generated
exact repin, upstream Amaru behavior, operator credentials, repository rules,
or the hardening children. There is no automatic real-run retry and no real
implementation-time launch.
