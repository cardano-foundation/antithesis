# Cardano Amaru Testnet

This testnet extends the `cardano_node_master` shape with an Amaru
bootstrap path:

- three `cardano-node` block producers pinned to the official
  `10.7.1-amd64` image digest;
- two relays, also pinned to the same node release;
- the published `amaru-bootstrap-producer` image from
  `lambdasistemi/amaru-bootstrap`;
- two relay-only Amaru nodes whose entrypoints wait until the producer
  has committed a complete `testnet_42` bootstrap bundle.

Amaru is not assigned stake in this testnet. The only stake-bearing block
producers are the three cardano-node services `p1`, `p2`, and `p3`.
`amaru-relay-1` and `amaru-relay-2` receive no KES key, VRF key, cold
key, operational certificate, or stake-pool genesis assignment.

This testnet uses a fast bootstrap profile:

```yaml
protocolConsts:
  k: 10
epochLength: 120
securityParam: 10
activeSlotsCoeff: 0.2
TestConwayHardForkAtEpoch: 0
```

The producer requires two complete Conway epochs behind the immutable
tip. These values make that proof bounded for local and CI runs without
changing the cardano-node release target or giving Amaru producer
credentials. Dense block production is part of the profile because the
producer reads immutable chunks only; sparse block production can leave
the immutable tip at genesis for too long.

The Amaru relay containers are intentionally quiet for Antithesis log
ingestion: compose sets `AMARU_LOG=warn`, `AMARU_TRACE=warn`, and
`AMARU_COLOR=never`, and the wrapper loops do not print polling
heartbeats. The bootstrap producer stores per-attempt logs under
`/srv/amaru/.logs` in the bundle volume and prints only the final commit
line or a bounded tail for a non-retryable failure.

The producer image is pinned by full source commit SHA:

```text
ghcr.io/lambdasistemi/amaru-bootstrap-producer:pr-32-ad64e76778b0408ec66f353c7e58c8a1e7d4045f
```

The cardano-node release image is pinned in Compose by digest only:

```text
ghcr.io/intersectmbo/cardano-node@sha256:3275d357053d21f3220f74b0854fd584e1fe322dfa1bbb78effd760c3191d14c
```

That digest is the manifest digest for the upstream
`ghcr.io/intersectmbo/cardano-node:10.7.1-amd64` tag. Compose must not
use the Docker-valid `repo:tag@sha256:digest` spelling here because the
Antithesis image parameter validator accepts image names by tag or by
digest, but rejects the combined tag-plus-digest form before the cluster
is built.

The generic observability and assertion services remain enabled:
`tracer`, `tracer-sidecar`, `log-tailer`, and `sidecar`. The
transaction perturbator workload is deliberately absent; this testnet has
no `tx-generator` service.

## Runtime Flow

```text
configurator -> p1/p2/p3/relay1/relay2
                  |
                  v
             p1 ChainDB
                  |
                  v
      bootstrap-producer refresh loop
                  |
                  v
          bootstrap ChainDB copy
                  |
                  v
           amaru-bundle volume
             |             |
             v             v
      amaru-relay-1   amaru-relay-2
              \           /
               \         /
                v       v
             amaru-consumer
```

`bootstrap-producer` owns the snapshot-refresh loop. It mounts `p1`'s
live ChainDB read-only at `/live`, copies it into the isolated
`bootstrap-state` volume, then mounts that copy read-write at
`/cardano/state` for the upstream producer command. This preserves the
cardano-node 10.7.1 consensus API requirement that immutable chunk
validation has write permissions, while avoiding writes to the live `p1`
ChainDB during Antithesis fault scheduling. Retryable readiness and copy
failures use a short per-attempt deadline and refresh the snapshot inside
the same container instead of exiting non-zero. Expected `cp` races
against the live ledger directory are kept in the Amaru bundle logs, not
container stdout.

Each relay-only Amaru entrypoint copies the final bundle into its private
state volume before it execs `amaru run`, so the two Amaru nodes do not
share writable chain or ledger stores. The relays peer directly with
cardano-node producers (`amaru-relay-1` to `p1`, `amaru-relay-2` to
`p2`) and also serve the isolated `amaru-consumer` path described below.

