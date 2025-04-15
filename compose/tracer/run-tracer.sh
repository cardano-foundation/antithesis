#!/usr/bin/env bash
# this script is meant to be run by root and
# in order to adjust permissions for mounted folder,
# then switch to user cardano for running tracer

chown -R cardano /opt/cardano-tracer

ANTITHESIS_OUTPUT_DIR="${ANTITHESIS_OUTPUT_DIR:-/tmp}"

combine_filtered_logs() {

    # wait for cardano-tracer to create the log files
    # however, this will cause us to miss the first logs though
    sleep 2

    for logfile in /opt/cardano-tracer/p*.example_3001/node-*.json; do

	# Filter for traces we care about
	# Rewrite to format antithesis expects
	# https://antithesis.com/docs/using_antithesis/sdk/fallback/lifecycle/#event
	local filter="AdoptedBlock|SwitchedToAFork|ForgedBlock|AddBlockEvent"
        tail -f "$logfile" 2>/dev/null \
		| grep --line-buffered -E "Trace(${filter})" \
		| jq -c --unbuffered '{ (.data.kind | sub("^Trace";"")): {host: .host, data: .data, at: .at} }' \
		>> $ANTITHESIS_OUTPUT_DIR/sdk.jsonl &
    done
}

combine_filtered_logs &

runuser -u cardano -- /usr/local/bin/cardano-tracer "$@"
