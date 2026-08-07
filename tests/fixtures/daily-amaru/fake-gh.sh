#!/usr/bin/env bash
set -euo pipefail

# Deterministic `gh` stand-in: no network call, and every invocation recorded so
# a proof can count the effects a broken precondition was allowed to reach.
log_file=${DAILY_AMARU_FAKE_GH_LOG:?DAILY_AMARU_FAKE_GH_LOG is required}

{
  printf 'gh'
  if [ "$#" -gt 0 ]; then
    printf ' %s' "$@"
  fi
  printf '\n'
} >>"$log_file"