## Amaru Consumer Path

`amaru-consumer` is a cardano-node relay that starts from the Amaru
bootstrap seed and then must catch up through Amaru. Its topology is
`amaru-consumer-topology.json`, whose only local roots are
`amaru-relay-1.example` and `amaru-relay-2.example`; it has no public
roots and no direct producer or cardano-node relay peers.

`amaru-consumer-seed` copies the `bootstrap-state` volume into
`amaru-consumer-state` after `bootstrap-producer` exits successfully.
`amaru-consumer` mounts that seeded state as its ChainDB, but it is
attached only to `amaru-consumer-net`. The two Amaru relays are attached
to both the producer network and `amaru-consumer-net`, so they are the
only route by which the consumer can advance past its seed point.

For `cardano_amaru`, the smoke captures the consumer's first readable tip
as `N0`, then fails unless the consumer advances to a slot greater than
`N0` and its tip hash matches `p1`. On timeout, crash, restart, or
divergence, the smoke prints the consumer tip, the `p1` tip, `N0`, and a
tail of the `amaru-consumer` logs before exiting non-zero.

Each relay also writes a startup marker into the shared `amaru-startup`
volume immediately before the `amaru run` exec. The sidecar mounts that
volume, and its image contains the Amaru startup proof scripts in the
existing `convergence` Test Composer template so Antithesis can score
`parallel_driver_amaru_started.sh` and `finally_amaru_started.sh` as
explicit properties instead of asking readers to infer startup from
container background-monitor logs. In this profile the sidecar also
waits for those markers before emitting Antithesis setup-complete, so
fault injection starts only after Amaru has consumed the bootstrap bundle
at least once.

## Local Commands

Validate the Compose model:

```bash
INTERNAL_NETWORK=false docker compose -f testnets/cardano_amaru/docker-compose.yaml config
```

Run the standard node smoke test:

```bash
./scripts/smoke-test.sh cardano_amaru 600
```

The standard smoke test proves the cardano-node network and sidecar
convergence checks still start. Because this profile has no
`tx-generator`, the generic tx-generator smoke gate is skipped. For
`cardano_amaru`, the smoke waits for `bootstrap-producer` to complete,
checks that both relay-only Amaru nodes copied the bundle into private
state and stayed running after `amaru run` opened the stores, then proves
`amaru-consumer` advanced past its seeded tip and converged to a producer
tip through the Amaru-only topology.

For the bootstrap-specific proof, inspect:

```bash
docker compose -f testnets/cardano_amaru/docker-compose.yaml logs -f bootstrap-producer
docker compose -f testnets/cardano_amaru/docker-compose.yaml ps bootstrap-producer amaru-relay-1 amaru-relay-2
```

Expected completion sequence:

1. `bootstrap-producer` prints `wrote /srv/amaru/testnet_42` and exits
   `0`.
2. `amaru-relay-1` and `amaru-relay-2` copy the bundle into their private state
   volumes.
3. `amaru-relay-1` and `amaru-relay-2` start with `amaru run` and stay
   running without a restart during the smoke gate.
4. The sidecar setup signal is delayed until both relay startup markers
   exist.
5. `parallel_driver_amaru_started.sh` emits `amaru_relays_started` when
   it samples both relay startup markers; `finally_amaru_started.sh`
   fails the run if those markers are still missing at the final check.
   Both commands run from the `convergence` template so Antithesis does
   not mix separate test directories in one sidecar.
6. The sidecar uses a larger post-fault convergence budget in this
   profile (`30s` settle, `15` attempts, `3s` delay) so a final check is
   not scored while producer tips are still catching up after faults
   stop.

## Compatibility Constraint

This stack intentionally targets cardano-node 10.7.1. The Amaru
bootstrap CBOR projection is release-sensitive, so a green compile
against a different ledger dependency set is not evidence that the
runtime bytes are compatible with this cluster.
