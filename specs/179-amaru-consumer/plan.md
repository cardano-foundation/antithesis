# Implementation Plan: Amaru-fed cardano-node consumer + local smoke proof

**Branch**: `feat/amaru-consumer` | **Date**: 2026-06-29 | **Spec**: `spec.md`
**Input**: `specs/179-amaru-consumer/spec.md` (issue #179, epic #182)

## Status

**Completed**: Worktree + spec.md + topology read. Amaru responder/anchor code
audited against pragma-org main-equivalent source — seed decision resolved
(Option A, on protocol-correctness grounds; see "Amaru serving model" below).
**Current**: Plan checkpoint — awaiting green light to start the slice loop.
**Blockers**: None (seed decision resolved).

## Summary

Add one `amaru-consumer` cardano-node to `testnets/cardano_amaru` whose
localRoots are **exactly** the two amaru relays, seed it near amaru's
bootstrap anchor (point N), and extend `scripts/smoke-test.sh cardano_amaru`
to assert — fail-closed — that the consumer's tip advances past N and
matches a producer tip. Any tip growth past N can only come from amaru's
blockfetch-server, so a green smoke is direct evidence amaru serves.

## Technical Context

**Language/Version**: Docker Compose YAML + Bash (smoke) + JSON (topology).
**Primary Dependencies**: existing `cardano-node` digest, existing
`amaru-bootstrap-producer` image, `cardano-cli`, `docker compose`.
**Storage**: a new `amaru-consumer-state` named volume seeded from the
existing `bootstrap-state` volume.
**Testing**: `scripts/smoke-test.sh cardano_amaru`, `docker compose config`.
**Target Platform**: Linux containers under Docker Compose (and later
Antithesis, via #180/#181 — out of scope here).
**Constraints**: amaru = main HEAD, no fork patch (C-002); image-spelling
constraint preserved (FR-008); convergence budget bounded (C-003).
**Scale/Scope**: one new node + one seed init + one topology file + one
smoke assertion + README.

## Constitution Check

- **I. Composer-first**: N/A — this ticket adds no Composer commands; the
  Antithesis property is #180. It touches compose topology + the local
  smoke only.
- **III. Short-running commands**: the smoke assertion is a bounded poll
  loop, not an unbounded wait (C-003).
- **IV. Duration-robust**: convergence budget is parametrised
  (`AMARU_CONSUMER_CONVERGE_TIMEOUT`) so a slow bootstrap doesn't false-fail.
- **VI. Bisect-safe commits**: two vertical slices, each green at HEAD.
- **VII. Image tag hygiene**: no component source changes here, so no image
  bump is required; the consumer reuses already-pinned images. (If a slice
  ends up needing a new helper image, that's a flag back to the operator.)
- **Custom testnet boundaries**: changes are scoped to
  `testnets/cardano_amaru/` + `scripts/smoke-test.sh`; nothing leaks into
  `cardano_node_master`.
- **Composer smoke-tests run locally before every push**: yes — the proof
  *is* the local smoke; both the positive and a one-off negative run are
  recorded in `WIP.md`.

## Amaru serving model (verified against pragma-org main-equivalent code)

Read from `/code/amaru` (fork HEAD); the fork delta vs `upstream/main` on all
of the serving/anchor code below is cosmetic (`build_node.rs` adds one
`.context()` string; `bootstrap.rs` is snapshot-decoder plumbing), so this is
pragma-org main HEAD behaviour.

Amaru **does** implement the n2n responder, as full stages:
- `crates/amaru-protocols/src/chainsync/responder.rs` — `FindIntersect` →
  `store.find_intersect_point(points)`; `RequestNext` → `next_best_chain_header`
  (roll forward / rollback along the best chain).
- `crates/amaru-protocols/src/blockfetch/responder.rs` — `RequestRange{from,
  through}` → walk `through`→`from` over the store and stream stored block
  bodies (`load_block`).

**The anchor governs what amaru can serve:**
- At first init (bootstrap), amaru sets `anchor = ledger-snapshot tip` and
  writes *that point* into its best-chain slot index
  (`build_node.rs:191-199` → `roll_forward_chain` → `CHAIN_PREFIX[slot]=hash`).
  It knows **nothing below the anchor** (`ancestors_on_snapshot` stops at the
  anchor slot, `read_chain_store.rs:315`).
- `find_intersect_point` (`read_chain_store.rs:162`) sorts the client's offered
  points descending and returns the **highest one on amaru's best chain
  `[anchor, tip]`**; if none match it returns **`Point::Origin`**.
- **Failure mode (the operator's exact concern):** a consumer offering only
  points *below* the anchor collapses the intersection to `Origin`; amaru then
  rolls it forward from its lowest indexed block (the anchor), whose parent a
  consumer-at-Origin does not hold → headers don't connect → no sync. **Amaru
  can only serve a peer that intersects at/after its anchor.**

## DECISION — seed source (FR-003): Option A, on correctness grounds

The serving model above resolves the seed choice; it is not merely a
convenience call.

### Option A — seed from `bootstrap-state` (CHOSEN)

`bootstrap-state` is already a **cardano-node ChainDB** at the bootstrap
snapshot: p1's live ChainDB copied (immutable/ledger/volatile/protocolMagicId/
lock) by the bootstrap-producer, the same snapshot the amaru bundle was built
from. A one-shot `amaru-consumer-seed` init (reusing the
`amaru-bootstrap-producer` image — already has `/bin/sh` + coreutils, no new
image) copies `bootstrap-state` → `amaru-consumer-state` after the producer
completes; the consumer `run`s against that DB.

- **Why it's correct, not just cheap:** amaru's anchor = ledger tip ≈ 2 epochs
  behind the immutable tip. The consumer seeded from the *same* snapshot has a
  tip **far above** the anchor on the **same chain**, so its chainsync sample
  always contains a point inside amaru's known range `[anchor, tip]` → clean
  `IntersectFound` at a real shared block → amaru rolls it forward to the live
  tip and streams bodies it fetched live. The consumer already holds the anchor
  block, so it never requests anything ≤ anchor. The "point amaru doesn't know"
  risk is eliminated by construction.
- **Verify in S1:** the copied `bootstrap-state` opens cleanly as the
  consumer's `--database-path` (it is a native node DB, so expected to).

### Option B — seed from the amaru bundle anchor (rejected)

The bundle is in **amaru's format, not a cardano-node ChainDB** — the node
cannot open it; would need an amaru→node DB converter that does not exist.
Buys no correctness over A (A already lands the intersection at a point amaru
knows). Out of proportion for a boundary gate.

### Option C — start from genesis (rejected, protocol reason)

A genesis consumer offers only sub-anchor points + Origin → intersection
collapses to `Origin` → headers don't connect → no sync (see failure mode
above). Not a tuning issue; structurally broken.

### Convergence nuance for the smoke (S2)

While amaru is still catching up to the live tip, the intersection can
temporarily land *below* the consumer's seed tip; the consumer still advances
as amaru advances. The smoke's assertion therefore needs a **bounded
convergence budget** for amaru to reach the live tip and stream the consumer
forward — not an exact-tip check at first contact.

## Project Structure

```text
testnets/cardano_amaru/
├── docker-compose.yaml            # + amaru-consumer, + amaru-consumer-seed, + amaru-consumer-state volume
├── amaru-consumer-topology.json   # NEW — localRoots = [amaru-relay-1, amaru-relay-2] only
└── README.md                      # responder role + consumer + seed + smoke assertion

scripts/
└── smoke-test.sh                  # cardano_amaru branch: consumer convergence assertion (fail-closed)
```

### Concrete shapes (Option A)

`amaru-consumer-topology.json`:
```json
{
  "localRoots": [
    { "accessPoints": [
        {"address": "amaru-relay-1.example", "port": 3001},
        {"address": "amaru-relay-2.example", "port": 3001}
      ],
      "advertise": false, "trustable": true, "valency": 2 }
  ],
  "publicRoots": [],
  "useLedgerAfterSlot": 0
}
```

`amaru-consumer-seed` (one-shot, reuses the amaru image):
```yaml
amaru-consumer-seed:
  image: ghcr.io/lambdasistemi/amaru-bootstrap-producer:03d2727b71e8d1fe7c793d5036dce3c3ce294f6c
  entrypoint: [/bin/sh, -ec]
  command:
    - |
      if [ ! -d /seed/immutable ]; then
        cp -a /bootstrap/. /seed/
      fi
  labels: *fault-exclude
  volumes:
    - bootstrap-state:/bootstrap:ro
    - amaru-consumer-state:/seed
  depends_on:
    bootstrap-producer: { condition: service_completed_successfully }
  restart: on-failure
```

`amaru-consumer` (reuses the relay anchor — producer=false, same `run` command):
```yaml
amaru-consumer:
  <<: *cardano-relay-10-7-1
  container_name: amaru-consumer
  labels: *fault-exclude
  hostname: amaru-consumer.example
  depends_on:
    amaru-consumer-seed: { condition: service_completed_successfully }
    amaru-relay-1: { condition: service_started }
    amaru-relay-2: { condition: service_started }
  volumes:
    - p1-configs:/configs:ro
    - ./amaru-consumer-topology.json:/configs/configs/topology.json:ro
    - amaru-consumer-state:/state
    - tracer:/tracer
```

## Slices (bisect-safe, one commit each)

### Slice 1 — `amaru-consumer` service + amaru-only topology, seeded near N

- Create `amaru-consumer-topology.json` (amaru relays only).
- Add `amaru-consumer-seed`, `amaru-consumer`, and the
  `amaru-consumer-state` volume to the compose.
- **Proof / gate** (no unit harness at this layer): `docker compose -f
  testnets/cardano_amaru/docker-compose.yaml config` validates; bring the
  cluster up far enough to confirm `amaru-consumer-seed` exits 0, the
  consumer opens the seeded DB and reaches RUNNING, and its only peers are
  the amaru relays (topology + peer-selection trace). RED = compose config
  fails / consumer can't open DB before the slice; GREEN = validates + runs.
  The existing `cardano_amaru` smoke still passes (it doesn't yet assert the
  consumer), so HEAD stays green.
- **Independently usable**: the consumer exists and runs; assertion is S2.

### Slice 2 — smoke asserts convergence through amaru (fail-closed) + README

- `scripts/smoke-test.sh` `cardano_amaru` branch: after the relay checks,
  record the consumer's seed tip `N0`, then poll (bounded by
  `AMARU_CONSUMER_CONVERGE_TIMEOUT`, default e.g. 300s) until the consumer
  tip slot `> N0` **and** the consumer tip hash equals a producer tip hash;
  on timeout/crash/divergence, exit non-zero printing consumer tip,
  producer tip, and `N0` (FR-006).
- `README.md`: document the consumer, its amaru-only topology, the seed
  source, and the assertion; delete the stale "should not require Amaru to
  serve blocks as a responder" sentence.
- **Proof / gate**: `scripts/smoke-test.sh cardano_amaru` passes *because*
  the consumer converged (read the output). **Negative check**: once during
  development, break serving (point localRoots at a non-amaru peer or stop
  the amaru relays) and confirm the smoke fails with the divergence
  diagnostic; record both runs in `WIP.md`.

## Risks & open questions

- **R1 (boundary gate, narrowed)**: the *intersection* failure mode is now
  ruled out by code audit (Option A seeds inside amaru's known range). The
  residual risk is **runtime responder correctness** — amaru serving correctly
  while itself syncing under faults, with Conway-only header tagging. If it
  doesn't serve, S2's smoke fails by design — land consumer + failing smoke as
  the reproducer and file upstream (`pragma-org/amaru`). Do **not** relax the
  assertion (C-002).
- **R2 (seeded DB opens)**: confirm in S1 that a copy of `bootstrap-state`
  opens cleanly as the consumer's `--database-path` (Option A assumption).
- **R6 (image provenance)**: the deployed amaru image is the lambdasistemi
  fork; the fork delta on serving/anchor code is nil, but epic #182's
  "pragma-org main HEAD, no fork patch" invariant should be reconciled at the
  *image* level (which amaru commit the bootstrap-producer image bundles) — a
  separate check, doesn't change the serving model. Flag to operator.
- **R3 (cardano-node image shell)**: the seed-copy is done by a separate
  one-shot using the amaru image (known to have `/bin/sh`), so we do **not**
  depend on the cardano-node image having a shell.
- **R4 (convergence budget)**: amaru must first catch up to the producer tip
  before it can serve the consumer that far; the bounded poll must allow
  bootstrap + amaru catch-up + consumer catch-up. Parametrised; tune in S2.
- **R5 (image policy)**: no new image is introduced (reuses two
  already-pinned images), so Antithesis image validation is unaffected.

## Test strategy

- No unit/golden harness exists for compose topology — the proof is the
  local smoke (positive) + a one-off negative run, per the
  live-boundary-smoke pattern. Recorded in `WIP.md`, not just asserted.
