#!/usr/bin/env bash
set -euo pipefail

log_file=${DAILY_AMARU_BOUNDARY_GH_LOG:?DAILY_AMARU_BOUNDARY_GH_LOG is required}
root=${DAILY_AMARU_OBSERVATION_ROOT:?DAILY_AMARU_OBSERVATION_ROOT is required}

{
  printf 'gh'
  printf ' %q' "$@"
  printf '\n'
} >>"$log_file"

# Persistent per-boundary fault injection for the #231 census. The marker holds
# one boundary name spelled <endpoint-class>-<api|parse>: `api` fails the
# transport itself, `parse` returns a body the census parser cannot read. The
# implemented endpoint classes are the proof's injectable registry, derived
# from the `inject_boundary_fault` call sites below rather than from the
# production census, so registry and census cannot agree by construction.
boundary_fault=''
if [ -f "$root/boundary-fault" ]; then
  boundary_fault=$(cat "$root/boundary-fault")
fi

inject_boundary_fault() {
  local class=$1
  [ -n "$boundary_fault" ] || return 0
  [ "${boundary_fault%-*}" = "$class" ] || return 0
  # Recorded so a proof can require the injection actually executed rather than
  # inferring it from the outcome it was supposed to cause.
  printf 'observation-gh: injected fault boundary=%s\n' "$boundary_fault" \
    >>"$log_file"
  case "${boundary_fault##*-}" in
    api)
      printf 'observation-gh: injected transport error boundary=%s\n' \
        "$boundary_fault" >&2
      exit 1
      ;;
    parse)
      printf '{\n'
      exit 0
      ;;
    *)
      printf 'observation-gh: unusable fault mode: %s\n' "$boundary_fault" >&2
      exit 64
      ;;
  esac
}

case "${1:-}" in
  api)
    [ "$#" -eq 2 ] || exit 64
    endpoint=$2
    if [[ "$endpoint" == repos/*/actions/runs\?head_sha=*\&per_page=100 ]]; then
      n=$(($(cat "$root/poll" 2>/dev/null || printf '0') + 1))
      printf '%s\n' "$n" >"$root/poll"
      inject_boundary_fault runs
      if [ -f "$root/persist_fault" ] || [ -f "$root/fault-$n" ]; then
        printf 'observation-gh: injected transport error poll=%s\n' "$n" >&2
        exit 1
      fi
      if [ -f "$root/persist_malformed" ]; then
        printf '{\n'
        exit 0
      fi
      runs="$root/polls/$n/runs.json"
      [ -f "$runs" ] || exit 64
      cat "$runs"
    elif [ "$endpoint" = 'repos/lambdasistemi/amaru-bootstrap/actions/runs?per_page=30' ]; then
      [ -f "$root/duration.json" ] || exit 64
      cat "$root/duration.json"
    elif [[ "$endpoint" == repos/*/check-suites/*/check-runs\?per_page=100 ]]; then
      inject_boundary_fault check-runs
      n=$(cat "$root/poll")
      suite=${endpoint#*/check-suites/}
      suite=${suite%%/*}
      checks="$root/polls/$n/checks-$suite.json"
      [ -f "$checks" ] || exit 64
      cat "$checks"
    else
      exit 64
    fi
    ;;
  *)
    exit 64
    ;;
esac
