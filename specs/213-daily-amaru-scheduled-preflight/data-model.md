# Data model — Issue 213

Artifact ceiling: 4,000 bytes and 100 lines.

| ID | Data | Required fields / shape | Invariants |
|---|---|---|---|
| D213-01 | Failure receipt | `day` as UTC `YYYY-MM-DD`; precise `stage`; `outcome=FAILED`; specific stable `error`; existing observation/effect fields when known | INV-213-01, INV-213-02, INV-213-04 |
| D213-02 | Bootstrap App interface | variable name `DAILY_AMARU_APP_ID`; secret name `DAILY_AMARU_APP_PRIVATE_KEY`; owner `lambdasistemi`; repository set containing only `amaru-bootstrap`; permissions exactly actions read, checks read, contents write, pull requests write, metadata read | INV-213-03, INV-213-05 |
| D213-03 | Minted bootstrap identity | short-lived token output from D213-02; empty when configuration or minting is unavailable; step-scoped and secret-valued | INV-213-03 through INV-213-05 |
| D213-04 | Scheduled dependency census | explicit non-shell command names required by every reachable production transport operation, including the incident command `rg`; each has provisioned and observed status | INV-213-01, INV-213-07, INV-213-09 |
| D213-05 | Effect census | counts for attempt claim, bootstrap proposal, image resolution, consumer repin, supervised integration, fake launch, and real launch | INV-213-06 through INV-213-08 |
| D213-06 | Incident evidence | base SHA `311dfc1d499277b23035a107eaf0ec097cf3d948`; days `2026-08-02` and `2026-08-03`; fingerprint `daily-amaru-github: missing command: rg`; exit, receipt, and D213-05 observations | INV-213-02, INV-213-07 |

The stable precondition verdicts are `stage=runner-preflight` with
`error=missing-command-rg`, and `stage=identity` with
`error=missing-production-identity`.

D213-02 and D213-03 authorize only the bootstrap repository. The workflow's
default short-lived repository token is a separate value for cna issue and
consumer operations and is never represented as D213-03.

Failure receipts and intentional failure-publication bookkeeping are evidence,
not business mutations. INV-213-06 forbids attempt/bootstrap/image/consumer/
integration/launch effects while still requiring the failure evidence itself.
