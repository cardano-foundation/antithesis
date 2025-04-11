#!/usr/bin/env bash

set -o pipefail

SHELL="/bin/bash"
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"

# Environment variables
CONVERGENCE_COMPOSER="${CONVERGENCE_COMPOSER:-true}"
POOLS="${POOLS:-}"
PORT="${PORT:-3001}"

# Antithesis
ANTITHESIS_OUTPUT_DIR="${ANTITHESIS_OUTPUT_DIR:-/tmp}"

verify_environment_variables() {
    if [ -z "${POOLS}" ]; then
        echo "POOLS not defined, exiting..."
        sleep 60
        exit 1
    fi
}

enable_composers() {
    # CONVERGENCE_COMPOSER
    if [ "${CONVERGENCE_COMPOSER,,}" = "true" ]; then
        ln -snf /opt/composer/convergence /opt/antithesis/test/v1/convergence
    fi
}

signal_ready() {
    if [ ! -f "${ANTITHESIS_OUTPUT_DIR}/sdk.jsonl" ]; then
        for i in $(seq 1 "${POOLS}"); do
            (
                while true; do
                    cardano-cli ping -c1 -q -j --magic 42 --host p${i}.example --port ${PORT} 2>/dev/null
                    if [ $? -ne 0 ] ; then
                        sleep 1
                        continue
                    else
                        break
                    fi
                done
            ) &
        done
        wait
        echo '{"antithesis_setup": { "status": "complete", "details": null }}' >"${ANTITHESIS_OUTPUT_DIR}/sdk.jsonl"
    fi
}

# Establish run order
main() {
    verify_environment_variables
    enable_composers
    signal_ready
    while true; do
        sleep 60
    done
}

main
