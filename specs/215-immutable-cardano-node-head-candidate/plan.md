# Plan: immutable Cardano Node master HEAD Antithesis candidate

## Strategy

Reuse the accepted repository pattern established by the Daily Amaru walking
skeleton (`scripts/daily-amaru.sh`, `scripts/daily-amaru-github.sh`,
`tests/fixtures/daily-amaru/fake-transport.sh`, `tests/test-daily-amaru.sh`,
`.github/workflows/daily-amaru.yaml`): all policy lives in one
transport-injected controller, all external effects live behind one transport
operation surface, and a deterministic fake transport makes every fail-closed
boundary locally executable.

The candidate path is a linear stage machine. Each stage calls exactly one
transport operation, validates its observation in the controller, appends a
`CandidateReceiptV1` record, and either continues or fails closed:

```text
resolve-upstream → publish-candidate → prove-revision
  → render-topology → verify-topology → validate-compose
  → submit-candidate (fake only in #215) → complete
```

Policy never lives in the transport. The transport observes and effects; the
controller decides. Uniformity, form, equality, census, and reachability
assertions are controller-side so the fake transport can drive every one of
them without Docker, Nix, or a registry.

## Constraints

- Only Codex/Claude/Grok-authored shell; no new language or dependency.
- Local test execution must stay hermetic: no Docker, Nix build, registry, or
  network access in `tests/test-daily-cardano-node-head.sh`.
- The manual workflow performs real Nix build, real GHCR publication, real
  container execution, and real Compose validation. Only the submission
  boundary is fake.
- `testnets/cardano_node_master/` is read-only for this ticket; rendering
  writes into the controller state directory.
- Secrets reach only the process environment of the effecting command.

## Live boundaries

| Boundary | Where it is crossed | Failure mode it catches |
|---|---|---|
| Upstream ref observation | `git ls-remote` on the bare origin | wrong repository, wrong ref, ambiguous or empty remote |
| Upstream build | `nix build` of the exact-rev `dockerImage/node` output | HEAD that does not build; substituter unavailability |
| Registry publication | GHCR push plus digest read-back | tag that resolves to no immutable digest |
| Binary revision | running the published image's `cardano-node` | correctly named image containing the wrong artifact |
| Topology resolution | Compose's own resolution of the rendered model | anchor/override interactions that file-text substitution hides |

The binary-revision and Compose-resolution boundaries are the two that unit
assertions cannot reach; both are mandatory in the real transport and are
exercised by the manual workflow run, not by the hermetic test suite.

## Resolved parent-plan inconsistencies

The parent's `research.md` is preliminary. These #215 decisions supersede it
inside this ticket's scope and are reported upward as informational:

| Parent item | Resolution for #215 | Rationale |
|---|---|---|
| R-001 requires `ci/hydra-build:required` success on the exact SHA | Not required. | Building the exact Nix output, publishing it, and proving the live binary revision strictly dominates a third-party check-status observation. A HEAD that does not build already fails closed at `publish-candidate`. #216 may re-add Hydra as a cheap pre-filter, never as identity. |
| R-002 requires the artifact *from the upstream Nix cache* | Build the exact flake output with `cache.iog.io` configured as a substituter; a cache hit is an optimization, not a contract. | Making a cache miss a hard failure would make the manual entrypoint flaky for reasons unrelated to candidate identity. Runaway builds are bounded by the workflow timeout, which fails closed. |
| R-003 creates a consumer commit/branch per candidate | Out of scope. #215 renders and validates the model in the state directory and commits nothing. | The generated-commit contract belongs to the submission path (#216). #215 must not create branches, PRs, or merges. |
| R-004/R-005 own the launcher, day claim, and issue-comment receipts | Out of scope. #215's receipt is a durable file artifact published by the workflow run. | A day claim or issue-#214 receipt stream would pre-empt #216's contract. |
| R-003 notes "all seven producer/relay image values" | Adopted as the exact expected census `p1 p2 p3 p4 relay1 relay2 relay3`, asserted on the resolved model. | A positive, exact census cannot be satisfied vacuously by an empty match. |

## Risks

| Risk | Mitigation |
|---|---|
| Upstream flake evaluation/build exceeds runner budget | explicit workflow and step timeouts; timeout is a fail-closed `publish-candidate` failure with an honest receipt |
| GHCR namespace pollution from repeated manual runs | tag is the full upstream SHA, so a repeated candidate is idempotent by construction |
| Fake transport drifting from the real operation surface | both implement one documented operation surface; the controller is the only caller and rejects malformed observations from either |
| Uniformity proved on text instead of resolution | `verify-topology` consumes Compose-resolved rows only |

## Mandate v2 — why the proof architecture is now specified

The first S1 campaign produced two audited submissions. Both passed every
named verification command, the frozen slice gate, and the ticket gate; both
were rejected by independent auditors on mutation and value coverage. Reports:
`audit-report-S1-submission-1.md` (8 blocking, sha256 `4a211292…`) and
`audit-report-S1-submission-2.md` (6 blocking, sha256 `42858079…`).

