# Rotate Cardano Node 11.1.0 into the master FIFO matrix

Issue: cardano-foundation/cardano-node-antithesis#236

Frozen main base: `fe039ac5582081297b38709a6862083cc2fb6c00`

Artifact ceiling: 6,000 bytes and 140 lines.

## Context

`cardano_node_master` currently runs producer releases 10.5.3, 10.6.2,
10.7.1, and 11.0.1. Cardano Node 11.1.0 was published on 2026-08-21 as
the next available release. The operator has chosen FIFO rotation: evict the
oldest producer release, 10.5.3, and preserve the other three slots.

The 11.1.0 OCI tag resolves to the immutable multi-platform manifest digest
`sha256:78a3a5113b5989115a21bba74b8a990799aa43e5f9165641b9f0c062c266b58a`.

## Requirements

- **R236-1 — FIFO membership.** The four `cardano_node_master` producers run
  10.6.2, 10.7.1, 11.0.1, and 11.1.0 exactly once. The 10.5.3 producer image
  is absent.
- **R236-2 — immutable release identity.** The new 11.1.0 slot references the
  release's immutable multi-platform OCI digest. A mutable tag, platform-child
  digest, or unrelated digest is not an acceptable replacement.
- **R236-3 — preserved shape.** Producer identities, configuration mounts,
  command contract, topology, and existing relay pairings are unchanged.
- **R236-4 — executable proof.** A permanent focused check observes the
  rendered Compose model, distinguishes all four producer values, and rejects
  restoration of 10.5.3 or substitution of a mutable 11.1.0 reference.
- **R236-5 — live image boundary.** Anonymous registry resolution confirms the
  pinned manifest is 11.1.0 and includes linux/amd64; its amd64 image starts
  with the repository's existing cardano-node command contract.
- **R236-6 — documentation truth.** User-facing master-testnet documentation
  names the same four producer releases and topology that Compose renders.

## Invariants

All rows are `BLOCKING`: the matrix controls nodes that produce test chain
state, and a false release identity invalidates the compatibility experiment.

| ID | Severity | Observable truth | Demonstrated failure | Observable success |
|---|---|---|---|---|
| INV-236-1 | BLOCKING | Producer release membership is exactly 10.6.2, 10.7.1, 11.0.1, 11.1.0 | restore the 10.5.3 digest or duplicate one retained producer | rendered Compose exposes four distinguishable producer images matching the ordered FIFO set |
| INV-236-2 | BLOCKING | 11.1.0 is bound to its immutable multi-platform manifest | replace it with `:11.1.0`, its amd64 child, or another digest | the pinned digest equals the anonymously resolved 11.1.0 manifest and advertises linux/amd64 |
| INV-236-3 | BLOCKING | FIFO rotation changes only the evicted producer release and matching documentation/proof | alter relay images, service shape, mounts, topology, Amaru, or adversary surfaces | structural comparison to the frozen base differs only at the owned release/documentation/proof surfaces |
| INV-236-4 | BLOCKING | The 11.1.0 image accepts the existing node startup contract | run the image with an invalid or missing node command as a positive control | the pinned linux/amd64 image executes the existing node command entry boundary successfully |

## Scope

Owned production surface is
`testnets/cardano_node_master/docker-compose.yaml`. Matching master-testnet
documentation, one focused permanent proof, and the minimal CI/Just wiring
needed to execute that proof are owned. `cardano_amaru`,
`cardano_node_adversary`, relay pins, topology, workload images, fault policy,
and test duration are forbidden.

## Observable completion

- The focused proof is shown RED on the frozen base, then GREEN on the
  candidate, with verified-applied FIFO and mutable-reference mutants rejected.
- `docker compose ... config` succeeds and exposes the exact producer set.
- The anonymous live-image boundary for 11.1.0 succeeds.
- `nix develop --quiet -c just ci` passes on the final tree.
