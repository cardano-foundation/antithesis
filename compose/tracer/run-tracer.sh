#!/usr/bin/env bash
# this script is meant to be run by root and
# in order to adjust permissions for mounted folder,
# then switch to user cardano for running tracer

chown -R cardano /opt/cardano-tracer

runuser -u cardano -- /usr/local/bin/cardano-tracer $@
