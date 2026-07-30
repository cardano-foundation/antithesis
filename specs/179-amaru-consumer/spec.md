# Feature Specification: Amaru-fed cardano-node consumer + local smoke proof

**Feature Branch**: `feat/amaru-consumer`
**Created**: 2026-06-29
**Status**: Draft
**Input**: GitHub issue #179 (parent epic #182)

## Context

Today the `cardano_amaru` testnet runs amaru as a **leaf consumer**: each
amaru relay chainsync-pulls from a cardano-node relay (`amaru-relay-1` →
`relay1`, `amaru-relay-2` → `relay2`) and listens on `0.0.0.0:3001`, but
**nothing connects to those listen addresses**. Amaru's chainsync-server +
blockfetch-server (responder) path — which `pragma-org/amaru` main HEAD
implements — is never exercised. The current README even states this stack
"should not require Amaru to serve blocks as a responder."

This ticket is the **boundary gate** of epic #182: add one downstream
cardano-node whose only upstream is amaru and prove, locally, that it
follows the chain *through amaru*. If amaru does not actually serve, the
smoke must fail closed and the finding is filed upstream.

## User Scenarios & Testing

### User Story 1 — Consumer follows the chain through amaru (Priority: P1)

As a tester, I run the `cardano_amaru` cluster with an amaru-fed
cardano-node consumer and observe its tip track the producers — served
entirely by amaru.

**Why this priority**: This is the entire point of the epic. Without a
peer that pulls from amaru, amaru's responder path stays dark and the epic
cannot proceed. #179 is the gate: if amaru does not serve, #180 and #181
are moot.

**Independent Test**: Run `scripts/smoke-test.sh cardano_amaru`; observe
the `amaru-consumer` node advance past amaru's bootstrap anchor and reach
the producers' tip, having no peer other than `amaru-relay-1` and
`amaru-relay-2`.

**Acceptance Scenarios**:

1. **Given** the cluster is up and amaru has bootstrapped, **When**
   `amaru-consumer` starts with a topology whose localRoots are exactly
   `[amaru-relay-1, amaru-relay-2]`, **Then** it establishes chainsync +
   blockfetch with the amaru relays and no other peer.
2. **Given** `amaru-consumer` is seeded near amaru's bootstrap anchor
   (point N), **When** the producers extend the chain and amaru relays it,
   **Then** the consumer's tip advances strictly past N and converges to
   the producers' tip.
3. **Given** amaru does **not** serve (responder path broken, anchor
   mismatch, or no block forwarded), **When** the smoke's convergence
   window elapses, **Then** the smoke **fails** with a diagnostic naming
   the consumer's last tip and the producers' tip — it must not pass by
   omission.

### User Story 2 — Honest local proof, fail-closed (Priority: P1)

As a maintainer, I need the `cardano_amaru` smoke to prove serving rather
than mere liveness, so a green local run is real evidence that amaru's
responder path works.

**Why this priority**: The existing `cardano_amaru` smoke only checks that
the relays stay *running* — it never checks that anything is *served*. A
consumer that silently sticks at its seed point, or that is fed by a
non-amaru peer, would be a false green.

**Independent Test**: Temporarily break amaru's serving (e.g. point the
consumer's localRoots at a non-amaru peer, or stop the amaru relays) and
confirm the smoke fails with the divergence diagnostic rather than passing.

**Acceptance Scenarios**:

1. **Given** the consumer never advances past its seed point within the
   convergence budget, **When** the smoke's assertion runs, **Then** it
   exits non-zero and prints the consumer tip, the producer tip, and the
   anchor N.
2. **Given** the consumer reaches a tip at/after N that equals a producer
   tip, **When** the assertion runs, **Then** it exits zero and prints the
   matched slot/hash.

### User Story 3 — Documentation reflects the new responder role (Priority: P2)

As a future reader of `testnets/cardano_amaru/README.md`, I need the docs
to state that this stack now exercises amaru as an n2n responder, so the
stale "should not require Amaru to serve blocks as a responder" claim does
not mislead.

**Why this priority**: The README is the entry point for anyone touching
this testnet; leaving the old claim makes the consumer look accidental.