Every surviving mutant across both audits is one shape: **the fake transport
was both the effect double and the source of the expected values**, so
assertions compared the controller against numbers derived from the
controller's own arguments. Deleting the origin requirement, the rendered-model
witness, the node-image comparator, the zero-census guard, or the Compose
target each left the suite green.

Two structural consequences, both now part of the mandate:

1. `spec.md` "Proof architecture" constrains how proofs are built, not only
   what they assert.
2. I215-11 makes mutation survival an invariant, and the mutation harness
   becomes a shipped repository artifact rather than an auditor's scratch
   work. Both auditors built such a harness by hand and both were discarded;
   the second one — 13 named mutants, each verifying that its own mutation
   applied before running the suite — is the seed for the shipped one.

The named mutant set is the auditor-established minimum. On the rejected
candidate `508efd33` it caught 5 and missed 8; all 13 must be caught.

## Slices

Ordered, bisect-safe, each one OWNER-mode with a Grok commit owner and a fresh
Codex auditor.

### S1 — `controller-policy`

Controller, deterministic fake transport, and the test suite. Adds
`scripts/daily-cardano-node-head.sh`,
`tests/fixtures/daily-cardano-node-head/fake-transport.sh`, and
`tests/test-daily-cardano-node-head.sh`. Proves I215-01, I215-02 (form),
I215-04, I215-05 (policy), I215-06, I215-07, I215-08, I215-09. The controller's
default transport path names the not-yet-existing real transport and fails
closed when it is absent; every test injects the fake.

### S2 — `github-transport`

Adds `scripts/daily-cardano-node-head-github.sh` implementing the same
operation surface for real: bare-remote observation, exact-rev Nix build,
GHCR publication, digest read-back, containerized revision proof, rendering
from `testnets/cardano_node_master/docker-compose.yaml` into the state
directory, Compose-resolved topology rows, Compose validation, fake submission,
and receipt persistence. Proves I215-02 (digest), I215-03, I215-04 (real
render), I215-05 (real Compose), I215-10.

### S3 — `manual-entrypoint`

Adds `.github/workflows/daily-cardano-node-head.yaml` and
`docs/daily-cardano-node-head.md`. The workflow exposes a `workflow_dispatch`
candidate job that runs the real path with the fake submission transport and
uploads the receipt, plus a `pull_request` job that runs only the hermetic test
suite. Proves R-07 and R-09, and re-proves I215-07 at workflow level: no job
selects a real submission mode.

## Verification

Ticket-level commands, preserved from the parent brief:

```sh
nix develop --quiet -c tests/test-daily-cardano-node-head.sh
nix flake check --no-build --no-write-lock-file
bash -n scripts/daily-cardano-node-head.sh \
        scripts/daily-cardano-node-head-github.sh \
        tests/test-daily-cardano-node-head.sh
./gate.sh
git diff --check 311dfc1d499277b23035a107eaf0ec097cf3d948...HEAD
```

The ticket gate additionally runs `shellcheck` over the new shell, re-runs
`tests/test-daily-amaru.sh` as a regression, and asserts that
`testnets/cardano_node_master/docker-compose.yaml` is byte-identical to its
frozen-base blob (I215/R-10). Slices S1 and S2 name commands that cannot pass
before their own files exist; each slice gate is proved able to fail against
the frozen base before dispatch.

## Mandate v3 — I215-07 moves from observation to containment

Campaign 3 closed with two blocking findings that were, again, I215-07. Across
four consecutive audits the same invariant failed with a different escape each
time: one forbidden command name; two syntactic invocation forms; `execve`-only
tracing; and finally an inherited descriptor plus a filesystem write. The last
audit demonstrated the escape with **a single one-line change to the fake
transport and no edit to the suite at all** — 1,845 bytes reaching an external
TCP listener while the suite printed `PASS no-real-submission`.

Every one of those repairs was correct. The mandate was wrong: it asked for the
egress channels to be *enumerated*, and that set is open-ended. Worse, the
observer established its own traced region from inside the file it observes, so
it could never bound what crossed into the region before it started.

v3 therefore proves I215-07 by containment — see `spec.md` "I215-07 is proved by
containment, not observation". The suite runs inside an OS-enforced container
with no network and no writable path outside its scratch root; green inside
those walls is the proof, and the walls themselves carry negative controls.

This is expected to be **smaller and cheaper** than what it replaces: it deletes
the syscall observer and its allowlist, removes roughly 285 seconds per gate
run, and ends the enumeration loop. If it turns out larger, that is a signal the
approach is wrong and the owner should stop and ask rather than proceed.

Everything else from campaign 3 is retained: D-05 receipt value coverage
(13/13, no holes, enumeration live in both directions), the model-derived
rendered-model witness inventory, the guard-ablation sweep (33/33, zero
survivors), determinism, and the R-02 image-repository default. None of it may
regress.
