# Modules model — Issue 213

Artifact ceiling: 4,000 bytes and 90 lines.

Only changed responsibilities are listed. Data IDs refer to
`data-model.md`; interface IDs refer to `functions-model.md`.

| ID | Component | Changed responsibility | Depends on | Must not own |
|---|---|---|---|---|
| MOD-213-01 | `.github/workflows/daily-amaru.yaml` | Provision the scheduled command set; request D213-02 from the dedicated App interface; bind D213-03 only to the controller step; durably publish D213-01 on every outcome | MOD-213-02, GitHub Actions token minting | Controller policy, App creation/installation, secret persistence, real-run authorization |
| MOD-213-02 | `scripts/daily-amaru.sh` | Enforce INV-213-01 and INV-213-04; maintain D213-01 locally before external publication; preserve existing ordered state-machine policy | FN-213-01, FN-213-02, MOD-213-03 | Repository-specific API mechanics or token minting |
| MOD-213-03 | `scripts/daily-amaru-github.sh` | Validate D213-04; publish receipts with the minimum viable dependency surface; keep D213-02 and D213-03 on their distinct repository boundaries | FN-213-03 through FN-213-06 | Daily policy, App credentials, consumer self-merge, live authorization |
| MOD-213-04 | `tests/test-daily-amaru.sh` and `tests/fixtures/daily-amaru/**` | Prove INV-213-01 through INV-213-09 with dated incident evidence, non-vacuous receipt validation, and explicit effect counts | MOD-213-01 through MOD-213-03 | Production credentials, network mutation, real launch |
| MOD-213-05 | `docs/daily-amaru.md` | Describe the explicit runner/App interface, failure receipts, operator setup gate, and local proof | D213-01 through D213-04 | Secret values or claims that live setup is complete |

Dependency direction is workflow → controller → transport. Proof observes all
three but production never depends on proof code. Receipt durability belongs
at the controller/workflow seam so a failed transport command cannot erase the
only failure record.
