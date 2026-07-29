# Issue 200 — Adopt the Amaru consensus-fix producer image

## Priority story

As the operator of the `cardano_amaru` Antithesis stack, I need every
Compose consumer of the Amaru bootstrap producer to use the immutable image
that contains the upstream rollback fix so the decisive fault-injection run
can establish whether the fatal consensus signature is absent.

## Functional requirements

- FR-001: All three `amaru-bootstrap-producer` image references in the
  Compose tree use:

  `ghcr.io/lambdasistemi/amaru-bootstrap-producer:cf657b918787c213c09ffef3879ac4a2552dd680@sha256:72906da307862ee5652a35d2e6569fcd929ddd5785ad6d633b42e4912faef147`

- FR-002: The Compose tree contains exactly three producer-image references
  and zero producer-image references to any other tag or digest.
- FR-003: Docker Compose accepts the updated model, the repository gate
  passes, and the `cardano_amaru` local smoke passes.
- FR-004: The PR remains unmerged until the milestone desk records explicit
  authorization through the runtime Q/A protocol.
- FR-005: After the authorized PR merges, a 60-minute Antithesis
  fault-injection run is launched from the merged commit.
- FR-006: `no fatal amaru consensus logs` is present and scoring with zero
  counterexamples. Both `attempted roll back in the future` and
  `Consensus died` are absent from the retained evidence.
- FR-007: If either fatal signature appears, stop, retain raw evidence, and
  escalate immediately; do not rationalize or reclassify the failure.
- FR-008: The completed run report lists every property and explicitly
  accounts for the declared `pragma-org/amaru#1104` rewards-panic/container
  exit red and the `cardano-node-antithesis#140` stale-consumer fork-depth
  artifact. Every other red is triaged as a genuine finding and filed
  upstream when unowned.

## Success criteria

- A positive control proves the census method finds the three old references
  before the edit.
- After the edit, the same Compose-tree census finds exactly three producer
  references, all equal to the required tag-plus-digest, and a complementary
  search finds zero references on any other tag or digest.
- Compose validation, the full gate, and the local smoke exit zero.
- The one-hour run is launched only from the authorized merged commit.
- The desk receives a complete per-property report whose ABSENT/RED
  accounting distinguishes the required fatal-signature absence, declared
  #1104 red, expected #140 artifact, and any genuine new finding.

## Scope boundaries

- Do not change findings-gate semantics, assertion code, declared-property
  exemptions, the test constitution, or fatal-log scoring.
- Do not suppress, weaken, or game any scored property.
- Do not change `amaru-bootstrap`, Amaru source, or any artifact other than
  the binding producer-image reference above.
- Do not update non-Compose documentation image examples.
- Merge only after the milestone desk records authorization.

## Provenance

This is the downstream acceptance run for
`lambdasistemi/amaru-bootstrap#67`. The supplier image came from merged
`lambdasistemi/amaru-bootstrap#74`, which adopted upstream Amaru fix
`437ff6c4fb506e1347eee9e619271a5ccb55a401`. Issue #195 and PR #199 provide
the previous repin and run-report pattern.
