# Issue 219 — Daily Amaru workflow validation

Artifact ceiling: 7,000 bytes and 160 lines.

## Priority story

As the Daily Amaru operator, I need GitHub to allocate and run the pull-request
dry-run job and I need required CI to reject invalid Actions expression
contexts across the repository, so a workflow cannot merge while creating zero
jobs.

## Root cause and incident

At accepted head `6735541bb61076de81bab3e1676f8f2eb4017229` and merged
head `5641da000f3b5fecfae9eaa2df42e67cd293f3b0`, the Daily Amaru
workflow bound `${{ runner.temp }}` in scheduled-job `env`. GitHub evaluates
that mapping before allocating a runner, where `runner` is unavailable, and
rejected the whole workflow with zero jobs. Runs `31791847532` and
`31793226810` record the failure.

The six required contexts on PR #218 were green because none evaluated all
repository workflows with GitHub Actions expression-context rules.

## Functional requirements

- **FR-219-01 — Runner-scoped initialization.** Daily Amaru state and receipt
  paths resolve to runner-local temporary storage only in a context where a
  runner has already been allocated. The resolved paths remain
  `$RUNNER_TEMP/daily-amaru` and `$RUNNER_TEMP/daily-amaru/receipt`.
- **FR-219-02 — Repository-wide census.** One permanent local command
  enumerates every tracked `.yaml` and `.yml` workflow under
  `.github/workflows`, reports a positive file count, and exits non-zero when
  that census is empty.
- **FR-219-03 — Expression validation.** The command validates the census with
  a pinned Actions-aware validator and exits non-zero for invalid expression
  contexts. Any baseline suppression is path-specific, documented, and cannot
  suppress the `runner`-at-job-env class.
- **FR-219-04 — Required-CI reachability.** The validator command executes in
  the repository-required `Check code quality` context. A validator failure
  therefore makes one of the six merge-required contexts red.
- **FR-219-05 — Both-way proof.** Permanent controls reject the exact merged
  `${{ runner.temp }}` scheduled-job-env defect and an empty workflow census,
  then emit meaningful positive evidence for the repaired complete census.
- **FR-219-06 — Hosted dry-run proof.** On the exact accepted PR head, the
  `Daily Amaru contract dry run` is a real GitHub-hosted job, the Daily Amaru
  workflow job census is non-zero, and all six required contexts are green.
- **FR-219-07 — Controller preservation.** Existing Daily Amaru controller
  tests remain green, including absent named-credential and distinct-present
  credential controls. Once-per-day, identity, receipt, and launch semantics
  do not change.
- **FR-219-08 — Operator explanation.** User-facing documentation explains
  that `runner` values exist only after allocation and identifies the local
  repository-wide validation command.
- **FR-219-09 — Local gate.** The repository exposes a complete local CI
  command covering workflow validation, focused Daily Amaru proof, shell
  analysis, and formatting checks that are available without Docker or live
  services.

## Invariant mandate

- **INV-219-01 — No pre-allocation runner lookup.** No job-level mapping
  references `runner`; runner-local Daily Amaru paths retain their exact values
  after allocation.
- **INV-219-02 — Census cannot pass vacuously.** Every tracked repository
  workflow is validated exactly once, the passing output names a positive
  count, and zero workflows is red.
- **INV-219-03 — The validator can catch the incident class.** Restoring the
  exact two merged job-env bindings makes the permanent validator exit
  non-zero with a `runner` context diagnostic.
- **INV-219-04 — The guard is merge-reachable.** The exact validator command is
  called by `Check code quality`; an orphaned command or test is red.
- **INV-219-05 — Fail-closed identity survives.** Missing App configuration
  still yields the exact named missing-credential receipt and zero business
  effects; three distinct present sentinels still exercise the positive
  production control without leaking.
- **INV-219-06 — Hosted evidence binds the candidate.** The Daily Amaru
  pull-request job and all six required contexts report the exact accepted PR
  SHA, not a prior head or rerun substitute.
- **INV-219-07 — No live effects.** Local and hosted dry-run proof performs no
  App or secret provisioning, workflow dispatch, MOOG/Antithesis submission,
  production schedule execution, spend, or merge.

## Rejection behavior

CI rejects an unreadable workflow, invalid Actions expression context,
incomplete workflow census, empty census, a validator no longer called from a
required context, or a restoration of either broken `runner.temp` job-env
binding. A zero-job GitHub evaluation is a failure even when every other
required context is green.

## Scope

Owned implementation is limited to `.github/workflows/daily-amaru.yaml`, the
required `Check code quality` workflow path, the repository-local workflow
validation command and focused tests/fixtures, strictly necessary Nix/Just
tool plumbing, and Daily Amaru documentation. Narrow path-specific validator
baselines may describe pre-existing diagnostics but may not alter unrelated
workflow behavior.

App/secret/variable provisioning, credential values, Daily Amaru policy,
MOOG/Antithesis submission, manual workflow dispatch, production schedule
execution, compose/image changes, and implementation of #75/#212/#208/#207/
#206 are excluded.
