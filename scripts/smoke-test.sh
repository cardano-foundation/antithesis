#!/usr/bin/env bash

# Smoke test: verify the testnet compose starts and nodes respond to queries.
# Uses cardano-cli ping to prove each node is serving the Ouroboros protocol.
#
# Usage: scripts/smoke-test.sh [testnet] [timeout_seconds]
set -euo pipefail

TESTNET="${1:-cardano_node_master}"
TIMEOUT="${2:-120}"
COMPOSE_FILE="testnets/${TESTNET}/docker-compose.yaml"
MAGIC=42

export INTERNAL_NETWORK=true

cleanup() {
  echo "Tearing down..."
  docker compose --progress quiet -f "$COMPOSE_FILE" down --volumes --remove-orphans 2>/dev/null || true
}
trap cleanup EXIT

echo "Starting testnet ${TESTNET}..."
docker compose --progress quiet -f "$COMPOSE_FILE" up -d

POOLS=$(awk '/poolCount: /{ print $2 }' "testnets/${TESTNET}/testnet.yaml")
DEADLINE=$((SECONDS + TIMEOUT))

echo "Waiting for ${POOLS} nodes to respond to cardano-cli ping (timeout ${TIMEOUT}s)..."

for i in $(seq 1 "$POOLS"); do
  NODE="p${i}"
  while true; do
    if [ "$SECONDS" -ge "$DEADLINE" ]; then
      echo "FAIL: timed out waiting for ${NODE}"
      docker compose -f "$COMPOSE_FILE" logs --tail 20 "$NODE" 2>&1
      exit 1
    fi

    # Check the node did not terminate. Compose may briefly report created or
    # restarting while dependencies settle, so only terminal states fail.
    # Use `docker compose ps` to resolve the service to its actual container
    # name — testnets that allow multi-project coexistence on a shared host
    # don't pin `container_name:`, so the container is project-prefixed.
    STATE="$(docker compose -f "$COMPOSE_FILE" ps --format '{{.State}}' "$NODE" 2>/dev/null | head -1)"
    if [ "$STATE" = "exited" ] || [ "$STATE" = "dead" ]; then
      echo "FAIL: ${NODE} crashed"
      docker compose -f "$COMPOSE_FILE" logs --tail 30 "$NODE" 2>&1
      exit 1
    fi

    # Query the node tip via cardano-cli ping. `docker compose exec`
    # resolves the service name regardless of container_name.
    if TIP=$(docker compose -f "$COMPOSE_FILE" exec -T "$NODE" \
        cardano-cli ping --magic "$MAGIC" --host 127.0.0.1 --port 3001 \
        --tip --quiet -c1 2>/dev/null); then
      echo "OK: ${NODE} — ${TIP}"
      break
    fi

    sleep 5
  done
done

# Convergence is now measured continuously by tracer-sidecar's
# fork-tree probe (#119) — no shell-level eventually_converged.sh
# check needed here.  The cardano-cli ping above already proves
# each producer is alive and serving the chain; tracer-sidecar's
# Always assertion enforces the cluster-wide unrecoverable-divergence
# bound at runtime.

