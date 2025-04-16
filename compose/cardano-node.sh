#!/usr/bin/env bash

# Required for overriding exit code
#set -o errexit
set -o pipefail

SHELL="/bin/bash"
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"

# Environment variables
EKG_PORT="${EKG_PORT:-12788}"
LOG_TO_CONSOLE="${LOG_TO_CONSOLE:-true}"
LOG_TO_FILE="${LOG_TO_FILE:-true}"
MIN_SEVERITY="${MIN_SEVERITY:-Error}"
PEER_SHARING="${PEER_SHARING:-true}"
POOL_ID="${POOL_ID:-}"
PORT="${PORT:-3001}"
PROMETHEUS_LISTEN="${PROMETHEUS_LISTEN:-127.0.0.1}"
PROMETHEUS_PORT="${PROMETHEUS_PORT:-12798}"
SYSTEM_START="${SYSTEM_START:-$(date -d "@$(( ( $(date +%s) / 120 ) * 120 ))" +%Y-%m-%dT%H:%M:00Z)}"
TYPE="${TYPE:-bp}"
USE_LEDGER_AFTER_SLOT="${USE_LEDGER_AFTER_SLOT:-0}"

# Antithesis
ANTITHESIS_OUTPUT_DIR="${ANTITHESIS_OUTPUT_DIR:-/tmp}"

# Configuration files
BYRON_GENESIS_JSON="${BYRON_GENESIS_JSON:-/opt/cardano-node/pools/${POOL_ID}/configs/byron-genesis.json}"
CONFIG_JSON="/opt/cardano-node/pools/${POOL_ID}/configs/config.json"
CONFIG_PATH="/opt/cardano-node/config"
DATA_PATH="/opt/cardano-node/data"
DATABASE_PATH="/opt/cardano-node/data/db"
KEY_PATH="/opt/cardano-node/pools/${POOL_ID}/keys"
SHELLEY_GENESIS_JSON="${SHELLEY_GENESIS_JSON:-/opt/cardano-node/pools/${POOL_ID}/configs/shelley-genesis.json}"
SOCKET_PATH="/opt/cardano-node/data/db/node.socket"

# Log file
LOG_FILE="/opt/cardano-node/log/node.json"

# Implement sponge-like command without the need for binary nor TMPDIR environment variable
write_file() {
    # Create temporary file
    local tmp_file="${1}_$(tr </dev/urandom -dc A-Za-z0-9 | head -c16)"

    # Redirect the output to the temporary file
    cat >"${tmp_file}"

    # Replace the original file
    mv --force "${tmp_file}" "${1}"
}

verify_environment_variables() {
    if [ -z "${POOL_ID}" ]; then
        echo "POOL_ID not defined, exiting..."
        sleep 60
        exit 1
    fi
}

config_config_json() {
    # .AlonzoGenesisHash, .ByronGenesisHash, .ConwayGenesisHash, .ShelleyGenesisHash
    jq "del(.AlonzoGenesisHash, .ByronGenesisHash, .ConwayGenesisHash, .ShelleyGenesisHash)" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"

    # .hasEKG
    jq "del(.hasEKG)" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"

    # .options.mapBackends
    jq "del(.options.mapBackends)" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"

    # .minSeverity
    jq ".minSeverity = \"${MIN_SEVERITY^}\"" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"

    # .hasPrometheus
    jq ".hasPrometheus = [\"${PROMETHEUS_LISTEN}\", ${PROMETHEUS_PORT}]" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"

    # .defaultScribes, .setupScribes
    if [ "${LOG_TO_CONSOLE,,}" = "true" ] && [ "${LOG_TO_FILE,,}" = "true" ]; then
        jq ".\"defaultScribes\" = [[\"StdoutSK\", \"stdout\"], [\"FileSK\", \"${LOG_FILE}\"]]" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"
        jq ".\"setupScribes\" = [{\"scFormat\": \"ScJson\", \"scKind\": \"StdoutSK\", \"scName\": \"stdout\", \"scRotation\": null}, {\"scFormat\": \"ScJson\", \"scKind\": \"FileSK\", \"scName\": \"${LOG_FILE}\", \"scRotation\": null}]" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"
    elif [ "${LOG_TO_CONSOLE,,}" = "false" ] && [ "${LOG_TO_FILE,,}" = "true" ]; then
        jq ".\"defaultScribes\" = [[\"FileSK\", \"${LOG_FILE}\"]]" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"
        jq ".\"setupScribes\" = [{\"scFormat\": \"ScJson\", \"scKind\": \"FileSK\", \"scName\": \"${LOG_FILE}\", \"scRotation\": null}]" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"
    else
        jq '."defaultScribes" = [["StdoutSK", "stdout"]]' "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"
        jq '."setupScribes" = [{"scFormat": "ScJson", "scKind": "StdoutSK", "scName": "stdout", "scRotation": null}]' "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"
    fi

    # .PeerSharing
    if [ "${PEER_SHARING,,}" = "true" ]; then
        jq ".PeerSharing = true" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"
    else
        jq ".PeerSharing = false" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"
    fi
}

