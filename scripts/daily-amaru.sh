#!/usr/bin/env bash
set -euo pipefail

mode=${DAILY_AMARU_MODE:-production}
identity=${DAILY_AMARU_IDENTITY:-}
state_dir=${DAILY_AMARU_STATE_DIR:-${RUNNER_TEMP:-/tmp}/daily-amaru}
receipt_path=${DAILY_AMARU_RECEIPT:-$state_dir/receipt}

origin=https://github.com/pragma-org/amaru.git
ref=refs/heads/main

die() {
  printf 'daily-amaru: %s\n' "$*" >&2
  exit 1
}

# Builtin-only dirname: the failure receipt must stay reachable while the
# external command set is still unverified, so nothing here may shell out.
path_directory() {
  local path=$1
  if [[ "$path" != */* ]]; then
    printf '.'
    return 0
  fi
  path=${path%/*}
  printf '%s' "${path:-/}"
}

# Builtin-only UTC day: the failure receipt must still carry a real day when
# the missing external command is `date` itself.
utc_day() {
  local day=${DAILY_AMARU_DAY:-}
  [ -n "$day" ] || day=$(TZ=UTC0 printf '%(%Y-%m-%d)T' -1)
  printf '%s' "$day"
}

case "$mode" in
  production | manual | pull_request | test) ;;
  *) die "unsupported mode: $mode" ;;
esac

export DAILY_AMARU_STATE_DIR=$state_dir
export DAILY_AMARU_RECEIPT=$receipt_path

transport_call() {
  "$transport" "$@"
}

declare -A receipt=()
receipt[upstream_origin]=$origin
receipt[upstream_ref]=$ref

receipt_keys=(
  day stage outcome error
  dependency_census
  upstream_origin upstream_ref upstream_sha
  bootstrap_candidate_sha image_ref
  consumer_candidate_sha check_evidence producer_count producer_evidence
  consumer_integrated_sha
  launch_workflow launch_test launch_duration launch_no_faults
  launch_request moog_request run_outcome
)

receipt_fields=()

compose_receipt() {
  local stage=$1
  local outcome=$2
  local pair key value
  shift 2

  receipt[stage]=$stage
  receipt[outcome]=$outcome
  unset 'receipt[error]'
  for pair in "$@"; do
    key=${pair%%=*}
    value=${pair#*=}
    receipt["$key"]=$value
  done
  receipt_fields=()
  for key in "${receipt_keys[@]}"; do
    if [[ -v "receipt[$key]" ]]; then
      receipt_fields+=("$key=${receipt[$key]}")
    fi
  done
}

# Independently writable durable sink. An unreachable primary receipt path —
# a nested parent the runner never created, with `mkdir` itself missing — must
# not erase the machine-readable failure.
publish_independent_receipt() {
  printf '%s\n' "${receipt_fields[@]}" >&2
}

# Refreshed before any external publication, so a transport whose own
# preconditions are broken cannot erase the only record of the day. The primary
# receipt stays authoritative wherever it is writable.
persist_local_receipt() {
  local receipt_dir
  receipt_dir=$(path_directory "$receipt_path")
  if [ ! -d "$receipt_dir" ]; then
    mkdir -p -- "$receipt_dir" 2>/dev/null || true
  fi
  if printf '%s\n' "${receipt_fields[@]}" >"$receipt_path"; then
    return 0
  fi
  publish_independent_receipt
}

write_receipt() {
  compose_receipt "$@"
  persist_local_receipt
  transport_call receipt "${receipt_fields[@]}"
}

fail_stage() {
  local stage=$1
  local message=$2
  compose_receipt "$stage" FAILED "error=$message"
  persist_local_receipt
  if ! transport_call receipt "${receipt_fields[@]}"; then
    printf 'daily-amaru: external receipt publication failed: %s\n' "$stage" >&2
  fi
  die "$stage: $message"
}

# First executable boundary: the commands needed to reach the transport at all,
# checked with builtins only so absence is classified rather than crashing.
bootstrap_command_census=(dirname mkdir)
[ -n "${DAILY_AMARU_DAY:-}" ] || bootstrap_command_census+=(date)
for command in "${bootstrap_command_census[@]}"; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'daily-amaru: missing command: %s\n' "$command" >&2
    receipt[day]=$(utc_day)
    compose_receipt runner-preflight FAILED "error=missing-command-$command"
    persist_local_receipt
    die "runner-preflight: missing-command-$command"
  fi
done

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
transport=${DAILY_AMARU_TRANSPORT:-$script_dir/daily-amaru-github.sh}
day=${DAILY_AMARU_DAY:-$(date -u +%F)}
receipt[day]=$day

[[ "$day" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] ||
  die "invalid UTC day: $day"

[ -x "$transport" ] || die "transport is not executable: $transport"
mkdir -p "$state_dir"

# The full census is checked before the UTC day is claimed, so a runner missing
# a required command costs neither the day nor a business effect.
preflight_rc=0
preflight_output=$(transport_call preflight) || preflight_rc=$?
if [ "$preflight_rc" -ne 0 ]; then
  missing_command=''
  while read -r marker name _; do
    [ "$marker" = MISSING-COMMAND ] || continue
    missing_command=$name
  done <<<"$preflight_output"
  [ -n "$missing_command" ] || missing_command=unreported
  fail_stage runner-preflight "missing-command-$missing_command"
fi
[[ "$preflight_output" =~ ^OK:\ [1-9][0-9]*\ scheduled\ dependencies\ present:\ .+$ ]] ||
  fail_stage runner-preflight malformed-dependency-evidence
receipt[dependency_census]=$preflight_output

if ! transport_call claim-day "$day"; then
  fail_stage day-claim duplicate-day
fi
write_receipt day-claim CLAIMED

observation_output=''
if ! observation_output=$(transport_call resolve-upstream "$origin" "$ref"); then
  fail_stage resolve-upstream observation-command-failed
fi

mapfile -t observations < <(printf '%s\n' "$observation_output" | sed '/^$/d')
if [ "${#observations[@]}" -ne 1 ]; then
  fail_stage resolve-upstream "observation-count-${#observations[@]}"
fi

observed_origin=''
observed_ref=''
observed_sha=''
extra=''
IFS='|' read -r observed_origin observed_ref observed_sha extra <<<"${observations[0]}"
[ -z "$extra" ] || fail_stage resolve-upstream malformed-observation
[ "$observed_origin" = "$origin" ] || fail_stage resolve-upstream wrong-origin
[ "$observed_ref" = "$ref" ] || fail_stage resolve-upstream wrong-ref
[[ "$observed_sha" =~ ^[0-9a-f]{40}$ ]] ||
  fail_stage resolve-upstream malformed-sha

receipt[upstream_sha]=$observed_sha
write_receipt resolve-upstream OBSERVED

last_success=''
if ! last_success=$(transport_call last-success-sha); then
  fail_stage last-success read-failed
fi
if [ -n "$last_success" ] && [[ ! "$last_success" =~ ^[0-9a-f]{40}$ ]]; then
  fail_stage last-success malformed-record
fi

if [ "$observed_sha" = "$last_success" ]; then
  write_receipt complete UNCHANGED run_outcome=not-launched
  printf 'UNCHANGED %s %s\n' "$day" "$observed_sha"
  exit 0
fi

if [ "$mode" = production ]; then
  if [ -z "$identity" ]; then
    missing_creds=()
    [ -n "${DAILY_AMARU_APP_ID:-}" ] || missing_creds+=(DAILY_AMARU_APP_ID)
    [ -n "${DAILY_AMARU_APP_PRIVATE_KEY:-}" ] || missing_creds+=(DAILY_AMARU_APP_PRIVATE_KEY)
    if [ "${#missing_creds[@]}" -gt 0 ]; then
      fail_stage identity "missing-credentials-$(IFS=,; printf '%s' "${missing_creds[*]}")"
    fi
    fail_stage identity missing-production-identity
  fi
else
  identity=dry-run
fi
# Process environment only: never a command-line argument any process can read.
export DAILY_AMARU_IDENTITY=$identity

if ! transport_call claim-sha-attempt "$observed_sha"; then
  fail_stage launch-attempt sha-already-attempted
fi
write_receipt launch-attempt CLAIMED

bootstrap_sha=''
if ! bootstrap_sha=$(transport_call propose-bootstrap "$observed_sha"); then
  fail_stage bootstrap-proposal proposal-failed
fi
[[ "$bootstrap_sha" =~ ^[0-9a-f]{40}$ ]] ||
  fail_stage bootstrap-proposal malformed-candidate-sha
receipt[bootstrap_candidate_sha]=$bootstrap_sha
write_receipt bootstrap-proposal PROVISIONAL

if ! transport_call require-bootstrap-checks "$bootstrap_sha" >/dev/null; then
  fail_stage bootstrap-checks exact-head-checks-failed
fi
write_receipt bootstrap-checks VERIFIED

image_ref=''
if ! image_ref=$(transport_call resolve-image "$bootstrap_sha"); then
  fail_stage image-resolution resolution-failed
fi
[[ "$image_ref" =~ ^ghcr\.io/lambdasistemi/amaru-bootstrap-producer:[0-9a-f]{40}@sha256:[0-9a-f]{64}$ ]] ||
  fail_stage image-resolution malformed-tag-or-digest
receipt[image_ref]=$image_ref
write_receipt image-resolution VERIFIED

consumer_sha=''
if ! consumer_sha=$(transport_call prepare-consumer-repin "$image_ref"); then
  fail_stage consumer-repin preparation-failed
fi
[[ "$consumer_sha" =~ ^[0-9a-f]{40}$ ]] ||
  fail_stage consumer-repin malformed-candidate-sha
receipt[consumer_candidate_sha]=$consumer_sha
write_receipt consumer-repin PROVISIONAL

checks_output=''
if ! checks_output=$(transport_call require-consumer-checks "$consumer_sha"); then
  fail_stage consumer-checks query-failed
fi
mapfile -t check_rows < <(printf '%s\n' "$checks_output" | sed '/^$/d')
required_checks=(
  'Build and push component images for cardano-node testnet|publish-images'
  'Build and push component images for cardano-node testnet|Compose smoke test'
  'tracer-sidecar CI|Build'
  'tracer-sidecar CI|Run unit Tests'
  'tracer-sidecar CI|Check code quality'
  'Build documentation|build-docs'
  'PR preview|preview'
)

for required in "${required_checks[@]}"; do
  required_workflow=${required%%|*}
  required_name=${required#*|}
  match_count=0
  valid_count=0
  for row in "${check_rows[@]}"; do
    workflow=''
    check_name=''
    check_head=''
    conclusion=''
    row_extra=''
    IFS='|' read -r workflow check_name check_head conclusion row_extra <<<"$row"
    [ -z "$row_extra" ] || continue
    if [ "$workflow" = "$required_workflow" ] && [ "$check_name" = "$required_name" ]; then
      match_count=$((match_count + 1))
      if [ "$check_head" = "$consumer_sha" ] && [ "$conclusion" = success ]; then
        valid_count=$((valid_count + 1))
      fi
    fi
  done
  if [ "$match_count" -ne 1 ] || [ "$valid_count" -ne 1 ]; then
    fail_stage consumer-checks "invalid-${required_name// /-}"
  fi
done
receipt[check_evidence]="${#required_checks[@]} exact-head successful checks"
write_receipt consumer-checks VERIFIED

producer_evidence=''
if ! producer_evidence=$(transport_call run-producer-check "$consumer_sha"); then
  fail_stage producer-check command-failed
fi
producer_count=''
producer_pin=''
if [[ "$producer_evidence" =~ ^OK:\ ([1-9][0-9]*)\ producer-image\ reference\(s\),\ all\ pinned\ to\ (.+)$ ]]; then
  producer_count=${BASH_REMATCH[1]}
  producer_pin=${BASH_REMATCH[2]}
fi
[ -n "$producer_count" ] || fail_stage producer-check non-positive-census
[ "$producer_pin" = "$image_ref" ] || fail_stage producer-check wrong-image-census
receipt[producer_count]=$producer_count
receipt[producer_evidence]=$producer_evidence
write_receipt producer-check VERIFIED

integrated_sha=''
if ! integrated_sha=$(transport_call await-supervised-integration "$consumer_sha"); then
  fail_stage supervised-integration not-integrated
fi
[[ "$integrated_sha" =~ ^[0-9a-f]{40}$ ]] ||
  fail_stage supervised-integration malformed-integrated-sha
receipt[consumer_integrated_sha]=$integrated_sha
write_receipt supervised-integration VERIFIED

launch_operation=fake-launch
if [ "$mode" = production ]; then
  launch_operation=real-launch
fi

launch_request=''
if ! launch_request=$(transport_call "$launch_operation" \
  cardano-node.yaml cardano_amaru duration=1 no-faults=false "$integrated_sha"); then
  fail_stage launch submission-failed
fi

receipt[launch_workflow]=cardano-node.yaml
receipt[launch_test]=cardano_amaru
receipt[launch_duration]=1
receipt[launch_no_faults]=false
receipt[launch_request]=$launch_request
receipt[moog_request]=$launch_request
write_receipt complete CHANGED run_outcome=requested
printf 'CHANGED %s %s launch=%s\n' "$day" "$observed_sha" "$launch_request"
