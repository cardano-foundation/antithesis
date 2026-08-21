#!/usr/bin/env bash
set -euo pipefail

record=nix/peer-snapshots/resolution.json
flake_lock=${FLAKE_LOCK:-./flake.lock}
write=false
log_file=${DAILY_AMARU_BOUNDARY_RESOLVER_LOG:-}
selected=${DAILY_AMARU_BOUNDARY_SELECTED_CONFIGS_REV:-4444444444444444444444444444444444444444}
fail_mode=${DAILY_AMARU_BOUNDARY_RESOLVER_FAIL:-}

fail() {
  echo "peer-snapshot resolution failed: $*" >&2
  exit 1
}

case "${1:-}" in
  '') ;;
  --write) write=true ;;
  *) fail "usage: $0 [--write]" ;;
esac
[ "$#" -le 1 ] || fail "usage: $0 [--write]"
[ -f "$flake_lock" ] || fail "flake lock not found: $flake_lock"

amaru_rev=$(jq -er '.nodes.amaru.locked.rev' "$flake_lock") ||
  fail 'amaru locked rev is missing'
pinned_configs_rev=$(
  jq -er '.nodes["cardano-configurations"].locked.rev' "$flake_lock"
) || fail 'cardano-configurations locked rev is missing'

if [ -n "$log_file" ]; then
  printf 'resolver write=%s amaru_rev=%s pinned_configs_rev=%s selected_configs_rev=%s cwd=%s\n' \
    "$write" "$amaru_rev" "$pinned_configs_rev" "$selected" "$PWD" >>"$log_file"
fi

if [ "$fail_mode" = network ]; then
  fail 'network/rate-limit'
fi

if [ "$fail_mode" = malformed ]; then
  if $write; then
    mkdir -p "$(dirname "$record")"
    printf 'not-json\n' >"$record"
  fi
  fail 'malformed result'
fi

if $write; then
  mkdir -p "$(dirname "$record")"
  jq -n \
    --arg amaru_rev "$amaru_rev" \
    --arg configs_rev "$selected" \
    '{
      amaru_rev: $amaru_rev,
      amaru_committer_date_utc: "2026-01-01T00:00:00Z",
      configs_rev: $configs_rev,
      resolved_at_utc: "2026-01-01T00:00:00Z",
      query_url: "https://example.invalid/commits",
      snapshots: {
        mainnet: {sha256: "aa"},
        preprod: {sha256: "bb"},
        preview: {sha256: "cc"}
      }
    }' >"$record.boundary-new"
  mv "$record.boundary-new" "$record"
  echo "wrote $record"
fi

if [ "$fail_mode" = nonzero ]; then
  fail 'injected non-zero'
fi

if [ "$pinned_configs_rev" != "$selected" ]; then
  echo "configs revision: pinned=$pinned_configs_rev resolved=$selected MISMATCH" >&2
  fail 'pinned resolution, input bytes, or committed record differ'
fi

echo 'peer-snapshot resolution verified for 3 networks'
