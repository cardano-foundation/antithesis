# Modules model

Dependency direction is strictly downward. No lower row may import, source, or
call a higher row.

| ID | Module | Responsibility | Depends on | Owned by slice |
|---|---|---|---|---|
| M-01 | `scripts/daily-cardano-node-head.sh` | The only policy holder: stage sequencing, observation validation, census/equality/form assertions, submission reachability, receipt composition, fail-closed exits. Performs no external effect. | M-02 through the operation surface only | S1 |
| M-02 | `scripts/daily-cardano-node-head-github.sh` | The only effect holder: bare-remote observation, exact-rev Nix build, GHCR publication and digest read-back, containerized revision observation, topology rendering, Compose resolution and validation, fake submission, receipt persistence. Decides nothing. | external tools (`git`, `nix`, `docker`, `jq`) | S2 |
| M-03 | `tests/fixtures/daily-cardano-node-head/fake-transport.sh` | Deterministic test double for the M-02 operation surface, scenario-selected, logging every invocation. Never contacts the network. | none | S1 |
| M-04 | `tests/test-daily-cardano-node-head.sh` | Executes M-01 against M-03 once per scenario and asserts the invariant matrix, including every negative control and the submission-reachability counts. | M-01, M-03 | S1 |
| M-05 | `.github/workflows/daily-cardano-node-head.yaml` | Manual entrypoint that runs M-01 with M-02 in candidate mode and publishes the receipt; pull-request job that runs only M-04. | M-01, M-02, M-04 | S3 |
| M-06 | `docs/daily-cardano-node-head.md` | Operator documentation naming the manual recovery entrypoint, the stage machine, each fail-closed stop, and the receipt fields. | none | S3 |

## Boundaries

- **Policy/effect seam (M-01 ↔ M-02/M-03).** The transport operation surface in
  `functions-model.md` is the entire contract. Both implementations satisfy it;
  the controller is their only caller and validates every observation it
  receives, so a malformed real or fake observation is rejected identically.
- **Test double fidelity.** M-03 exists to drive M-01's decisions, not to
  simulate Docker, Nix, or GHCR. Any assertion that only the real boundary can
  settle (I215-03 live revision, I215-05 real Compose validity) is proved by the
  manual workflow run, never claimed by the fake.
- **Read-only surfaces.** `testnets/`, `scripts/daily-amaru*.sh`,
  `tests/test-daily-amaru.sh`, and every other existing script are read-only for
  this ticket. Rendering output goes to the controller state directory.

## Promotion

No abstraction is promoted to a shared owner. The Daily Amaru controller and
this controller deliberately stay separate executables: their stage machines,
receipts, and operation surfaces differ, and a premature shared library would
couple #216's schedule contract to an unrelated repository's daily job. If a
third controller appears, the recurring shape (transport-injected stage machine
with a fail-closed receipt) becomes a consolidation candidate for the epic
owner's invariant ledger.

## M-07 (mandate v2) — mutation harness

| ID | Module | Responsibility | Depends on | Owned by slice |
|---|---|---|---|---|
| M-07 | `tests/mutants/daily-cardano-node-head.sh` | Apply each named mutant to a throwaway copy of the tree, prove the mutation actually applied, run M-04 against it, and require every named mutant to be caught (I215-11). Never mutates the working tree. | M-04 | S1 |

M-07 is the instrument that keeps M-04 honest, and it is a check like any
other: it must itself be shown able to fail. A mutant whose edit silently does
not apply is a false negative, so each mutant verifies its own application
before the suite runs. M-07 mutates only a materialized copy; the candidate
tree must be byte-identical before and after a run.
