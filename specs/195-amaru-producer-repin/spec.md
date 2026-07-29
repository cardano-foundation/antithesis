# Issue 195 — Repin the Amaru producer image and validate it

## Priority story

As the operator of the `cardano_amaru` Antithesis stack, I need every
Compose consumer of the Amaru bootstrap producer to use the newly published,
immutable producer artifact so the one-hour validation run tests one known
image rather than a mixture of tags or digests.

## Functional requirements

- FR-001: All three `amaru-bootstrap-producer` image references in
  `testnets/cardano_amaru/docker-compose.yaml` use:

  `ghcr.io/lambdasistemi/amaru-bootstrap-producer:2d0f4451630b7587851e9238cb43a34e3200e8cf@sha256:deff22e851d9703b344a75c20f5deeb8374258f3cc5716edf237e69d2f5ab108`

- FR-002: The Compose file contains zero producer-image references to the
  previous tag or any other tag/digest.
- FR-003: Docker Compose accepts the updated model.
- FR-004: The repository gate and the `cardano_amaru` local smoke test pass.
- FR-005: After the PR merges with desk authorization, a one-hour Antithesis
  run is launched from the merged commit.
- FR-006: The completed run report lists every property's pass/fail result.
  The fatal-consensus signature owned by `pragma-org/amaru#1098` is an expected
  red and must remain visible. Every other new red is triaged and reported.

## Success criteria

- The Compose reference census is exactly three and all three lines resolve to
  the required tag and digest.
- A positive control proves the census command can find the old references
  before the edit; after the edit it finds three new references and zero old
  Compose references.
- Compose validation, the full gate, and the local smoke exit zero.
- The one-hour run is launched only from the merged commit and its report is
  delivered to the milestone desk.

## Scope boundaries

- Do not change findings-gate semantics, the constitution, assertion
  exemptions, or fatal-log scoring.
- Do not suppress or game the expected fatal-consensus red.
- Do not change `amaru-bootstrap` or adopt any image other than the binding
  tag-plus-digest above.
- Merge only after the milestone desk records authorization.