# cardano_amaru: prove the amaru bootstrap pipeline. bootstrap-producer
# builds the bundle (create-snapshots + bootstrap) and exits 0; the two
# relay-only amaru nodes then consume it, exec `amaru run`, and stay up.
if [[ "$TESTNET" == cardano_amaru* ]]; then
  BOOTSTRAP_TIMEOUT="${AMARU_BOOTSTRAP_SMOKE_TIMEOUT:-1500}"
  AMARU_CONSUMER_TIMEOUT="${AMARU_CONSUMER_CONVERGE_TIMEOUT:-300}"

  inspect_status() {
    docker inspect -f '{{.State.Status}}' "$1" 2>/dev/null || true
  }

  inspect_exit_code() {
    docker inspect -f '{{.State.ExitCode}}' "$1" 2>/dev/null || echo -1
  }

  inspect_restart_count() {
    docker inspect -f '{{.RestartCount}}' "$1" 2>/dev/null || echo 0
  }

  query_tip() {
    docker compose -f "$COMPOSE_FILE" exec -T "$1" \
      cardano-cli query tip --testnet-magic "$MAGIC" --socket-path /state/node.socket
  }

  tip_block() {
    printf '%s\n' "$1" | sed -nE 's/.*"block"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' | head -1
  }

  tip_slot() {
    printf '%s\n' "$1" | sed -nE 's/.*"slot"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' | head -1
  }

  tip_hash() {
    printf '%s\n' "$1" | sed -nE 's/.*"hash"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -1
  }

  tip_summary() {
    local TIP_JSON="$1"
    local BLOCK SLOT HASH
    BLOCK="$(tip_block "$TIP_JSON")"
    SLOT="$(tip_slot "$TIP_JSON")"
    HASH="$(tip_hash "$TIP_JSON")"
    printf 'block=%s slot=%s hash=%s' "${BLOCK:-unknown}" "${SLOT:-unknown}" "${HASH:-unknown}"
  }

  print_tip_diagnostic() {
    local LABEL="$1"
    local SERVICE="$2"
    local TIP_JSON
    if TIP_JSON="$(query_tip "$SERVICE" 2>/dev/null)"; then
      echo "${LABEL} tip: $(tip_summary "$TIP_JSON")"
    else
      echo "${LABEL} tip: unavailable"
    fi
  }

  N0_SUMMARY="unavailable"
  fail_amaru_consumer() {
    local REASON="$1"
    echo "FAIL: ${REASON}"
    print_tip_diagnostic "amaru-consumer" amaru-consumer
    print_tip_diagnostic "p1" p1
    echo "N0: ${N0_SUMMARY}"
    docker compose -f "$COMPOSE_FILE" logs --tail 60 amaru-consumer 2>&1 || true
    exit 1
  }

  echo "Waiting for bootstrap-producer to build the bundle (timeout ${BOOTSTRAP_TIMEOUT}s)..."
  BP_DEADLINE=$((SECONDS + BOOTSTRAP_TIMEOUT))
  while true; do
    BP_STATE="$(docker inspect -f '{{.State.Status}}' bootstrap-producer 2>/dev/null || true)"
    BP_EXIT="$(docker inspect -f '{{.State.ExitCode}}' bootstrap-producer 2>/dev/null || echo -1)"
    if [ "$BP_STATE" = "exited" ] && [ "$BP_EXIT" = "0" ]; then
      echo "OK: bootstrap-producer built the bundle (exit 0)"; break
    fi
    if [ "$BP_STATE" = "exited" ] && [ "$BP_EXIT" != "0" ]; then
      echo "FAIL: bootstrap-producer exited ${BP_EXIT}"
      docker compose -f "$COMPOSE_FILE" logs --tail 60 bootstrap-producer 2>&1; exit 1
    fi
    if [ "$SECONDS" -ge "$BP_DEADLINE" ]; then
      echo "FAIL: bootstrap-producer did not finish within ${BOOTSTRAP_TIMEOUT}s (state=${BP_STATE})"
      docker compose -f "$COMPOSE_FILE" logs --tail 60 bootstrap-producer 2>&1; exit 1
    fi
    sleep 10
  done
  for RELAY in amaru-relay-1 amaru-relay-2; do
    echo "Waiting for ${RELAY} to consume the bundle and run amaru..."
    R_DEADLINE=$((SECONDS + 180))
    while [ "$(docker inspect -f '{{.State.Status}}' "$RELAY" 2>/dev/null || true)" != "running" ]; do
      if [ "$SECONDS" -ge "$R_DEADLINE" ]; then
        echo "FAIL: ${RELAY} not running after bootstrap"
        docker compose -f "$COMPOSE_FILE" logs --tail 60 "$RELAY" 2>&1; exit 1
      fi
      sleep 5
    done
    RB="$(docker inspect -f '{{.RestartCount}}' "$RELAY")"; sleep 20
    RA="$(docker inspect -f '{{.RestartCount}}' "$RELAY" 2>/dev/null || echo x)"
    if [ "$(docker inspect -f '{{.State.Status}}' "$RELAY" 2>/dev/null)" != "running" ] || [ "$RB" != "$RA" ]; then
      echo "FAIL: ${RELAY} did not stay running (restarts ${RB}->${RA})"
      docker compose -f "$COMPOSE_FILE" logs --tail 60 "$RELAY" 2>&1; exit 1
    fi
    echo "OK: ${RELAY} consumed bundle and stayed running"
  done

  echo "Waiting for amaru-consumer-seed to seed the consumer state (timeout ${AMARU_CONSUMER_TIMEOUT}s)..."
  SEED_DEADLINE=$((SECONDS + AMARU_CONSUMER_TIMEOUT))
  while true; do
    SEED_STATE="$(inspect_status amaru-consumer-seed)"
    SEED_EXIT="$(inspect_exit_code amaru-consumer-seed)"
    if [ "$SEED_STATE" = "exited" ] && [ "$SEED_EXIT" = "0" ]; then
      echo "OK: amaru-consumer-seed seeded the consumer state (exit 0)"
      break
    fi
    if [ "$SEED_STATE" = "exited" ] && [ "$SEED_EXIT" != "0" ]; then
      echo "FAIL: amaru-consumer-seed exited ${SEED_EXIT}"
      docker compose -f "$COMPOSE_FILE" logs --tail 60 amaru-consumer-seed 2>&1 || true
      fail_amaru_consumer "amaru-consumer-seed failed before consumer convergence"
    fi
    if [ "$SECONDS" -ge "$SEED_DEADLINE" ]; then
      echo "FAIL: amaru-consumer-seed did not finish within ${AMARU_CONSUMER_TIMEOUT}s (state=${SEED_STATE})"
      docker compose -f "$COMPOSE_FILE" logs --tail 60 amaru-consumer-seed 2>&1 || true
      fail_amaru_consumer "amaru-consumer-seed timed out before consumer convergence"
    fi
    sleep 5
  done

  echo "Waiting for amaru-consumer to run (timeout ${AMARU_CONSUMER_TIMEOUT}s)..."
  CONSUMER_READY_DEADLINE=$((SECONDS + AMARU_CONSUMER_TIMEOUT))
  CONSUMER_RESTARTS="unknown"
  while true; do
    CONSUMER_STATE="$(inspect_status amaru-consumer)"
    CONSUMER_RESTARTS_NOW="$(inspect_restart_count amaru-consumer)"
    if [ "$CONSUMER_RESTARTS_NOW" != "0" ]; then
      fail_amaru_consumer "amaru-consumer restarted before readiness (restarts=${CONSUMER_RESTARTS_NOW})"
    fi
    if [ "$CONSUMER_STATE" = "running" ]; then
      CONSUMER_RESTARTS="$CONSUMER_RESTARTS_NOW"
      echo "OK: amaru-consumer running (restarts=${CONSUMER_RESTARTS})"
      break
    fi
    if [ "$CONSUMER_STATE" = "exited" ] || [ "$CONSUMER_STATE" = "dead" ]; then
      fail_amaru_consumer "amaru-consumer crashed before readiness (state=${CONSUMER_STATE})"
    fi
    if [ "$SECONDS" -ge "$CONSUMER_READY_DEADLINE" ]; then
      fail_amaru_consumer "amaru-consumer did not run within ${AMARU_CONSUMER_TIMEOUT}s (state=${CONSUMER_STATE})"
    fi
    sleep 5
  done

  echo "Reading amaru-consumer seed tip..."
  N0_DEADLINE=$((SECONDS + AMARU_CONSUMER_TIMEOUT))
  N0_SLOT="unknown"
  while true; do
    CONSUMER_STATE="$(inspect_status amaru-consumer)"
    if [ "$CONSUMER_STATE" != "running" ]; then
      fail_amaru_consumer "amaru-consumer stopped before seed tip capture (state=${CONSUMER_STATE})"
    fi
    CONSUMER_RESTARTS_NOW="$(inspect_restart_count amaru-consumer)"
    if [ "$CONSUMER_RESTARTS_NOW" != "$CONSUMER_RESTARTS" ]; then
      fail_amaru_consumer "amaru-consumer restarted before seed tip capture (restarts ${CONSUMER_RESTARTS}->${CONSUMER_RESTARTS_NOW})"
    fi
    if N0_TIP="$(query_tip amaru-consumer 2>/dev/null)"; then
      N0_SLOT="$(tip_slot "$N0_TIP")"
      N0_HASH="$(tip_hash "$N0_TIP")"
      if [[ "$N0_SLOT" =~ ^[0-9]+$ ]] && [ -n "$N0_HASH" ]; then
        N0_SUMMARY="$(tip_summary "$N0_TIP")"
        echo "OK: amaru-consumer seed tip ${N0_SUMMARY}"
        break
      fi
    fi
    if [ "$SECONDS" -ge "$N0_DEADLINE" ]; then
      fail_amaru_consumer "could not read amaru-consumer seed tip within ${AMARU_CONSUMER_TIMEOUT}s"
    fi
    sleep 5
  done

  echo "Waiting for amaru-consumer to advance past seed and match p1 (timeout ${AMARU_CONSUMER_TIMEOUT}s)..."
  CONVERGE_DEADLINE=$((SECONDS + AMARU_CONSUMER_TIMEOUT))
  while true; do
    CONSUMER_STATE="$(inspect_status amaru-consumer)"
    if [ "$CONSUMER_STATE" != "running" ]; then
      fail_amaru_consumer "amaru-consumer stopped during convergence (state=${CONSUMER_STATE})"
    fi
    CONSUMER_RESTARTS_NOW="$(inspect_restart_count amaru-consumer)"
    if [ "$CONSUMER_RESTARTS_NOW" != "$CONSUMER_RESTARTS" ]; then
      fail_amaru_consumer "amaru-consumer restarted during convergence (restarts ${CONSUMER_RESTARTS}->${CONSUMER_RESTARTS_NOW})"
    fi
    if P1_TIP="$(query_tip p1 2>/dev/null)" && CONSUMER_TIP="$(query_tip amaru-consumer 2>/dev/null)"; then
      CONSUMER_SLOT="$(tip_slot "$CONSUMER_TIP")"
      CONSUMER_HASH="$(tip_hash "$CONSUMER_TIP")"
      P1_HASH="$(tip_hash "$P1_TIP")"
      if [[ "$CONSUMER_SLOT" =~ ^[0-9]+$ ]] && [ -n "$CONSUMER_HASH" ] && [ -n "$P1_HASH" ]; then
        if [ "$CONSUMER_SLOT" -gt "$N0_SLOT" ] && [ "$CONSUMER_HASH" = "$P1_HASH" ]; then
          echo "OK: amaru-consumer converged via amaru — tip slot=${CONSUMER_SLOT} hash=${CONSUMER_HASH} matches p1"
          break
        fi
      fi
    fi
    if [ "$SECONDS" -ge "$CONVERGE_DEADLINE" ]; then
      fail_amaru_consumer "amaru-consumer did not advance past N0 and match p1 within ${AMARU_CONSUMER_TIMEOUT}s"
    fi
    sleep 5
  done
  echo "PASS: cardano_amaru bootstrap + relays + amaru-consumer convergence"
  exit 0
