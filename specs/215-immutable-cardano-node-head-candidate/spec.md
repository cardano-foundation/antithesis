# Spec: immutable Cardano Node master HEAD Antithesis candidate

Issue: #215. Parent epic: #214. Slug: `215-immutable-cardano-node-head-candidate`.

## Observable outcome

An operator dispatches one GitHub Actions workflow on the default branch and
observes a durable receipt describing exactly one Cardano Node `master` HEAD
candidate whose upstream SHA, published image digest, live binary revision, and
every rendered producer/relay image agree. No Antithesis request is made.

## P1 user story

As a Cardano Node fault-injection operator I run the manual candidate workflow
and read one receipt that names the resolved upstream SHA, the immutable
`tag@sha256:digest` candidate, the observed binary revision, and the uniform
rendered topology — or an honest failure naming the exact stage that stopped.

## Requirements

| ID | Requirement |
|---|---|
| R-01 | Resolve `https://github.com/IntersectMBO/cardano-node.git` `refs/heads/master` exactly once per candidate and freeze the single observed full 40-hex SHA. |
| R-02 | Build the exact upstream Nix `dockerImage/node` output for that SHA and publish it under a full-SHA tag in the repository's own GHCR namespace. |
| R-03 | Record the published OCI digest and express candidate identity only as `<repository>:<40-hex-sha>@sha256:<64-hex>`. |
| R-04 | Prove the revision by executing the published image and reading the containerized `cardano-node` binary's own revision output. |
| R-05 | Render the `cardano_node_master` Compose model so that every producer and relay resolves to that one candidate reference, and verify uniformity on the resolved model rather than on file text. |
| R-06 | Validate the rendered model through Compose itself before the submission boundary. |
| R-07 | Expose one manually dispatchable GitHub Actions entrypoint that runs the production candidate path with a fake submission transport and publishes a durable candidate receipt. |
| R-08 | Emit a `CandidateReceiptV1` record at every stage, including honest failure records. |
| R-09 | Run the candidate-path tests in local and hosted CI, and document the manual recovery entrypoint. |
| R-10 | Keep the existing mixed-version `cardano_node_master` profile on disk and separately invokable. |

## Invariants

Each invariant states its observable failure and success meaning. Parent
invariants `E214-01..05` map as noted; `E214-06..09` belong to #216.

| ID | Invariant | Fails when | Holds when |
|---|---|---|---|
| I215-01 | Exactly one `master` observation yields one full SHA (E214-01) | zero, multiple, malformed, wrong-origin, or wrong-ref observation | stage `resolve-upstream` records exactly one 40-hex SHA and the receipt carries it |
| I215-02 | Candidate identity is full-SHA tag plus OCI digest (E214-02) | tag component differs from the resolved SHA, digest absent, or reference not `repo:40hex@sha256:64hex` | stage `publish-candidate` records a reference in exactly that form whose tag equals the resolved SHA |
| I215-03 | Live binary revision equals the resolved SHA (E214-03) | container cannot run, revision absent, unparsable, or different | stage `prove-revision` records the observed revision and it equals the resolved SHA |
| I215-04 | Every rendered producer/relay uses one identical immutable candidate (E214-04) | any expected node service missing, any node image unequal to the candidate, any stale release reference surviving, or a zero-row census | stage `verify-topology` records the complete expected service census with one distinct image equal to the candidate |
| I215-05 | The rendered model is Compose-valid | Compose validation of the rendered model fails or produces no services | stage `validate-compose` succeeds on the rendered model |
| I215-06 | No failed or ambiguous prerequisite reaches the submission boundary (E214-05) | the submission operation is invoked after any stage failure | the submission operation is invoked exactly once on the complete path and zero times in every negative control |
| I215-07 | No real Antithesis submission exists in this ticket | any real-submission transport operation is reachable or invoked | every mode available in #215 reaches only the fake submission operation |
| I215-08 | One production code path | preparation or validation logic is duplicated per mode | the same controller runs in every mode and only the injected transport differs |
| I215-09 | Receipts are honest | a failing run emits a success outcome or omits its failing stage | each stage appends a `CandidateReceiptV1` record; a failure records `outcome=FAILED` with the failing stage and an error reason |
| I215-10 | Secrets never leak | any credential value appears in a receipt, log, fixture, brief, or document | credentials are passed only through the process environment of the effecting command |

## Rejection behavior

Every rejection is fail-closed: the controller writes the honest failure
receipt for its stage, exits non-zero, and performs no later stage. Rejected
conditions are those named in the invariant table above, plus an unsupported
mode, a non-executable transport, and a transport operation that exits non-zero.

## Observable success

- `tests/test-daily-cardano-node-head.sh` passes locally and in hosted CI, with
  one named scenario per invariant and per negative control.
- The manual workflow run produces a downloadable receipt containing the four
  agreeing identities and `outcome=PREPARED`.
- `testnets/cardano_node_master/docker-compose.yaml` is unchanged.

## Non-goals

- Scheduling, day claims, real MOOG transport, and terminal run receipts (#216).
- Changing Cardano Node source or upstream release workflows.
- Changing the Daily Amaru controller.
- Committing or merging any generated candidate consumer commit.
