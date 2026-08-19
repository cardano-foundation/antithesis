# Modules model — Issue 223

Artifact ceiling: 3,500 bytes and 70 lines.

Dependency direction is unchanged: workflow → controller → transport → GitHub.
No new module and no new dependency edge. Two existing modules gain one
responsibility each; one gains none and is only re-routed.

## `.github/workflows/daily-amaru.yaml` — trigger surface

Gains a typed `workflow_dispatch` input and a routing rule. Owns no spend
decision: it selects which of the two existing jobs runs and nothing more. The
production job it selects for a dispatch is the identical job the schedule
selects — a single definition, never a copy.

## `scripts/daily-amaru.sh` — controller

Gains the workflow-head derivation, validation, and export, mirroring the day
boundary repaired by #221, and gains one ordering duty: the launch claim is a
stage of its own, immediately before the launcher. Owns the mapping from a
refused claim to a named stage and error in the durable receipt. Owns no
knowledge of how a marker is stored.

## `scripts/daily-amaru-github.sh` — transport

Owns the durable marker vocabulary on issue #210 and every claim decision made
from it: one census reader that fails closed, and three claim operations that
share it. Owns the supersede rule. The controller learns a verdict, never a
marker string.

## `tests/fixtures/daily-amaru/fake-transport.sh` — deterministic fixture

Must implement exactly the claim-operation set the production transport
implements, reconciled mechanically as `tests/test-daily-amaru.sh` already
reconciles the day-requiring operation set (#221 FR-05). A fixture free to
accept an operation production rejects cannot observe the defect it exists for.

## `tests/test-daily-amaru.sh` — the proof

The single home for every #223 proof, because it is the only proof this
repository runs in hosted CI. Owns the routing census, the cap and supersede
scenarios, the fail-closed census case, the head-propagation census, and the
mutants. Consumes the workflow file, the controller, the production transport,
and both fixtures.

## Promotion

None. Every new responsibility lands on the module that already owns its
neighbours; no shared abstraction is justified by two call sites.
