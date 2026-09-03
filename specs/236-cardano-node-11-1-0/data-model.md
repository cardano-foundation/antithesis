# Data model — Issue 236

Artifact ceiling: 2,500 bytes and 70 lines.

## D236-1 — Producer release matrix

- Ordered services: `p1`, `p2`, `p3`, `p4`.
- Ordered releases after rotation: `11.1.0`, `10.6.2`, `10.7.1`, `11.0.1`.
- Each service has one immutable OCI digest.
- Set invariant: the four releases are distinct and equal exactly
  `{10.6.2, 10.7.1, 11.0.1, 11.1.0}`.
- FIFO invariant: only the prior head, 10.5.3 at p1, is evicted.

## D236-2 — 11.1.0 image identity

- Repository: `ghcr.io/intersectmbo/cardano-node`.
- Release tag: `11.1.0` (resolution input only, never shipped).
- Shipped multi-platform manifest digest:
  `sha256:78a3a5113b5989115a21bba74b8a990799aa43e5f9165641b9f0c062c266b58a`.
- Required platform: `linux/amd64`.
- Known amd64 child digest, prohibited as the shipped Compose identity:
  `sha256:7b36384afd9d78e787c02f9b9a0868ed74b28a04b7d447325a68b1f397ddb43a`.

## D236-3 — Preserved relay matrix

- `relay1` remains paired with 10.6.2.
- `relay2` remains paired with 10.7.1.
- `relay3` remains paired with 11.0.1.
- No 11.1.0 relay is introduced by this ticket.

## D236-4 — Scope projection

The changed tracked paths may contain the master Compose image rotation,
matching documentation, the focused proof and minimal test-runner wiring, and
the ticket planning artifacts. No other testnet or workflow state belongs to
this change.

