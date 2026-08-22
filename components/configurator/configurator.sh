#!/usr/bin/env bash
set -o pipefail

UTXO_HD_WITH="mem"

# Log file

# Implement sponge-like command without the need for binary nor TMPDIR environment variable
write_file() {
    # Create temporary file
    local tmp_file="${1}_$(tr </dev/urandom -dc A-Za-z0-9 | head -c16)"

    # Redirect the output to the temporary file
    cat >"${tmp_file}"

    # Replace the original file
    mv --force "${tmp_file}" "${1}"
}

# Updates specific node's configuration depending on environment variables
# Those environment variables can be set in the service definition in the
# docker-compose file like:
#
# ```
# p2:
#   <<: *base
#   container_name: p2
#   hostname: p2.example
#   volumes:
#     - p2:/opt/cardano-node/data
#   ports:
#     - "3002:3001"
#   environment:
#     <<: *env
#     POOL_ID: "2"
#     PEER_SHARING: "false"
# ```
config_config_json() {
    PEER_SHARING="${PEER_SHARING:-true}"
    CONFIG_JSON=$1/configs/config.json
    # .AlonzoGenesisHash, .ByronGenesisHash, .ConwayGenesisHash, .ShelleyGenesisHash
    jq "del(.AlonzoGenesisHash, .ByronGenesisHash, .ConwayGenesisHash, .ShelleyGenesisHash)" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"

    # .hasEKG
    jq "del(.hasEKG)" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"

    # .options.mapBackends
    jq "del(.options.mapBackends)" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"

    # .PeerSharing
    if [ "${PEER_SHARING,,}" = "true" ]; then
        jq ".PeerSharing = true" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"
    else
        jq ".PeerSharing = false" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"
    fi

    # configure UTxO-HD
    # see https://ouroboros-consensus.cardano.intersectmbo.org/docs/for-developers/utxo-hd/migrating
    # FIXME: /state needs to match the --database-path in the
    # node's command
    # FIXME: We want to be able to configure this for each node separately
    # FIXME: Btw also think about how to have a nice abstraction for generating
    # the configs
    # One alternative is:
    # UTXO_HD_WITH: "hd hd hd mem mem mem"
    case "${UTXO_HD_WITH,,}" in
        hd)
            jq ".LedgerDB = { Backend: \"V1LMDB\", LiveTablesPath: \"/state/lmdb\"}" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"
            ;;
        *)
            jq '.LedgerDB = { Backend: "V2InMemory"}' "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"
            ;;
    esac
}

config_topology_json() {
    # Generate a ring topology, where pool_n is connected to pool_{n-1} and pool_{n+1}

    # Count number of pools
    VALENCY=2

    local num_pools=$2
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

        cat <<EOF > "/configs/$i/configs/topology.json"
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
    # TODO: the rounding is no longer needed
    SYSTEM_START=$(date -d "@$(( ( $(date +%s) / 120 ) * 120 ))" +%Y-%m-%dT%H:%M:00Z)
    SYSTEM_START_UNIX=$(date -d "${SYSTEM_START}" +%s)
    SHELLEY_GENESIS_JSON="$1/configs/shelley-genesis.json"
    BYRON_GENESIS_JSON="$1/configs/byron-genesis.json"

    # Convert unix epoch to ISO time
    SYSTEM_START_ISO="$(date -d @${SYSTEM_START_UNIX} '+%Y-%m-%dT%H:%M:00Z')"

    # .systemStart
    jq ".systemStart = \"${SYSTEM_START_ISO}\"" "${SHELLEY_GENESIS_JSON}" | write_file "${SHELLEY_GENESIS_JSON}"

    # .startTime
    jq ".startTime = ${SYSTEM_START_UNIX}" "${BYRON_GENESIS_JSON}" | write_file "${BYRON_GENESIS_JSON}"
}


# # Copy testnet.yaml specification
cp /testnet.yaml ./testnet.yaml

# # Build testnet configuration files
uv run python3 genesis-cli.py testnet.yaml -o /tmp/testnet -c generate

# # Remove dynamic topology.json
find /tmp/testnet -type f -name 'topology.json' -exec rm -f '{}' ';'

mkdir -p /configs
cp -r /tmp/testnet/pools/* /configs

# Preserve UTxO keys for tx-generator before pool-specific keys overwrite them
if [ -d "/configs/keys" ] && [ -d "/utxo-keys" ]; then
  echo "preserving UTxO keys to /utxo-keys"
  cp -r /configs/keys/* /utxo-keys/ 2>/dev/null || true
fi

echo "removing /configs/keys"; rm -rf /configs/keys

# Bump Alonzo ExUnits limits to fit asteria's add_new_ship script,
# which exceeds the cardano-cli default maxTxExUnits.steps of
# 10_000_000_000 by a few hundred thousand steps. 14B / 14M is
# comfortable headroom; matching maxBlockExUnits scales by 4x as
# the upstream defaults do.
echo "bumping Alonzo maxTxExUnits + maxBlockExUnits for asteria"
for ag in /configs/*/configs/alonzo-genesis.json; do
  jq '.maxTxExUnits.exUnitsMem    = 14000000
    | .maxTxExUnits.exUnitsSteps  = 14000000000
    | .maxBlockExUnits.exUnitsMem = 80000000
    | .maxBlockExUnits.exUnitsSteps = 64000000000' "$ag" | write_file "$ag"
done

pools=$(ls -d /configs/*)
number_of_pools=$(ls -d /configs/* | wc -l)
echo "number_of_pools: $number_of_pools"
for pool in $pools; do
  echo "pool: $pool"
  config_config_json "$pool"
  pool_ix=$(echo "$pool" | awk -F '/' '{print $3}')
  config_topology_json "$pool_ix" "$number_of_pools"
  set_start_time "$pool"
  cp -r /tmp/testnet/utxos/* /configs/$pool_ix
done

# Write roles.json manifest for tracer-sidecar & assertion probes
echo "generating /configs/roles.json manifest..."
cat <<EOF > /configs/roles.json
{
  "producers": [
    "p1", "p2", "p3", "p4", "p5",
    "relay1", "relay2", "relay3",
    "amaru-relay-1", "amaru-relay-2", "amaru-relay-3",
    "bootstrap-producer"
  ],
  "consumer": "amaru-consumer"
}
EOF
