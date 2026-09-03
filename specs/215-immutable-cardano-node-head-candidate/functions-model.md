# Functions model

Only new or changed signatures. Shell interfaces are specified as
argument names, stdout contract, and exit semantics. No bodies, algorithms, or
control flow appear here.

## Controller entrypoint (M-01)

`scripts/daily-cardano-node-head.sh` takes no positional arguments and is
configured only through the environment:

| Variable | Type | Meaning |
|---|---|---|
| `HEAD_CANDIDATE_MODE` | `ControllerMode` (D-06) | default `manual` |
| `HEAD_CANDIDATE_TRANSPORT` | absolute path | default: the sibling real transport; must be executable |
| `HEAD_CANDIDATE_STATE_DIR` | absolute path | working root for rendered artifacts |
| `HEAD_CANDIDATE_RECEIPT` | absolute path | receipt destination, exported to the transport |
| `HEAD_CANDIDATE_IMAGE_REPOSITORY` | string | candidate GHCR repository (D-02 `repository`) |

Exit: `0` only after a `PREPARED` receipt; non-zero on any fail-closed
rejection, with the failing stage's `FAILED` receipt already written.

Stdout on success: exactly one line
`PREPARED <upstream_sha> <candidate_ref> <submission>`.

## Transport operation surface (M-02 and M-03)

Both transports are invoked as `<transport> <operation> [args...]`. Every
operation exits non-zero on failure and writes nothing to stdout in that case.
Unknown operations are rejected.

| Operation | Arguments | Stdout on success |
|---|---|---|
| `resolve-upstream` | `origin ref` | zero or more `UpstreamObservation` lines `origin\|ref\|sha` (D-01) |
| `publish-candidate` | `upstream_sha repository` | one `CandidateRef` rendered form `repository:tag@digest` (D-02) |
| `prove-revision` | `candidate_ref` | one `RevisionProof` `revision` (D-03) |
| `render-topology` | `candidate_ref` | one absolute path to the rendered model |
| `describe-topology` | `rendered_model` | zero or more `TopologyRow` lines `service\|image` (D-04) |
| `validate-compose` | `rendered_model` | nothing; exit status is the whole contract |
| `fake-submit` | `rendered_model candidate_ref upstream_sha` | one submission identifier beginning with `fake://` |
| `receipt` | `field=value ...` | nothing; appends one `CandidateReceiptV1` record (D-05) |

Signature-level constraints:

- No operation takes or returns a credential; identity reaches the effecting
  command only through its inherited environment (I215-10).
- No operation named `real-submit` or any other real-submission operation
  exists in either transport in #215 (I215-07).
- `describe-topology` reports Compose-resolved services only; it may not read
  image values out of unresolved file text (I215-04).
- `prove-revision` observes the running container's own binary; image labels,
  registry metadata, and tag names are inadmissible (I215-03).
- Every operation is pure with respect to `testnets/`: no transport operation
  may write below the repository's tracked tree (R-10).

## Fake transport selection (M-03)

`tests/fixtures/daily-cardano-node-head/fake-transport.sh` reads:

| Variable | Type | Meaning |
|---|---|---|
| `FAKE_SCENARIO` | string | selects the deterministic observation set for one test case |
| `FAKE_LOG` | absolute path | append-only invocation log, one `operation args...` line per call |

The log is the reachability oracle: submission counts and stage ordering are
asserted from it (I215-06).

## Test harness (M-04)

`tests/test-daily-cardano-node-head.sh` takes no arguments, requires no
network, Docker, or Nix, prints one `PASS <scenario>` line per satisfied
scenario, and exits non-zero on the first unsatisfied assertion.

## Mutation harness (M-07, mandate v2)

`tests/mutants/daily-cardano-node-head.sh` takes no positional arguments.

| Variable | Type | Meaning |
|---|---|---|
| `MUTANT_WORKDIR` | absolute path | scratch root for materialized copies; defaults to a fresh temporary directory |

Stdout: one line per mutant, `<mutant-id> caught|survived`, followed by a
final `MUTANTS <caught>/<total>` line. Exit `0` only when every named mutant is
caught.

Signature-level constraints:

- each mutant verifies that its own edit applied before the suite runs, and an
  unapplied edit is a harness failure, never a silent pass;
- the harness materializes a copy and never edits a tracked path;
- the named mutant set is at minimum the thirteen auditor-established ids
  listed in `tasks.md` T2157.
