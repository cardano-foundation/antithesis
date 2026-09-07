# Contract registry — milestone 2

Updated 2026-09-07T11:55:50Z. Every `NONE` below is a scheduled incident with
an owner/disposition; none is silently treated as green.

## Enforced or standing inherited contracts

| contract | parties | invariant | enforcing evidence |
|---|---|---|---|
| producer image identity | amaru-bootstrap publishes → cna compose pins | every compose reference resolves to one digest and that digest has validated provenance | cna#202/PR#203 dynamic census and six negative shapes |
| Amaru CLI surface | pragma-org/amaru → amaru-bootstrap mocks/scripts | mocks are a subset of the real binary surface | amaru-bootstrap#70/PR#71 drift-red proof |
| Amaru log stream | Amaru stdout → tracer-sidecar scoring | fatal lines reach the scored property | cna#194 positive control |
| compose/image entrypoint | cna compose command ↔ image Cmd/Entrypoint | the real pairing starts the sidecar | cna#196/PR#209 live-boundary check with seeded mismatch |
| trunk merge gate | GitHub main ruleset ↔ lane merge discipline | required checks are effective before an unattended merge | ruleset 20131742 plus guard-merge discipline |
| peer-snapshot bundle | daily controller → amaru-bootstrap pins, resolution record and staged bytes | every Amaru pin change atomically refreshes the complete anchored bundle | cna#227/PR#228 plus shipped resolver |
| bootstrap check observation | amaru-bootstrap CI → cna controller | pending, absent, completed failure, success and transport failure remain distinct | cna#229/#231/PR#230, extended by #234/#235/#239 |
| external publication boundary | lane evidence → operator → external humans | agents prepare evidence but never publish or speak as the operator | standing operator order; clause in briefs and acceptance audit |

## Current milestone contracts

| contract | parties | invariant | enforcement / disposition |
|---|---|---|---|
| automation trigger | pragma-org/amaru main → daily controller | once per UTC day a changed head enters the governed path; unchanged days are observably safe | **PARTIAL** — walking skeleton and hardening landed; first schedule carrying PR #239 is 2026-09-08 |
| validated image handoff | amaru-bootstrap#75 → cna#207/#208 | tag, digest and provenance bind the exact validated image | **NONE** — PR #76 is draft/incomplete; scheduled through #75 then #79 |
| harness-interface coverage | current Amaru ↔ mocks/compose/sidecars | current interface is covered or alarms; green is never vacuous | **NONE** — cna#208 is the commissioned destination; ab#110 is the open mutation-instrument gap |
| run-report honesty | controller → per-property report → desk | missing, pending, failed and partial runs are loud and distinct | **PARTIAL** — #234/#235/#239 landed; cna#206 and cna#232/PR#233 remain; general run-level loudness and F-OBS-05 remain open |
| successful no-op state | controller exit-zero outcomes → next scheduled run | every successful outcome leaves the next run distinguishable from failure while a failed attempt stays red | **NONE / ACTIVE SLICE** — `t-unchanged-head` under epic owner `%432`; no GitHub issue by design |
| fork-depth semantics | tracer-sidecar host map → protocol finding | stale relay lag cannot masquerade as producer divergence; host identity and k stay bound | **NONE** — cna#140 is open, planned, not yet commissioned; no waiver |
| cardano-node image freshness | configured testnet images → Antithesis freshness property | the intended tested image is recent without hiding functional failures | **NONE / OPERATOR DECISION** — cna#236/PR#238 is specs-only and red; latest run 34095717978 is 68/69 with only freshness failing |
| daily receipt existence | GitHub schedule → external watchdog | a dead schedule is detected outside the workflow it watches | **NONE** — cna#232/PR#233 is draft and unlanded |
| declared-red ledger | triage decision → future run reports | a declared red remains declared until a verified fix and recorded decision clear it | **NONE** — required after the daily path is operating; no waiver |
| carried era-history patch retirement | upstream Amaru bootstrap surface → amaru-bootstrap patch | the explicit patch applies to the pinned upstream and retires when equivalent upstream support lands | **ENFORCED BUT BRITTLE** — rebased through ab#96/#106/#109; retirement detector exists; upstream publication remains operator-only |
| daily-loop day derivation | workflow schedule → controller transports | every child receives one derived UTC day | **ENFORCED WITH ADVISORY** — cna#221 landed; residual CNA205-DAY-SOURCE-NONCE-01 stays visible |

## Contract-change routing

The M2 desk arbitrates cross-epic/repository contract changes and sequencing;
it never designs or implements them. Epic owner `%432` must escalate a touch
to this registry before a child changes a registered contract. Constitutional,
destructive, external-human and issue-236 disposition decisions go to the
operator with evidence and a recommendation.
