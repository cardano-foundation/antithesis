# Tasks — Issue 236 Cardano Node 11.1.0 FIFO rotation

Artifact ceiling: 2,500 bytes and 65 lines.

## Slice S236-01 — Rotate the master producer matrix

- [ ] **T2361** Commit a permanent executable RED proof over rendered Compose
  for exact four-release membership, multiplicity, immutable identity, retained
  relay pairing, and owned scope.
- [ ] **T2362** Rotate only the FIFO head from Cardano Node 10.5.3 to the
  immutable multi-platform Cardano Node 11.1.0 manifest.
- [ ] **T2363** Update master-testnet documentation to the same producer matrix
  without changing topology or other testnets.
- [ ] **T2364** Demonstrate verified-applied old-digest, mutable-tag, child-
  digest, and duplicate-release mutants are rejected by the permanent proof.
- [ ] **T2365** Pass Compose rendering, the anonymous 11.1.0 live-image probe,
  the frozen gate, and full local CI; receive fresh independent audit and all
  required hosted checks on the exact final head.

The ticket owner checks these tasks only after a fresh audit passes the exact
candidate. The parked commit owner then includes only the task stamp in the
final commit.
