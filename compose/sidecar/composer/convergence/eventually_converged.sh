#!/usr/bin/env bash

set -o pipefail

SHELL="/bin/bash"
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"

# Environment variables
POOLS="${POOLS:-}"
PORT="${PORT:-3001}"

verify_environment_variables() {
    if [ -z "${POOLS}" ]; then
        echo "POOLS not defined, exiting..."
        sleep 60
        exit 1
    fi
}

validate_block_hash() {
    temp_dir=$(mktemp -d)
    pids=()

    # Fetch hashes in parallel
    for i in $(seq 1 "${POOLS}"); do
        (
            cardano-cli ping -j --magic 42 --host p${i}.example --port ${PORT} --tip --quiet -c1 | jq -r '.tip[0].hash + " " + (.tip[0].blockNo|tostring) + " " + (.tip[0].slotNo|tostring)' >"$temp_dir/hash_${i}"
        ) &
        pids+=($!)
    done

    # Wait for all processes and handle errors
    for (( i=0; i < ${#pids[@]}; i++ )); do
        pid=${pids[$i]}
        if ! wait "$pid"; then
            j=$(( i + 1 ))
            echo "Error: Host p${j}.example failed" >&2
            status=2
        fi
    done

    # Analyze results
    hash_files=("$temp_dir"/hash_*)
    hash_count=$(cut -d' ' -f1 "${hash_files[@]}" | sort | uniq | wc -l)

    if [ "${status}" -eq 2 ]; then
        status=1
    elif [ "$hash_count" -eq 1 ]; then
        # All hashes match
        common_line=$(head -n1 "${hash_files[0]}")
        read -r hash block slot <<< "$common_line"
        message="[{\"status\":\"synced\",\"hash\":\"${hash}\",\"block\":\"${block}\",\"slot\":\"${slot}\"}]"
        status=0
    else
        # Hash mismatch detected
        for file in "${hash_files[@]}"; do
            pool_id=$(basename "$file" | sed 's/hash_//')
            read -r hash block slot <<< "$(cat "$file")"
            message="[{\"status\":\"diverged\",\"hash\":\"${hash}\",\"block\":\"${block}\",\"slot\":\"${slot}\",\"pool_id\":\"${pool_id}\"}]"
            echo "${message}"
        done
        status=1
    fi
}

# Establish run order
main() {
    verify_environment_variables
    while true; do
        status=1

        for i in {1..100}; do
            validate_block_hash
            if [ "${status}" -eq 0 ]; then
                break
            else
                sleep 2
            fi
        done

        if [ "${status}" -eq 0 ]; then
            echo "${message}"
            exit 0
        else
            echo "[{\"status\":\"diverged\"}]"
            exit 1
        fi

        sleep 300
    done
}

main