fi

# Adversary probe: if the testnet has the adversary container, exec
# its driver once to prove the binary runs, the chainpoints file is
# reachable, and exit code is zero. Antithesis composer dispatches
# this same script at much higher rate during a real run.
if docker compose -f "$COMPOSE_FILE" config --services | grep -qx adversary; then
  echo "Probing adversary driver..."
  if ! docker compose -f "$COMPOSE_FILE" exec -T adversary \
       /opt/antithesis/test/v1/chain-sync-client/parallel_driver_flap.sh; then
    echo "FAIL: adversary parallel_driver_flap.sh returned non-zero"
    docker compose -f "$COMPOSE_FILE" logs --tail 30 adversary 2>&1
    exit 1
  fi
  echo "OK: adversary driver"
fi

# tx-generator probes are conditional on the service being present in
# the resolved compose. The service is parked in some testnets (see
# tx-generator.disabled.yaml) — when it isn't part of the running
# cluster we skip the probes rather than fail the smoke test.
if ! docker compose -f "$COMPOSE_FILE" config --services | grep -qx tx-generator; then
  echo "SKIP: tx-generator not in compose for testnet ${TESTNET}, skipping tx-generator probes"
  echo "PASS: all ${POOLS} nodes responding"
  exit 0
fi

# tx-generator: prove the daemon comes up, drives one
# refill, lets the indexer observe it, then lands a small
# burst of transacts and grows the population. This is the
# CI-side counterpart of the docker-compose contract; the
# Antithesis composer drives the same scripts at much
# heavier load on the cluster.
TXGEN_SOCK=/state/tx-generator-control.sock
txgen_send() {
  docker exec tx-generator sh -c \
    "echo '$1' | nc -U -q 1 $TXGEN_SOCK"
}

