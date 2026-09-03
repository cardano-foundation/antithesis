# Modules model — Issue 236

Artifact ceiling: 2,500 bytes and 65 lines.

Only changed responsibilities are listed. Dependency direction is permanent
proof -> rendered Compose model -> public immutable OCI manifest.

## M236-1 — master testnet Compose definition

Changed responsibility: own the ordered four-producer Cardano Node release
matrix. Its FIFO head is rotated from 10.5.3 to 11.1.0 while inherited
producer behavior and all explicit retained producer/relay pins remain stable.

It does not own Amaru compatibility, adversary coverage, release discovery,
topology changes, or image publication.

## M236-2 — release-matrix proof

New responsibility: observe the rendered `cardano_node_master` Compose model,
assert exact ordered producer membership and immutable identities, protect the
unchanged relay pairing and scope boundary, and prove the relevant mutants can
fail. It is part of the repository's ordinary credential-free CI surface.

## M236-3 — public OCI registry boundary

Read-only external dependency: anonymously resolve the official 11.1.0 tag to
its multi-platform manifest, observe linux/amd64 membership, and supply the
image used by the bounded command probe. No credentials or publication effects.

## M236-4 — master-testnet documentation

Changed responsibility: state the producer release matrix and ring labels that
M236-1 actually renders. It contains no independent release-selection rule.
