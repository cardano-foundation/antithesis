#!/usr/bin/env bash
set -euo pipefail

scenario=${FAKE_SCENARIO:-changed}
log_file=${FAKE_LOG:?FAKE_LOG is required}
state_dir=${DAILY_AMARU_STATE_DIR:?DAILY_AMARU_STATE_DIR is required}
receipt_file=${DAILY_AMARU_RECEIPT:?DAILY_AMARU_RECEIPT is required}

upstream_sha=1111111111111111111111111111111111111111
bootstrap_sha=2222222222222222222222222222222222222222
consumer_sha=3333333333333333333333333333333333333333
integrated_sha=4444444444444444444444444444444444444444
image_ref="ghcr.io/lambdasistemi/amaru-bootstrap-producer:${bootstrap_sha}@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

mkdir -p "$state_dir"
markers_file=$state_dir/markers
receipt_history=$state_dir/receipt-history
touch "$markers_file" "$receipt_history"

log() {
  printf '%s' "$1" >>"$log_file"
  shift
  if [ "$#" -gt 0 ]; then
    printf ' %s' "$@" >>"$log_file"
  fi
  printf '\n' >>"$log_file"
}

increment() {
  local file=$1
  local count=0
  if [ -f "$file" ]; then
    read -r count <"$file"
  fi
  printf '%s\n' "$((count + 1))" >"$file"
}

identity_marker() {
  if [ -n "${DAILY_AMARU_IDENTITY:-}" ]; then
    printf 'identity-present'
  else
    printf 'identity-absent'
  fi
}

validate_head() {
  [[ "$1" =~ ^[0-9a-f]{40}$ ]] || {
    printf 'invalid workflow head: %s\n' "$1" >&2
    return 1
  }
}