echo "Waiting for tx-generator control socket..."
TXGEN_DEADLINE=$((SECONDS + 90))
while ! docker exec tx-generator test -S "$TXGEN_SOCK" 2>/dev/null; do
  if [ "$SECONDS" -ge "$TXGEN_DEADLINE" ]; then
    echo "FAIL: tx-generator control socket never bound"
    docker compose -f "$COMPOSE_FILE" logs --tail 50 tx-generator 2>&1
    exit 1
  fi
  sleep 2
done

echo "Probing tx-generator ready..."
TXGEN_DEADLINE=$((SECONDS + 180))
while true; do
  if [ "$SECONDS" -ge "$TXGEN_DEADLINE" ]; then
    echo "FAIL: tx-generator never reported ready=true"
    docker compose -f "$COMPOSE_FILE" logs --tail 50 tx-generator 2>&1
    exit 1
  fi
  RSP="$(txgen_send '{"ready":null}' 2>/dev/null || true)"
  if [ -n "$RSP" ] && echo "$RSP" | jq -e '.ready == true' >/dev/null 2>&1; then
    echo "OK: tx-generator ready"
    break
  fi
  sleep 3
done

echo "Driving initial refill..."
if ! docker exec tx-generator parallel_driver_refill; then
  echo "FAIL: parallel_driver_refill returned non-zero"
  docker compose -f "$COMPOSE_FILE" logs --tail 50 tx-generator 2>&1
  exit 1
