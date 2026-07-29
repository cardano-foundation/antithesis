# Issue 202 — Enforce the Amaru producer-image contract

## Priority story

As a maintainer changing Compose configuration, I need the local mechanical
gate and pull-request CI to reject an Amaru bootstrap producer reference that
drifts from its peers or loses its immutable digest, so the cross-repository
producer/consumer contract cannot silently regress after the manual repair in
#192.

## Functional requirements

- FR-001: A repository-conventional shell check discovers every image field
  referencing `ghcr.io/lambdasistemi/amaru-bootstrap-producer` in Compose
  files below `testnets/`.
- FR-002: Discovery is dynamic. The check must not hardcode the present
  reference count, current tag, or current digest.
- FR-003: Discovery returning zero producer-image references is a failure,
  because an empty census cannot establish the contract.
- FR-004: Every discovered producer-image value has the complete form
  `repository:tag@sha256:<64 hexadecimal characters>`.
- FR-005: All discovered producer-image values are byte-for-byte identical.
- FR-006: The passing output reports the discovered count and the one resolved
  image value, making a real pass distinguishable from a vacuous invocation.
- FR-007: The tracked repository `gate.sh` invokes the check.
- FR-008: A workflow triggered for pull requests to `main` invokes the check
  through an explicit, reviewable command.
- FR-009: Mechanically captured evidence demonstrates failure against two
  uncommitted temporary seeds: one valid-but-different producer reference and
  one tag-only producer reference.

## Success criteria

- The unchanged tree passes and prints a non-zero producer-reference count plus
  its unique digest-pinned value.
- A temporary one-reference drift exits non-zero and identifies disagreement.
- A temporary tag-only reference exits non-zero and identifies the missing
  digest pin.
- Neither seed appears in the committed diff.
- Running the tracked local gate shows the new check was invoked and passed.
- Pull-request CI reaches the explicit workflow step and its retained log shows
  the same non-vacuous passing output.

## Scope boundaries

- Do not change any current producer image tag or digest.
- Do not hardcode the current count, tag, or digest in the checker.
- Do not change Compose service behavior.
- Do not touch findings-gate behavior, declared-property handling,
  constitution semantics, or Antithesis property scoring.
- Do not introduce a second gate framework; extend the tracked project gate
  and an existing pull-request workflow.
- Merge only after the Milestone 1 desk records explicit authorization through
  the runtime Q/A protocol.

## Provenance

Issue #192 records the producer-image drift that maintainers previously found
and repaired by hand. The enforced contract is the repository side of the
cross-repository boundary:

`amaru-bootstrap publishes -> cardano-node-antithesis Compose pins`.

