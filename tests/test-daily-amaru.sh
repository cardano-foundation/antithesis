#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
controller="$repo_root/scripts/daily-amaru.sh"
fake_transport="$repo_root/tests/fixtures/daily-amaru/fake-transport.sh"
tmp_root=$(mktemp -d)
trap 'rm -rf "$tmp_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

pass() {
  printf 'PASS %s\n' "$1"
}

assert_file_contains() {
  local file=$1
  local literal=$2
  grep -Fqx -- "$literal" "$file" ||
    fail "$file does not contain exact line: $literal"
}

assert_file_lacks() {
  local file=$1
  local pattern=$2
  if grep -Eq -- "$pattern" "$file"; then
    fail "$file unexpectedly matches: $pattern"
  fi
}

assert_log_count() {
  local expected=$1
  local pattern=$2
  local actual
  actual=$(grep -Ec -- "$pattern" "$case_log" || true)
  [ "$actual" -eq "$expected" ] ||
    fail "scenario=$case_name expected $expected log matches for $pattern, found $actual"
}

assert_no_launch() {
  assert_log_count 0 '^(fake-launch|real-launch) '
}

assert_no_mutation() {
  assert_log_count 0 '^mutation:'
}

assert_honest_failure_receipt() {
  local stage=$1
  assert_file_contains "$case_receipt" "stage=$stage"
  assert_file_contains "$case_receipt" 'outcome=FAILED'
  assert_file_lacks "$case_receipt" 'outcome=(UNCHANGED|CHANGED|SUCCESS)|run_outcome=success|findings_complete=true'
}

case_number=0
run_case() {
  case_name=$1
  local mode=${2:-test}
  local identity=${3-test-identity}
  case_number=$((case_number + 1))
  case_dir="$tmp_root/$case_number-$case_name"
  case_state="$case_dir/state"
  case_log="$case_dir/transport.log"
  case_receipt="$case_dir/receipt"
  case_stdout="$case_dir/stdout"
  case_stderr="$case_dir/stderr"
  mkdir -p "$case_state"
  : >"$case_log"

  if [ "$case_name" = duplicate-same-day ]; then
    printf '2026-07-31-existing-claim\n' >"$case_state/day-claim"
  fi
  if [ "$case_name" = same-sha-retry ]; then
    printf '1111111111111111111111111111111111111111\n' >"$case_state/attempted-sha"
  fi

  case_rc=0
  env \
    FAKE_SCENARIO="$case_name" \
    FAKE_LOG="$case_log" \
    DAILY_AMARU_TRANSPORT="$fake_transport" \
    DAILY_AMARU_MODE="$mode" \
    DAILY_AMARU_DAY=2026-07-31 \
    DAILY_AMARU_IDENTITY="$identity" \
    DAILY_AMARU_STATE_DIR="$case_state" \
    DAILY_AMARU_RECEIPT="$case_receipt" \
    DAILY_AMARU_ALLOW_REAL=1 \
    "$controller" >"$case_stdout" 2>"$case_stderr" || case_rc=$?
}

require_success() {
  [ "$case_rc" -eq 0 ] ||
    fail "scenario=$case_name expected success, exit=$case_rc: $(tr '\n' ' ' <"$case_stderr")"
}

require_failure() {
  [ "$case_rc" -ne 0 ] || fail "scenario=$case_name expected failure"
}

if [ ! -x "$fake_transport" ]; then
  fail "fake transport is absent or not executable: $fake_transport"
fi

# Intentional first RED: the deterministic transport exists, but production
# behavior does not. No PASS line may be emitted before this check flips.
if [ ! -x "$controller" ]; then
  fail "controller behavior absent: expected executable $controller"
fi

run_case changed
require_success
assert_file_contains "$case_receipt" 'outcome=CHANGED'
assert_file_contains "$case_receipt" 'upstream_sha=1111111111111111111111111111111111111111'
assert_log_count 1 '^resolve-upstream '
assert_log_count 1 '^claim-sha-attempt '
assert_log_count 1 '^fake-launch cardano-node.yaml cardano_amaru duration=1 no-faults=false 4444444444444444444444444444444444444444$'
assert_log_count 0 '^real-launch '
pass changed

run_case unchanged
require_success
assert_file_contains "$case_receipt" 'outcome=UNCHANGED'
assert_no_mutation
assert_no_launch
pass unchanged

for observation in zero-observation ambiguous-observation; do
  run_case "$observation"
  require_failure
  assert_no_mutation
  assert_no_launch
  assert_honest_failure_receipt resolve-upstream
  pass "$observation"
done

run_case missing-identity production ''
require_failure
assert_log_count 0 '^claim-sha-attempt '
assert_no_mutation
assert_no_launch
assert_honest_failure_receipt identity
pass missing-identity

for check_case in missing-check wrong-head-check ambiguous-check pending-check failed-check; do
  run_case "$check_case"
  require_failure
  assert_log_count 0 '^await-supervised-integration '
  assert_no_launch
  assert_honest_failure_receipt consumer-checks
  pass "$check_case"
done

run_case '#202-failure'
require_failure
assert_log_count 0 '^await-supervised-integration '
assert_no_launch
assert_honest_failure_receipt producer-check
pass '#202-failure'

run_case '#202-zero'
require_failure
assert_log_count 0 '^await-supervised-integration '
assert_no_launch
assert_honest_failure_receipt producer-check
pass '#202-zero'

run_case duplicate-same-day
require_failure
assert_file_contains "$case_state/day-claim" '2026-07-31-existing-claim'
assert_log_count 0 '^resolve-upstream '
assert_no_mutation
assert_no_launch
assert_honest_failure_receipt day-claim
pass duplicate-same-day

run_case same-sha-retry
require_failure
assert_file_contains "$case_state/attempted-sha" '1111111111111111111111111111111111111111'
assert_no_mutation
assert_no_launch
assert_honest_failure_receipt launch-attempt
pass same-sha-retry

run_case failed-stage
require_failure
assert_log_count 1 '^mutation:bootstrap '
assert_log_count 0 '^mutation:(image|repin) '
assert_no_launch
assert_honest_failure_receipt bootstrap-proposal
pass failed-stage

run_case changed manual ''
require_success
assert_log_count 1 '^fake-launch '
assert_log_count 0 '^real-launch '
pass manual-fake-only

run_case changed pull_request test-identity
require_success
assert_log_count 1 '^fake-launch '
assert_log_count 0 '^real-launch '
pass real-launcher-blocked

run_case changed test test-identity
require_success
assert_log_count 1 '^fake-launch cardano-node.yaml cardano_amaru duration=1 no-faults=false 4444444444444444444444444444444444444444$'
assert_log_count 0 '^real-launch '
assert_file_contains "$case_receipt" 'producer_count=3'
assert_file_contains "$case_receipt" 'launch_workflow=cardano-node.yaml'
assert_file_contains "$case_receipt" 'launch_test=cardano_amaru'
assert_file_contains "$case_receipt" 'launch_duration=1'
assert_file_contains "$case_receipt" 'launch_no_faults=false'
pass complete-fake-launch-once

assert_log_count 1 '^await-supervised-integration '
assert_log_count 0 'merge'
pass supervised-no-self-merge

for observation in malformed-observation wrong-origin-observation wrong-ref-observation; do
  run_case "$observation"
  require_failure
  assert_no_mutation
  assert_no_launch
  assert_honest_failure_receipt resolve-upstream
  pass "$observation"
done
