# Contract registry — milestone 1

| contract | parties | invariant | enforced |
|---|---|---|---|
| producer image | amaru-bootstrap publishes → cna compose pins | all 3 refs one digest, digest has validated run | CI-ENFORCED ✓ (#202/PR #203, merged fa39820): dynamic census — uniqueness + digest-form, nothing hardcoded; proven able to fail on 6 negative shapes; reachability demonstrated by completed CI job; validated runs behind current digest (ab36fa1b, 33fbed3c) |
| amaru CLI surface | pragma-org/amaru → amaru-bootstrap mocks/scripts | mocks ⊆ real binary surface | CI-enforced ✓ (#70/PR 71): explicit in Build Gate + justfile, drift-red proven against current pin, negative control on record |
| amaru log stream | amaru stdout → tracer-sidecar scoring | fatal lines reach the property | detector ✓ merged; scored property MERGED (cna#194) |
| compose/image entrypoint | cna compose command ↔ image Cmd/Entrypoint | pairing starts the sidecar | **NONE** — #196 open; config -q cannot see it |
| findings gate semantics | cna constitution ↔ observability PRs | new-finding ≠ revealed pre-existing failure | declared-property exemption MERGED (cna#198), operator-approved |
| upstream pin | pragma-org/amaru main → amaru-bootstrap flake | bare upstream, no forks | build gate ✓ (constitution P I) — proven able to fail: caught upstream peer-snapshot staging change RED (t68 A-001); upstream pragma-org/amaru#1102 OPEN, workaround-for stamped |
| global parameters | genesis → bundle → amaru env | AMARU_GLOBAL_* derived, not hand-authored | partial — #36 open |
