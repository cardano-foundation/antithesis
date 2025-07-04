#!/usr/bin/env bash

# Required for overriding exit code
#set -o errexit
set -o pipefail

SHELL="/bin/bash"
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"

# Environment variables
PORT="${PORT:-3001}"
PROMETHEUS_LISTEN="${PROMETHEUS_LISTEN:-127.0.0.1}"
PROMETHEUS_PORT="${PROMETHEUS_PORT:-12798}"
SYSTEM_START="${SYSTEM_START:-$(date -d "@$(( ( $(date +%s) / 120 ) * 120 ))" +%Y-%m-%dT%H:%M:00Z)}"
USE_LEDGER_AFTER_SLOT="${USE_LEDGER_AFTER_SLOT:-0}"

# Antithesis
ANTITHESIS_OUTPUT_DIR="${ANTITHESIS_OUTPUT_DIR:-/tmp}"

# Configuration files
BYRON_GENESIS_JSON="${BYRON_GENESIS_JSON:-/opt/cardano-node/pools/1/configs/byron-genesis.json}"
CARDANO_CONFIG="/opt/cardano-node/pools/1/configs/config.json"
CONFIG_PATH="/opt/cardano-node/config"
DATA_PATH="/opt/cardano-node/data"
SHELLEY_GENESIS_JSON="${SHELLEY_GENESIS_JSON:-/opt/cardano-node/pools/1/configs/shelley-genesis.json}"

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

config_config_json() {
    # .AlonzoGenesisHash, .ByronGenesisHash, .ConwayGenesisHash, .ShelleyGenesisHash
    jq "del(.AlonzoGenesisHash, .ByronGenesisHash, .ConwayGenesisHash, .ShelleyGenesisHash)" "${CARDANO_CONFIG}" | write_file "${CARDANO_CONFIG}"

    # .PeerSharing
    if [ "${PEER_SHARING,,}" = "true" ]; then
        jq ".PeerSharing = true" "${CARDANO_CONFIG}" | write_file "${CARDANO_CONFIG}"
    else
        jq ".PeerSharing = false" "${CARDANO_CONFIG}" | write_file "${CARDANO_CONFIG}"
    fi
}

config_topology_json() {
    # Connect to everything
    mkdir -p ${CONFIG_PATH}
    cat <<EOF > "${CONFIG_PATH}/topology-dingo.json"
{
  "localRoots": [
    {
      "accessPoints": [
        {"address": "p1.example", "port": 3001},
        {"address": "p2.example", "port": 3001},
        {"address": "p3.example", "port": 3001},
        {"address": "p4.example", "port": 3001},
        {"address": "p5.example", "port": 3001}
      ],
    "advertise": true,
    "trustable": true,
    "valency": 2
    }
  ],
    "publicRoots": [],
    "useLedgerAfterSlot": 0
}
EOF
}

set_start_time() {
    if [ ! -f "${DATA_PATH}/start_time.unix_epoch" ]; then
        # Convert ISO time to unix epoch
        SYSTEM_START_UNIX=$(date -d "${SYSTEM_START}" +%s)
	mkdir -p ${DATA_PATH}
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

export_environment() {
    export CARDANO_CONFIG
    export CARDANO_DATABASE_PATH="/opt/cardano-node/data/db"
    export CARDANO_NETWORK=devnet
    export CARDANO_SOCKET_PATH="/opt/cardano-node/data/db/dingo.socket"
    export CARDANO_TOPOLOGY="${CONFIG_PATH}/topology-dingo.json"
}

# Establish run order
main() {
    config_config_json
    config_topology_json
    set_start_time
    export_environment
    /bin/dingo
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
