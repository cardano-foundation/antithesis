#!/usr/bin/env bash
set -euo pipefail

# Deterministic stand-in for the `gh` CLI inside the scheduled-runner controls.
# It performs no network call and records every invocation so a proof can count
# the business effects a broken precondition was allowed to reach.
log_file=${DAILY_AMARU_FAKE_GH_LOG:?DAILY_AMARU_FAKE_GH_LOG is required}

{
  printf 'gh'
  if [ "$#" -gt 0 ]; then
    printf ' %s' "$@"
  fi
  printf '\n'
} >>"$log_file"