**Independent Test**: Read the README and confirm it describes the
`amaru-consumer` service, its amaru-only topology, its seed source, and the
smoke assertion.

## Requirements

### Functional Requirements

- **FR-001**: `testnets/cardano_amaru` MUST define an `amaru-consumer`
  cardano-node service (block production disabled, no stake/KES/VRF/opcert
  material).
- **FR-002**: `amaru-consumer`'s topology MUST set `localRoots` to exactly
  the two amaru relays (`amaru-relay-1.example:3001`,
  `amaru-relay-2.example:3001`), `publicRoots: []`, and MUST NOT reference
  any producer or cardano-node relay. This is what isolates amaru's serving.
- **FR-003**: `amaru-consumer` MUST be seeded near amaru's bootstrap anchor
  (point N) so amaru can serve its range; a consumer started from genesis
  is out of amaru's served range and is not acceptable. (Seed source chosen
  in plan.md.)
- **FR-004**: `amaru-consumer` MUST start only after amaru has bootstrapped
  (depends on the bootstrap-producer completing and the amaru relays
  running), mirroring the existing relay dependency wiring.
- **FR-005**: `scripts/smoke-test.sh cardano_amaru` MUST assert that
  `amaru-consumer`'s tip advances strictly past N AND matches a producer
  tip, within a bounded convergence budget.
- **FR-006**: The smoke MUST fail closed: any outcome other than
  "advanced past N and matched a producer tip" (stuck at seed, crash,
  timeout, divergence) exits non-zero with a diagnostic naming the
  consumer tip, the producer tip, and N.
- **FR-007**: The fault-exclusion posture of the new service MUST match the
  rest of the non-SUT cluster (the consumer is a witness, not part of
  amaru, so it carries the same `com.antithesis.exclude_from_faults` label
  as the other cardano-node services). Antithesis assertions/fault scoping
  for the consumer are explicitly out of scope (children #180/#181).
- **FR-008**: `docker compose -f testnets/cardano_amaru/docker-compose.yaml
  config` MUST validate with the consumer added, and the image-spelling
  constraint (digest-only, no `tag@digest`) MUST be preserved.
- **FR-009**: `testnets/cardano_amaru/README.md` MUST be updated to
  describe the consumer, its amaru-only topology, its seed source, and the
  smoke assertion, and MUST remove the stale "should not require Amaru to
  serve blocks as a responder" claim.

### Non-Functional / Constraints

- **C-001**: cardano-node image stays pinned to the existing digest; no
  release-target change.
- **C-002**: amaru = literal `pragma-org/amaru` main HEAD image already in
  the compose; no fork patch, no amaru flag changes to make serving work.
  If serving requires an amaru change, that is the finding — file upstream,
  do not patch locally.
- **C-003**: The smoke's convergence budget MUST stay within the bounds the
  existing `cardano_amaru` smoke already tolerates (bootstrap can take up to
  ~1500s); the new assertion adds a bounded window on top, not an unbounded
  wait.

## Success Criteria

- `scripts/smoke-test.sh cardano_amaru` passes locally **because** the
  amaru-fed consumer advanced past N to a producer tip — verified by
  reading the smoke output, not by exit code alone.
- Forcing amaru to not serve makes the same smoke fail with the divergence
  diagnostic (negative check performed at least once during development and
  noted in `WIP.md`).
- The consumer has no non-amaru peer (verified from the topology file and,
  if practical, from the consumer's peer-selection traces).

## Out of Scope (this ticket)

- Antithesis assertions / fault injection for the consumer (#180, #181).
- amaru stake or block production (the consumer carries no stake).
- amaru→amaru relay chains / producer-pulls-from-amaru (epic non-goal).
- amaru's own-tip observability (cna#168).

## Boundary-gate clause

If, after a faithful seed + amaru-only topology, the consumer cannot follow
the chain through amaru, the conclusion is **amaru does not serve** — this
PR then lands the consumer + the (failing) smoke as the reproducer, and a
finding is filed against `pragma-org/amaru`. We do not paper over it by
relaxing the assertion or feeding the consumer from a non-amaru peer.
