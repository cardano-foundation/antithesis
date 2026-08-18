# Plan — Issue 219 Daily Amaru workflow validation

Artifact ceiling: 7,000 bytes and 170 lines.

## Technical context

The frozen base is `5641da000f3b5fecfae9eaa2df42e67cd293f3b0`; refreshed
`origin/main` still resolves to that commit. The issue worktree is clean and
the branch is `fix/219-daily-amaru-workflow-validation`.

GitHub rejected runs `31791847532` and `31793226810` before job creation with
`Unrecognized named-value: 'runner'` at Daily Amaru workflow lines 44–45.
Actionlint 1.7.10 independently reports the same two context errors. A complete
base census also reports one unrelated shellcheck diagnostic in
`cardano-node.yaml` and two pre-existing typed-event diagnostics in
`publish-images.yaml`; they must receive only narrow path-specific baselines,
not unrelated behavior changes or a global expression suppression.

The nominal baseline command `nix develop --quiet -c just ci` exits 1 because
the base Justfile has no `ci` recipe. That is recorded as a pre-existing local
gate gap and is part of FR-219-09, not evidence that the frozen base is green.

## Architecture decisions

- `.github/workflows/daily-amaru.yaml` retains runner-local state and receipt
  values but initializes them only after runner allocation. The controller,
  transport, schedule, permissions, identity, receipt, and launch contracts do
  not change.
- A repository-local command owns workflow discovery, positive census output,
  the empty-census guard, and invocation of the pinned Actions validator. It
  validates both `.yaml` and `.yml` files and does not silently omit tracked
  workflows.
- Root Nix/Just plumbing makes that command identical locally and in CI. The
  required `Check code quality` job invokes it before its existing component
  quality work, so the required context cannot be green when validation is
  red.
- Focused proof owns the exact merged mutant, empty-census mutant, complete
  passing census, and required-job reachability. Existing
  `tests/test-daily-amaru.sh` remains the controller and credential oracle.
- `docs/daily-amaru.md` explains the allocation boundary and local command.

No module, data, or function interface changes are planned, so the parent
brief's authorized planning record is exactly `spec.md`, `plan.md`, and
`tasks.md`; no empty model artifacts are introduced.

## Proof strategy

The ticket owner freezes one executable gate outside Git before implementation.
Its first check runs a pinned Actions validator over the complete base census,
with only the named pre-existing path baselines, and must fail on the two exact
`runner` job-env diagnostics. The gate then requires:

- the permanent workflow-validation controls, including exact mutant and empty
  census rejection;
- the permanent local CI command and required-job reachability;
- the complete existing Daily Amaru controller suite;
- shell analysis, formatting checks, and `git diff --check`;
- meaningful workflow and credential-control evidence in passing output.

After GREEN, the commit owner independently restores the broken form or exact
fixture, records RED, restores the candidate, and records GREEN. The fresh
auditor repeats the invariant matrix in a clean detached worktree.

## Slice S219-01 — Evaluation repair and permanent workflow guard

Topology is `OWNER`: the slice changes workflow evaluation and a merge-required
CI boundary, and hosted GitHub evaluation remains outside a complete local
mechanical signal.

- Ticket owner: Codex `gpt-5.6-sol`, effort `xhigh`, pane `%6710`.
- Commit owner: fresh Claude Code `claude-opus-5[1m]`, effort `high`.
- Draft tool: `NONE`; qwen, grok, and agy are not authorized.
- Fresh auditor: Codex `gpt-5.6-sol`, effort `xhigh`, in a clean detached
  worktree at each submitted candidate.
- Audited submissions: maximum two, with at most one findings-driven repair.
- Commit owner and auditor have no push, publication, live dispatch, secret,
  App, spend, merge, or history-rewrite authority.

Predetermined final commit:

`fix(ci): validate GitHub Actions expression contexts`

The body explains runner-allocation timing, complete workflow census, required
CI reachability, and both-way controls. The trailer is:

`Tasks: T2191, T2192, T2193, T2194, T2195, T2196`

## Publication and hosted acceptance

Commit and push this planning record and open a draft PR before behavior work.
The planning head is expected to preserve the meaningful zero-job red; it must
not be rerun to hide that evidence. Implementation is pushed only after the
frozen gate, fresh audit, final tree proof, and complete local gate are green.

Normal pull-request evaluation—not `workflow_dispatch`—must then prove on the
exact accepted head:

- Daily Amaru workflow job census greater than zero;
- `Daily Amaru contract dry run` completed successfully;
- all six ruleset contexts (`Build`, `Run unit Tests`, `Check code quality`,
  `Compose smoke test`, `publish-images`, `build-docs`) green.

No scheduled or manual production run is part of acceptance. Dedicated App
inputs remain deliberately absent, so production continues to fail closed at
the named credential boundary with zero spend.
