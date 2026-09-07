# Plan — Issue 236 Cardano Node 11.1.0 FIFO rotation

Artifact ceiling: 4,500 bytes and 110 lines.

## Technical context

The issue lane starts from frozen main `fe039ac5582081297b38709a6862083cc2fb6c00`.
The exact worktree baseline `nix develop --quiet -c just ci` exited 0 on
2026-09-03. The master Compose anchor supplies p1's 10.5.3 image; p2, p3, and
p4 override it with 10.6.2, 10.7.1, and 11.0.1. Relays intentionally mirror
only the retained release pins.

## Architecture decisions

- Treat the four producer images as an ordered release matrix, not unrelated
  string substitutions. The first slot is the FIFO head and is the only
  production value rotated by this ticket.
- Preserve the shared producer anchor and every consumer of its command,
  environment, dependency, and restart contract. Only its image identity
  changes.
- Pin the public multi-platform 11.1.0 manifest. A platform-child digest would
  make the Compose definition host-specific and is therefore rejected.
- Put the permanent release-matrix proof next to the repository's existing
  shell verification surface and include it in `just ci`; it observes rendered
  Compose rather than merely matching a source line.
- Keep live registry and container-start evidence outside credential-free CI.
  The frozen gate runs it explicitly and records its result.

## Slice

One bisect-safe OWNER slice, **S236-01**. The production pin, documentation,
permanent RED/GREEN proof, mutation controls, and CI wiring form one semantic
change. The live OCI boundary and cross-platform manifest judgment require
independent review, so LIGHT is not eligible.

## Proof strategy

- Begin with a permanent focused check that fails on the frozen base because
  the rendered p1 image is 10.5.3 and 11.1.0 is absent.
- Use four distinguishable release/digest values; exact membership and
  multiplicity must prevent a duplicated retained value from passing.
- Demonstrate verified-applied mutants for restoring the evicted digest and
  replacing the immutable reference with a tag or platform-child digest.
- Compare structural Compose output or a narrowly selected base/candidate
  projection so unchanged relays, topology, command, mounts, and unrelated
  testnets remain observable.
- At the live boundary, resolve anonymously, verify the manifest platform, and
  execute a bounded command against the linux/amd64 image. No publication,
  credentials, or Antithesis launch is authorized.

## Verification envelope

- Frozen untracked `./gate.sh` and its runtime backup/hash.
- Focused release-matrix proof, shell analysis, and Compose rendering.
- Anonymous OCI manifest resolution and bounded image command probe.
- Complete `nix develop --quiet -c just ci`.
- Required hosted PR checks on the exact pushed head.

## Stop conditions

Stop before modifying any non-master testnet, relay image, topology, command,
mount, workload, fault policy, or Antithesis workflow; introducing credentials;
publishing images; or launching an Antithesis test.
