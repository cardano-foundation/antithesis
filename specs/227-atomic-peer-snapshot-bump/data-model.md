# Data model — Issue 227

Artifact ceiling: 3,500 bytes and 90 lines.

## D227-1 — Atomic bootstrap proposal

- **Base:** cloned bootstrap `origin/main`.
- **History:** exactly one proposal commit above that base.
- **Changed paths:** exactly `flake.lock` and
  `nix/peer-snapshots/resolution.json`.
- **Publication state:** unpublished until D227-2 is valid and final resolver
  verification succeeds.

## D227-2 — Anchored resolution tuple

Fields consumed from bootstrap-owned artifacts:

- `flake.lock` Amaru revision;
- `flake.lock` cardano-configurations revision;
- resolution-record `amaru_rev`;
- resolution-record `configs_rev`;
- three per-network hashes and resolution provenance owned by the resolver.

State invariant: both Amaru fields are equal, both configurations fields are
equal, and the configurations value is the resolver-selected non-default
revision. Hash/provenance validity remains bootstrap-resolver and anchor-owned.

## D227-3 — Proposal classification

`absent | adoptable | foreign`. `adoptable` requires D227-1 and D227-2 for the
requested Amaru revision. A missing record, lock-only diff, record-only diff,
extra path, extra commit, or inconsistent tuple is `foreign`.

## D227-4 — Resolver failure receipt

Existing receipt keys, with values:

- `stage=bootstrap-proposal`;
- `outcome=FAILED`;
- `error=peer-snapshot-resolution-failed`.

The state is terminal for that daily run and implies zero proposal push and PR
creation effects. It does not change cap, claim, or supersede state.
