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

comments_file=${DAILY_AMARU_FAKE_GH_COMMENTS:-}

if [ "${1:-}" = api ]; then
  for argument in "$@"; do
    if [[ "$argument" == repos/*/issues/*/comments* ]]; then
      if [ "${DAILY_AMARU_FAKE_GH_CENSUS_FAIL:-0}" = 1 ]; then
        printf 'fake-gh: forced comment census failure\n' >&2
        exit 70
      fi
      [ -z "$comments_file" ] || cat "$comments_file"
      exit 0
    fi
  done
fi

if [ "${1:-}" = issue ] && [ "${2:-}" = comment ]; then
  [ -n "$comments_file" ] || {
    printf 'fake-gh: comment store is required\n' >&2
    exit 64
  }
  body=''
  shift 2
  while [ "$#" -gt 0 ]; do
    if [ "$1" = --body ]; then
      body=${2:?--body value is required}
      break
    fi
    shift
  done
  [ -n "$body" ] || {
    printf 'fake-gh: comment body is required\n' >&2
    exit 64
  }
  printf '%s\n' "$body" >>"$comments_file"
fi