claim_prelaunch_marker() {
  local kind=$1 value=$2 head=$3 line marker legacy_marker current_prefix
  local previous_head='' recorded_head='' found=0

  if [ "$scenario" = census-failure ]; then
    printf 'BLOCKED census-unreadable\n'
    return 1
  fi
  if [ "$kind" = day ]; then
    while IFS= read -r line; do
      if [[ "$line" =~ ^\<\!--\ daily-amaru\ day="$value"\ launch-consumed\ head=[0-9a-f]{40}\ --\>$ ]]; then
        printf 'BLOCKED launch-consumed\n'
        return 1
      fi
    done <"$markers_file"
    legacy_marker="<!-- daily-amaru day=$value claim -->"
    current_prefix="<!-- daily-amaru day=$value claim head="
    marker="<!-- daily-amaru day=$value claim head=$head -->"
  else
    legacy_marker="<!-- daily-amaru attempted-sha=$value -->"
    current_prefix="<!-- daily-amaru attempted-sha=$value head="
    marker="<!-- daily-amaru attempted-sha=$value head=$head -->"
  fi
  while IFS= read -r line; do
    if [ "$line" = "$legacy_marker" ]; then
      found=1
      previous_head=legacy
      continue
    fi
    if [[ "$line" == "$current_prefix"*' -->' ]]; then
      recorded_head=${line#"$current_prefix"}
      recorded_head=${recorded_head%' -->'}
      [[ "$recorded_head" =~ ^[0-9a-f]{40}$ ]] || continue
      found=1
      previous_head=$recorded_head
      if [ "$recorded_head" = "$head" ]; then
        printf 'BLOCKED unchanged-head\n'
        return 1
      fi
    fi
  done <"$markers_file"
  printf '%s\n' "$marker" >>"$markers_file"
  if [ "$kind" = day ]; then
    printf '%s\n' "$value" >"$state_dir/day-claim"
  else
    printf '%s\n' "$value" >"$state_dir/attempted-sha"
  fi
  if [ "$found" -eq 0 ]; then
    printf 'CLAIMED\n'
  else
    printf 'SUPERSEDED previous-head=%s\n' "$previous_head"
  fi
}

operation=${1:?transport operation is required}
shift

case "$operation" in
  preflight)
    log preflight "$@"
    case "$scenario" in
      missing-tool)
        printf 'MISSING-COMMAND rg\n'
        printf 'daily-amaru-github: missing command: rg\n' >&2
        exit 1
        ;;
      silent-preflight)
        ;;
      malformed-preflight)
        printf 'dependencies look fine\n'
        ;;
      *)
        printf 'OK: 15 scheduled dependencies present: %s\n' \
          'gh git jq rg sed awk grep tail tr head seq sleep date docker nix'
        ;;
    esac
    ;;

  claim-day)
    day=${1:?day is required}
    head=${2:?head is required}
    validate_head "$head"
    log claim-day "$day" "$head"
    claim_prelaunch_marker day "$day" "$head"
    ;;

  resolve-upstream)
    origin=${1:?origin is required}
    ref=${2:?ref is required}
    log resolve-upstream "$origin" "$ref"
    case "$scenario" in
      zero-observation) ;;
      ambiguous-observation)
        printf '%s|%s|%s\n' "$origin" "$ref" "$upstream_sha"
        printf '%s|%s|%s\n' "$origin" "$ref" 9999999999999999999999999999999999999999
        ;;
      malformed-observation)
        printf '%s|%s|not-a-full-sha\n' "$origin" "$ref"
        ;;
      wrong-origin-observation)
        printf '%s|%s|%s\n' https://github.com/fork/amaru.git "$ref" "$upstream_sha"
        ;;
      wrong-ref-observation)
        printf '%s|%s|%s\n' "$origin" refs/heads/develop "$upstream_sha"
        ;;
      *)
        printf '%s|%s|%s\n' "$origin" "$ref" "$upstream_sha"
        ;;
    esac
    ;;

  last-success-sha)
    log last-success-sha
    if [ "$scenario" = unchanged ]; then
      printf '%s\n' "$upstream_sha"
    fi
    ;;

  claim-sha-attempt)
    sha=${1:?upstream SHA is required}
    head=${2:?head is required}
    validate_head "$head"
    log claim-sha-attempt "$sha" "$head"
    claim_prelaunch_marker sha "$sha" "$head"
    ;;

  claim-launch)
    day=${1:?day is required}
    head=${2:?head is required}
    validate_head "$head"
    log claim-launch "$day" "$head"
    while IFS= read -r line; do
      if [[ "$line" =~ ^\<\!--\ daily-amaru\ day="$day"\ launch-consumed\ head=[0-9a-f]{40}\ --\>$ ]]; then
        printf 'BLOCKED launch-consumed\n'
        exit 1
      fi
    done <"$markers_file"
    printf '<!-- daily-amaru day=%s launch-consumed head=%s -->\n' \
      "$day" "$head" >>"$markers_file"
    printf 'CLAIMED\n'
    ;;

  propose-bootstrap)
    sha=${1:?upstream SHA is required}
    # Same expansion as production: observe the day, never synthesize one.
    day=${DAILY_AMARU_DAY:?DAILY_AMARU_DAY is required}
    # The minted bootstrap identity travels in the process environment only, so
    # the log records its presence and never its value.
    log mutation:bootstrap "$sha" "$(identity_marker)"
    log observed-day propose-bootstrap "$day"
    if [ "$scenario" = failed-stage ]; then
      printf 'bootstrap proposal failed\n' >&2
      exit 1
    fi
    printf '%s\n' "$bootstrap_sha"
    ;;

  require-bootstrap-checks)
    candidate=${1:?bootstrap candidate is required}
    log require-bootstrap-checks "$candidate"
    printf 'bootstrap-checks success head=%s\n' "$candidate"
    ;;

  resolve-image)
    candidate=${1:?bootstrap candidate is required}
    log mutation:image "$candidate"
    printf '%s\n' "$image_ref"
    ;;

  prepare-consumer-repin)
    image=${1:?image is required}
    # Same expansion as production: observe the day, never synthesize one.
    day=${DAILY_AMARU_DAY:?DAILY_AMARU_DAY is required}
    log mutation:repin "$image"
    log observed-day prepare-consumer-repin "$day"
    printf '%s\n' "$consumer_sha"
    ;;

  require-consumer-checks)
    head=${1:?consumer head is required}
    log require-consumer-checks "$head"
    rows=(
      "Build and push component images for cardano-node testnet|publish-images|$head|success"
      "Build and push component images for cardano-node testnet|Compose smoke test|$head|success"
      "tracer-sidecar CI|Build|$head|success"
      "tracer-sidecar CI|Run unit Tests|$head|success"
      "tracer-sidecar CI|Check code quality|$head|success"
      "Build documentation|build-docs|$head|success"
      "PR preview|preview|$head|success"
    )
    case "$scenario" in
      missing-check) unset 'rows[6]' ;;
      wrong-head-check)
        rows[0]="Build and push component images for cardano-node testnet|publish-images|5555555555555555555555555555555555555555|success"
        ;;
      ambiguous-check)
        rows+=("Build and push component images for cardano-node testnet|publish-images|$head|success")
        ;;
      pending-check)
        rows[0]="Build and push component images for cardano-node testnet|publish-images|$head|pending"
        ;;
      failed-check)
        rows[0]="Build and push component images for cardano-node testnet|publish-images|$head|failure"
        ;;
    esac
    printf '%s\n' "${rows[@]}"
    ;;

  run-producer-check)
    head=${1:?consumer head is required}
    log run-producer-check "$head"
    case "$scenario" in
      '#202-failure')
        printf '#202 command failed\n' >&2
        exit 1
        ;;
      '#202-zero')
        printf 'OK: 0 producer-image reference(s), all pinned to %s\n' "$image_ref"
        ;;
      *)
        printf 'OK: 3 producer-image reference(s), all pinned to %s\n' "$image_ref"
        ;;
    esac
    ;;

  await-supervised-integration)
    head=${1:?consumer head is required}
    log await-supervised-integration "$head"
    case "$scenario" in
      awaiting-integration | awaiting-integration-threshold | awaiting-integration-stale)
        printf 'daily-amaru-github: consumer repin is awaiting guarded integration\n' >&2
        printf 'AWAITING https://example.invalid/pull/17\n'
        exit 75
        ;;
      integration-head-mismatch)
        printf 'daily-amaru-github: integrated PR head differs from the verified candidate\n' >&2
        exit 1
        ;;
      integration-not-exact-main)
        printf 'daily-amaru-github: merged consumer commit is not exact current main\n' >&2
        exit 1
        ;;
      *) printf '%s\n' "$integrated_sha" ;;
    esac
    ;;

  awaiting-integration-age)
    sha=${1:?upstream SHA is required}
    day=${2:?day is required}
    log awaiting-integration-age "$sha" "$day"
    case "$scenario" in
      awaiting-integration-threshold) printf '3\n' ;;
      awaiting-integration-stale) printf '4\n' ;;
      *) printf '1\n' ;;
    esac
    ;;

  fake-launch)
    log fake-launch "$@"
    increment "$state_dir/fake-launch-count"
    printf 'fake-request-%s\n' "$upstream_sha"
    ;;

  real-launch)
    log real-launch "$@"
    increment "$state_dir/real-launch-count"
    printf 'unexpected-real-request\n'
    ;;

  receipt)
    log receipt "$@"
    : >"$receipt_file"
    printf '%s\n' "$@" >>"$receipt_file"
    printf '%s\n' '--- receipt ---' >>"$receipt_history"
    printf '%s\n' "$@" >>"$receipt_history"
    ;;

  *)
    printf 'unknown transport operation: %s\n' "$operation" >&2
    exit 64
    ;;
esac
