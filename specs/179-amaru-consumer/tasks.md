# Tasks: Amaru-fed cardano-node consumer (#179)

One `## Slice` section per bisect-safe commit. Items get `[X]` when the
orchestrator accepts the slice (amended into the slice commit with a
`Tasks:` trailer).

## Slice 1 — amaru-consumer service + amaru-only topology, seeded from bootstrap-state

- [X] T001 Create `testnets/cardano_amaru/amaru-consumer-topology.json` with
  localRoots = `[amaru-relay-1.example:3001, amaru-relay-2.example:3001]` only,
  `publicRoots: []`, `useLedgerAfterSlot: 0`.
- [X] T002 Add `amaru-consumer-seed` one-shot to the compose (reuse the
  `amaru-bootstrap-producer` image; copy `bootstrap-state` → `amaru-consumer-state`
  after `bootstrap-producer` completes; `restart: on-failure`; fault-exclude label).
- [X] T003 Add `amaru-consumer` cardano-node service (block producer false; mounts
  p1-configs + the amaru-only topology override + `amaru-consumer-state:/state` +
  tracer; depends on seed completed + both amaru relays started; fault-exclude label);
  add the `amaru-consumer-state` volume.
- [X] T004 Proof: `INTERNAL_NETWORK=false docker compose -f
  testnets/cardano_amaru/docker-compose.yaml config` validates; bring the cluster up
  far enough to confirm seed exits 0, the consumer opens the seeded DB + reaches
  RUNNING, and its only peers are the amaru relays (topology + a peer-selection trace).
  Record the bring-up evidence in `WIP.md`.

## Slice 2 — smoke asserts convergence through amaru (fail-closed) + README

- [X] T005 Extend `scripts/smoke-test.sh` `cardano_amaru` branch: capture the
  consumer's seed tip `N0`, then poll (bounded by `AMARU_CONSUMER_CONVERGE_TIMEOUT`)
  until the consumer tip slot `> N0` AND its tip hash equals a producer tip hash.
- [X] T006 Fail-closed: on timeout/crash/divergence exit non-zero printing the
  consumer tip, the producer tip, and `N0`.
- [X] T007 Update `testnets/cardano_amaru/README.md`: document the consumer, its
  amaru-only topology, the bootstrap-state seed, and the assertion; remove the stale
  "should not require Amaru to serve blocks as a responder" claim.
- [X] T008 Proof: `scripts/smoke-test.sh cardano_amaru` passes because the consumer
  converged (read the output); one-off negative run (break serving) fails with the
  divergence diagnostic. Record both in `WIP.md`.