fi

echo "Waiting for indexer to observe refill UTxO (p50_lovelace != null)..."
# populationSize is the count of HD-derived addresses
# (incremented by refill on disk before the UTxO lands).
# p50_lovelace is null until the indexer actually sees a
# UTxO on chain, so it's the right gate for "ready to
# transact".
TXGEN_DEADLINE=$((SECONDS + 180))
while true; do
  if [ "$SECONDS" -ge "$TXGEN_DEADLINE" ]; then
    echo "FAIL: indexer never observed refill UTxO"
    txgen_send '{"snapshot":null}' || true
    exit 1
  fi
  SNAP="$(txgen_send '{"snapshot":null}' 2>/dev/null || true)"
  P50="$(echo "$SNAP" | jq -r '.p50_lovelace' 2>/dev/null || echo null)"
  if [ "$P50" != "null" ] && [ -n "$P50" ]; then
    echo "OK: indexer observed UTxO (p50_lovelace=$P50)"
    break
  fi
  sleep 3
done

echo "Driving 5 transacts..."
TXGEN_OK=0
TXGEN_TMP="$(mktemp -d)"
trap 'rm -rf "$TXGEN_TMP"; cleanup' EXIT
for i in 1 2 3 4 5; do
  STDERR="$TXGEN_TMP/transact-$i.err"
  if docker exec tx-generator parallel_driver_transact 2>"$STDERR"; then
    TXGEN_OK=$((TXGEN_OK + 1))
  fi
  # The composer-side semantics treat exit 1 as
  # "not applicable, retry next tick", so we don't fail
  # the smoke-test on a non-zero exit. But a `jq:` line
  # on stderr means the driver itself crashed (malformed
  # JSON, missing field, etc.) — that's a real bug and
  # the smoke-test must surface it.
  if grep -q '^jq:' "$STDERR"; then
    echo "FAIL: parallel_driver_transact emitted jq error on transact #$i:"
    cat "$STDERR"
    exit 1
  fi
  sleep 2
done

echo "Final tx-generator snapshot:"
SNAP="$(txgen_send '{"snapshot":null}')"
echo "$SNAP" | jq .

POP="$(echo "$SNAP" | jq -r '.populationSize // 0')"
if [ "$TXGEN_OK" -lt 1 ]; then
  echo "FAIL: no transacts landed"
  exit 1
fi
if [ "$POP" -lt 2 ]; then
  echo "FAIL: populationSize did not grow past refill ($POP < 2)"
  exit 1
fi

echo "OK: tx-generator drove $TXGEN_OK/5 transacts, populationSize=$POP"

echo "PASS: all ${POOLS} nodes responding"