config_topology_json() {
    # Generate a ring topology, where pool_n is connected to pool_{n-1} and pool_{n+1}

    # Count number of pools
    POOLS=$(ls -d /opt/cardano-node/pools/* | wc -l)
    VALENCY=2

    local num_pools=$POOLS
    local i prev next

    for ((i=1; i<=num_pools; i++)); do
        prev=$((i - 1))
        if [ $prev -eq 0 ]; then
            prev=$num_pools
        fi

        next=$((i + 1))
        if [ $next -gt $num_pools ]; then
            next=1
        fi

        cat <<EOF > "${CONFIG_PATH}/topology${i}.json"
{
  "localRoots": [
    {
      "accessPoints": [
        {"address": "p${prev}.example", "port": 3001},
        {"address": "p${next}.example", "port": 3001}
      ],
    "advertise": true,
    "trustable": true,
    "valency": ${VALENCY}
    }
  ],
    "publicRoots": [],
    "useLedgerAfterSlot": 0
}
EOF
    done
}

set_start_time() {
    if [ ! -f "${DATA_PATH}/start_time.unix_epoch" ]; then
        # Convert ISO time to unix epoch
        SYSTEM_START_UNIX=$(date -d "${SYSTEM_START}" +%s)
        echo "${SYSTEM_START_UNIX}" >"${DATA_PATH}/start_time.unix_epoch"

        update_start_time
    else
        SYSTEM_START_UNIX="$(cat "${DATA_PATH}/start_time.unix_epoch")"
        update_start_time
    fi
}

update_start_time() {
    # Convert unix epoch to ISO time
    SYSTEM_START_ISO="$(date -d @${SYSTEM_START_UNIX} '+%Y-%m-%dT%H:%M:00Z')"

    # .systemStart
    jq ".systemStart = \"${SYSTEM_START_ISO}\"" "${SHELLEY_GENESIS_JSON}" | write_file "${SHELLEY_GENESIS_JSON}"

    # .startTime
    jq ".startTime = ${SYSTEM_START_UNIX}" "${BYRON_GENESIS_JSON}" | write_file "${BYRON_GENESIS_JSON}"
}

canary_tx() {
    /canary_tx.sh >/dev/null 2>&1
}

assemble_command() {
    cmd=(/usr/local/bin/cardano-node)
    cmd+=(run)
    cmd+=(--database-path ${DATABASE_PATH})
    cmd+=(--socket-path ${SOCKET_PATH})
    cmd+=(--tracer-socket-path-connect /opt/cardano-tracer/tracer.socket)

    # TYPE
    if [ "${TYPE,,}" = "bp" ]; then
        cmd+=(--shelley-operational-certificate ${KEY_PATH}/opcert.cert)
        cmd+=(--shelley-kes-key ${KEY_PATH}/kes.skey)
        cmd+=(--shelley-vrf-key ${KEY_PATH}/vrf.skey)
    fi

    cmd+=(--config ${CONFIG_JSON})
    cmd+=(--port ${PORT})
    cmd+=(--topology ${CONFIG_PATH}/topology${POOL_ID}.json)
}

# Establish run order
main() {
    verify_environment_variables
    config_config_json
    config_topology_json
    set_start_time
    canary_tx &
    assemble_command
    "${cmd[@]}"
    exit_code=$?
    if [ ${exit_code} -eq 1 ]; then
        echo "exit code: 0"
        exit 0
    else
        echo "exit code: ${exit_code}"
        exit ${?}
    fi
}

main
