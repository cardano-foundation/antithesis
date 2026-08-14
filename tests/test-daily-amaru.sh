#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
controller="$repo_root/scripts/daily-amaru.sh"
transport="$repo_root/scripts/daily-amaru-github.sh"
workflow="$repo_root/.github/workflows/daily-amaru.yaml"
fake_transport="$repo_root/tests/fixtures/daily-amaru/fake-transport.sh"
fake_gh="$repo_root/tests/fixtures/daily-amaru/fake-gh.sh"
tmp_root=$(mktemp -d)
trap 'rm -rf "$tmp_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

pass() {
  printf 'PASS %s\n' "$1"
}

count_matches() {
  grep -Ec -- "$2" "$1" || true
}

count_literal() {
  grep -Fc -- "$2" "$1" || true
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
  actual=$(count_matches "$case_log" "$pattern")
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

assert_workflow_literal_once() {
  local literal=$1 actual
  actual=$(count_literal "$workflow" "$literal")
  [ "$actual" -eq 1 ] ||
    fail "workflow must declare exactly once (found $actual): $literal"
}

# D213-01, exercised in both directions before any verdict it gives is believed.
receipt_oracle() {
  local receipt=$1 day=$2 stage=$3 error=$4 effects=$5
  local field forbidden

  [ -f "$receipt" ] && [ ! -L "$receipt" ] && [ -s "$receipt" ] && [ -f "$effects" ] ||
    return 1
  for field in "day=$day" "stage=$stage" 'outcome=FAILED' "error=$error"; do
    grep -Fqx -- "$field" "$receipt" || return 1
  done
  if grep -Eq '^(outcome=(UNCHANGED|CHANGED|SUCCESS)|run_outcome=(success|requested))$' \
    "$receipt"; then
    return 1
  fi
  for forbidden in 'repo clone' 'pr create' 'pr merge' 'workflow run' 'run watch'; do
    if grep -Fq -- "$forbidden" "$effects"; then
      return 1
    fi
  done
  return 0
}

# An exclusive PATH makes a missing-command verdict caused by absence.
scheduled_seed_commands=(
  bash dirname mkdir git jq sed awk grep tail tr head seq sleep date docker nix
)

stub_command() {
  printf '#!/bin/sh\nexit 0\n' >"$1"
  chmod +x "$1"
}

seed_scheduled_path() {
  local bin_dir=$1 include_rg=$2
  local command target
  mkdir -p "$bin_dir"
  for command in "${scheduled_seed_commands[@]}"; do
    if target=$(command -v "$command" 2>/dev/null) &&
      [ "${target:0:1}" = / ] && [ -x "$target" ]; then
      ln -sf "$target" "$bin_dir/$command"
    else
      stub_command "$bin_dir/$command"
    fi
  done
  ln -sf "$fake_gh" "$bin_dir/gh"
  if [ "$include_rg" = with-rg ]; then
    stub_command "$bin_dir/rg"
  else
    rm -f "$bin_dir/rg"
  fi
  # Positive control: a PATH resolving nothing would report everything missing.
  PATH="$bin_dir" command -v gh >/dev/null ||
    fail "seeded PATH cannot resolve a command that is present: $bin_dir"
  if [ "$include_rg" = without-rg ] &&
    PATH="$bin_dir" command -v rg >/dev/null 2>&1; then
    fail "seeded PATH still resolves rg: $bin_dir"
  fi
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

bash_binary=$(command -v bash)

# One hermetic production-transport run. `omit` is the single command removed
# from an otherwise complete seeded PATH, or empty to seed nothing at all. An
# absolute interpreter keeps even an empty PATH reaching the first boundary.
run_hermetic_case() {
  local label=$1 omit=$2 day=$3 script=${4:-$controller} parent=${5:-existing}
  local day_env=(DAILY_AMARU_DAY="$day")
  hermetic_dir="$tmp_root/hermetic-$label"
  hermetic_state="$hermetic_dir/state"
  # Production nests the receipt under a directory no step pre-creates, so the
  # absent-parent class must be reachable without the harness building it.
  [ "$parent" = existing ] || hermetic_state="$hermetic_dir/never-created/state"
  hermetic_receipt="$hermetic_state/receipt"
  hermetic_effects="$hermetic_dir/effects"
  # An unset day is the production shape: the controller, not the workflow,
  # must derive the UTC day, so `date` becomes a first-boundary requirement.
  [ -n "$day" ] || day_env=()
  mkdir -p "$hermetic_dir/bin"
  if [ "$parent" = existing ]; then
    mkdir -p "$hermetic_state"
  fi
  : >"$hermetic_effects"
  if [ -n "$omit" ]; then
    seed_scheduled_path "$hermetic_dir/bin" with-rg
    rm -f "$hermetic_dir/bin/$omit"
    if PATH="$hermetic_dir/bin" command -v "$omit" >/dev/null 2>&1; then
      fail "hermetic omission did not apply: $omit"
    fi
  fi
  hermetic_rc=0
  env \
    PATH="$hermetic_dir/bin" \
    DAILY_AMARU_FAKE_GH_LOG="$hermetic_effects" \
    DAILY_AMARU_EFFECT_LOG="$hermetic_effects" \
    DAILY_AMARU_MODE=production \
    "${day_env[@]}" \
    DAILY_AMARU_IDENTITY=seed-non-empty-identity \
    DAILY_AMARU_STATE_DIR="$hermetic_state" \
    DAILY_AMARU_RECEIPT="$hermetic_receipt" \
    "$bash_binary" "$script" \
    >"$hermetic_dir/stdout" 2>"$hermetic_dir/stderr" || hermetic_rc=$?
}

# The primary receipt is authoritative while it is writable; an unreachable
# primary must not erase the machine-readable failure, so the durable runner
# stream is read exactly as the scheduled job would read it.
hermetic_sink() {
  hermetic_sink_kind=primary
  hermetic_sink_path="$hermetic_dir/sink"
  if [ -f "$hermetic_receipt" ]; then
    cp "$hermetic_receipt" "$hermetic_sink_path"
  else
    hermetic_sink_kind=independent
    cat "$hermetic_dir/stdout" "$hermetic_dir/stderr" >"$hermetic_sink_path"
  fi
}

run_transport_preflight() {
  local bin_dir=$1 root=$2 label=$3
  shift 3
  preflight_rc=0
  preflight_stdout=$root/$label.stdout
  preflight_stderr=$root/$label.stderr
  env \
    PATH="$bin_dir" \
    DAILY_AMARU_FAKE_GH_LOG="$root/effects" \
    DAILY_AMARU_STATE_DIR="$root/state" \
    DAILY_AMARU_RECEIPT="$root/state/receipt" \
    "$transport" preflight "$@" \
    >"$preflight_stdout" 2>"$preflight_stderr" || preflight_rc=$?
}

transport_branch() {
  local file=$1 operation=$2
  awk -v op="$operation" '
    $0 == "  " op ")" { inside = 1; next }
    inside && $0 == "    ;;" { inside = 0 }
    inside { print }
  ' "$file"
}

bootstrap_boundary_operations=(propose-bootstrap require-bootstrap-checks)
repository_boundary_operations=(
  claim-day last-success-sha claim-sha-attempt prepare-consumer-repin
  require-consumer-checks await-supervised-integration real-launch receipt
)

# INV-213-03: the minted token must be unreachable from every same-repository
# operation, and bootstrap operations must not fall back to the repository one.
identity_boundary_holds() {
  local file=$1
  local operation body
  for operation in "${bootstrap_boundary_operations[@]}"; do
    body=$(transport_branch "$file" "$operation")
    [ -n "$body" ] || return 1
    grep -q 'bootstrap_identity' <<<"$body" || return 1
    ! grep -q 'repository_identity' <<<"$body" || return 1
  done
  for operation in "${repository_boundary_operations[@]}"; do
    body=$(transport_branch "$file" "$operation")
    [ -n "$body" ] || return 1
    ! grep -q 'bootstrap_identity\|DAILY_AMARU_IDENTITY' <<<"$body" || return 1
  done
  return 0
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

if [ ! -x "$fake_gh" ]; then
  fail "fake gh is absent or not executable: $fake_gh"
fi

# Intentional first RED: the deterministic transport exists, but production
# behavior does not. No PASS line may be emitted before this check flips.
if [ ! -x "$controller" ]; then
  fail "controller behavior absent: expected executable $controller"
fi

if [ ! -x "$transport" ]; then
  fail "production transport absent: expected executable $transport"
fi

if [ ! -f "$workflow" ]; then
  fail "scheduled workflow absent: expected regular file $workflow"
fi

oracle_root="$tmp_root/receipt-oracle"
mkdir -p "$oracle_root"
: >"$oracle_root/clean-effects"
printf 'gh repo clone lambdasistemi/amaru-bootstrap\n' >"$oracle_root/dirty-effects"
printf 'day=2026-08-02\nstage=runner-preflight\noutcome=FAILED\nerror=missing-command-rg\n' \
  >"$oracle_root/valid"
printf 'day=2026-08-02\nstage=runner-preflight\noutcome=FAILED\n' >"$oracle_root/no-error"
printf 'day=2026-08-02\nstage=runner-preflight\noutcome=CHANGED\nerror=missing-command-rg\n' \
  >"$oracle_root/success-like"
# receipt|effects|expected|description
for control in \
  'valid|clean-effects|accept|its positive control' \
  'no-error|clean-effects|reject|a missing specific error' \
  'success-like|clean-effects|reject|a success-like outcome' \
  'absent|clean-effects|reject|silence' \
  'valid|dirty-effects|reject|a reached business effect'
do
  IFS='|' read -r control_receipt control_effects control_expect control_what \
    <<<"$control"
  control_rc=0
  receipt_oracle "$oracle_root/$control_receipt" 2026-08-02 runner-preflight \
    missing-command-rg "$oracle_root/$control_effects" || control_rc=$?
  if [ "$control_expect" = accept ]; then
    [ "$control_rc" -eq 0 ] || fail "receipt oracle rejected $control_what"
  else
    [ "$control_rc" -ne 0 ] || fail "receipt oracle accepted $control_what"
  fi
done
printf 'RECEIPT-ORACLE-CONTROLS positive=1 negative=4\n'
pass receipt-oracle-controls

preflight_root="$tmp_root/preflight-controls"
mkdir -p "$preflight_root/state"
: >"$preflight_root/effects"
seed_scheduled_path "$preflight_root/complete" with-rg
seed_scheduled_path "$preflight_root/incomplete" without-rg
run_transport_preflight "$preflight_root/complete" "$preflight_root" complete
[ "$preflight_rc" -eq 0 ] ||
  fail "complete dependency census was rejected: $(tr '\n' ' ' <"$preflight_stderr")"
census_evidence=$(cat "$preflight_stdout")
[[ "$census_evidence" =~ ^OK:\ ([1-9][0-9]*)\ scheduled\ dependencies\ present:\ (.+)$ ]] ||
  fail "preflight success evidence does not name the census: $census_evidence"
census_count=${BASH_REMATCH[1]}
census_list=${BASH_REMATCH[2]}
[ "$census_count" -eq "$(wc -w <<<"$census_list")" ] ||
  fail "declared census count $census_count differs from the named commands"
[[ " $census_list " == *" rg "* ]] ||
  fail "dependency census omits the incident command rg: $census_list"
# Absent `rg`, then an absent explicit requirement: the verdict must belong to a
# property class, not to the single `rg` instance.
for absent in rg t213-absent-probe; do
  if [ "$absent" = rg ]; then
    run_transport_preflight "$preflight_root/incomplete" "$preflight_root" "$absent"
    grep -Fqx 'MISSING-COMMAND rg' "$preflight_stdout" ||
      fail 'preflight did not report the missing command machine-readably'
  else
    run_transport_preflight "$preflight_root/complete" "$preflight_root" "$absent" "$absent"
  fi
  [ "$preflight_rc" -ne 0 ] || fail "preflight accepted an absent command: $absent"
  grep -Fqx "daily-amaru-github: missing command: $absent" "$preflight_stderr" ||
    fail "preflight did not name the absent command: $absent"
done
[ -f "$preflight_root/effects" ] && [ ! -s "$preflight_root/effects" ] ||
  fail 'dependency preflight reached a GitHub effect, or its log vanished'
printf 'DEPENDENCY-CENSUS count=%s rg=required effects=0\n' "$census_count"
pass scheduled-preflight-controls

# F1: the transport preflight cannot classify the commands needed to reach the
# transport itself. The census is read from the controller source, so a later
# addition to it is covered here automatically.
# Both the unconditional assignment and every conditional append, so a member
# the controller only sometimes requires cannot escape the census claim.
mapfile -t bootstrap_census < <(
  sed -nE 's/.*bootstrap_command_census\+?=\((.+)\).*/\1/p' "$controller" |
    tr ' ' '\n' | sed '/^$/d'
)
[ "${#bootstrap_census[@]}" -ge 1 ] ||
  fail 'controller declares no bootstrap command census'
# With nothing reachable, anything executing before the boundary would crash
# instead of classifying, so the first census member must be the verdict.
run_hermetic_case empty-path '' 2026-08-02
[ "$hermetic_rc" -ne 0 ] ||
  fail 'controller accepted a runner with no external command at all'
receipt_oracle "$hermetic_receipt" 2026-08-02 runner-preflight \
  "missing-command-${bootstrap_census[0]}" "$hermetic_effects" ||
  fail 'empty-PATH control produced no classified durable receipt'
[ ! -s "$hermetic_effects" ] ||
  fail 'empty-PATH control reached a GitHub effect'
# Every effective census member, over both production receipt-parent states.
# `date` is only required when nothing pre-computes the day, so it is exercised
# in exactly the shape that makes it a first-boundary requirement.
boundary_sink_kinds=()
for omitted in "${bootstrap_census[@]}"; do
  for parent in existing absent; do
    boundary_day=2026-08-02
    [ "$omitted" != date ] || boundary_day=''
    run_hermetic_case "omit-$omitted-$parent" "$omitted" "$boundary_day" \
      "$controller" "$parent"
    [ "$hermetic_rc" -ne 0 ] ||
      fail "controller accepted a runner without $omitted (parent=$parent)"
    grep -Fqx "daily-amaru: missing command: $omitted" "$hermetic_dir/stderr" ||
      fail "absent $omitted was not named on stderr (parent=$parent)"
    hermetic_sink
    boundary_expected_day=$boundary_day
    if [ -z "$boundary_expected_day" ]; then
      boundary_expected_day=$(
        sed -nE 's/^day=([0-9]{4}-[0-9]{2}-[0-9]{2})$/\1/p' "$hermetic_sink_path" |
          head -1
      )
      [ -n "$boundary_expected_day" ] ||
        fail "absent $omitted left no valid UTC day in the sink (parent=$parent)"
    fi
    receipt_oracle "$hermetic_sink_path" "$boundary_expected_day" \
      runner-preflight "missing-command-$omitted" "$hermetic_effects" ||
      fail "absent $omitted (parent=$parent) left no classified durable sink"
    [ ! -s "$hermetic_effects" ] ||
      fail "absent $omitted (parent=$parent) reached a GitHub effect"
    boundary_sink_kinds+=("$hermetic_sink_kind")
  done
done
# Both sink paths must actually occur: a harness that pre-created every parent
# would report the absent class green while never leaving the primary receipt.
[[ " ${boundary_sink_kinds[*]} " == *" primary "* ]] ||
  fail 'no first-boundary case reached the authoritative primary receipt'
[[ " ${boundary_sink_kinds[*]} " == *" independent "* ]] ||
  fail 'no first-boundary case exercised the independent durable sink'
# Negative control for the independent sink: a controller that can only write
# the primary receipt loses the verdict exactly when its parent is absent.
sinkless_mutant="$tmp_root/controller-sinkless.sh"
sed 's|^  publish_independent_receipt$|  : suppressed-independent-sink|' \
  "$controller" >"$sinkless_mutant"
grep -Fq ': suppressed-independent-sink' "$sinkless_mutant" ||
  fail 'independent-sink mutation did not apply'
run_hermetic_case sinkless-mutant mkdir 2026-08-02 "$sinkless_mutant" absent
hermetic_sink
if receipt_oracle "$hermetic_sink_path" 2026-08-02 runner-preflight \
  missing-command-mkdir "$hermetic_effects"; then
  fail 'a controller with no independent sink still published the failure'
fi
# Prove the control can fail: an empty boundary crashes instead of classifying.
bootstrap_mutant="$tmp_root/controller-unguarded.sh"
sed -E 's/^bootstrap_command_census=\(.*\)$/bootstrap_command_census=()/' \
  "$controller" >"$bootstrap_mutant"
grep -Fqx 'bootstrap_command_census=()' "$bootstrap_mutant" ||
  fail 'bootstrap-census mutation did not apply'
run_hermetic_case unguarded-mutant '' 2026-08-02 "$bootstrap_mutant"
if receipt_oracle "$hermetic_receipt" 2026-08-02 runner-preflight \
  "missing-command-${bootstrap_census[0]}" "$hermetic_effects"; then
  fail 'a controller without a bootstrap boundary still classified the failure'
fi
printf 'BOOTSTRAP-BOUNDARY census=%s members=%s empty_path_control=1 mutants_rejected=2\n' \
  "${#bootstrap_census[@]}" "${bootstrap_census[*]}"
printf 'FIRST-BOUNDARY-CONTROLS commands=%s parent_modes=existing,absent effects=0\n' \
  "$(IFS=,; printf '%s' "${bootstrap_census[*]}")"
pass bootstrap-command-boundary

scheduled_effect_logs=()
for incident_day in 2026-08-02 2026-08-03; do
  run_hermetic_case "incident-$incident_day" rg "$incident_day"
  [ "$hermetic_rc" -ne 0 ] ||
    fail "scenario=scheduled-$incident_day expected a non-zero scheduled exit"
  grep -Fqx 'daily-amaru-github: missing command: rg' "$hermetic_dir/stderr" ||
    fail "scenario=scheduled-$incident_day lacks the exact incident fingerprint"
  receipt_oracle "$hermetic_receipt" "$incident_day" runner-preflight \
    missing-command-rg "$hermetic_effects" ||
    fail "scenario=scheduled-$incident_day lacks a loud durable failure receipt"
  # A broken runner must not even consume the UTC day.
  if grep -Fq "daily-amaru day=$incident_day claim" "$hermetic_effects"; then
    fail "scenario=scheduled-$incident_day claimed the UTC day behind a broken runner"
  fi
  scheduled_effect_logs+=("$hermetic_effects")
  printf 'INCIDENT day=%s base=311dfc1 fingerprint=%s exit=%s business_effects=0\n' \
    "$incident_day" 'daily-amaru-github: missing command: rg' "$hermetic_rc"
  pass "scheduled-missing-rg-$incident_day"
done

run_case changed
require_success
assert_file_contains "$case_receipt" 'outcome=CHANGED'
assert_file_contains "$case_receipt" 'upstream_sha=1111111111111111111111111111111111111111'
assert_log_count 1 '^preflight'
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
assert_file_contains "$case_receipt" 'day=2026-07-31'
assert_file_contains "$case_receipt" 'error=missing-production-identity'
identity_control_log=$case_log
pass missing-identity

# A reported missing command, silence, and an unparsable success all become
# stage=runner-preflight before the day is claimed. INV-213-01, INV-213-02.
for broken in missing-tool silent-preflight malformed-preflight; do
  run_case "$broken" production seed-non-empty-identity
  require_failure
  assert_log_count 0 '^claim-day '
  assert_log_count 0 '^claim-sha-attempt '
  assert_no_mutation
  assert_no_launch
  assert_honest_failure_receipt runner-preflight
  assert_file_contains "$case_receipt" 'day=2026-07-31'
  if [ "$broken" = missing-tool ]; then
    assert_file_contains "$case_receipt" 'error=missing-command-rg'
    tool_control_log=$case_log
  else
    assert_file_contains "$case_receipt" 'error=malformed-dependency-evidence'
  fi
  pass "$broken"
done

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
assert_file_contains "$case_receipt" 'dependency_census=OK: 15 scheduled dependencies present: gh git jq rg sed awk grep tail tr head seq sleep date docker nix'
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
# INV-213-06 over both broken preconditions.
for broken_log in "${scheduled_effect_logs[@]}"; do
  for forbidden in 'repo clone' 'pr create' 'pr merge' 'workflow run' 'run watch'; do
    if grep -Fq -- "$forbidden" "$broken_log"; then
      fail "missing-command control reached a business effect: $forbidden"
    fi
  done
done
for broken_log in "$tool_control_log" "$identity_control_log"; do
  for pattern in '^claim-sha-attempt ' '^mutation:' \
    '^await-supervised-integration ' '^fake-launch ' '^real-launch '; do
    actual=$(count_matches "$broken_log" "$pattern")
    [ "$actual" -eq 0 ] ||
      fail "broken precondition reached $actual effects matching $pattern"
  done
done
printf 'EFFECT-CENSUS controls=2 attempts=0 mutations=0 integrations=0 fake_launches=0 real_launches=0\n'
pass broken-preconditions-no-business-effects

# The `${{ ... }}` sequences below are GitHub Actions expressions matched as
# literal workflow text; expanding them here would defeat the assertion.
# shellcheck disable=SC2016
for literal in \
  'uses: actions/create-github-app-token@v1' \
  'app-id: ${{ vars.DAILY_AMARU_APP_ID }}' \
  'private-key: ${{ secrets.DAILY_AMARU_APP_PRIVATE_KEY }}' \
  'owner: lambdasistemi' \
  'repositories: amaru-bootstrap' \
  'permission-actions: read' \
  'permission-checks: read' \
  'permission-contents: write' \
  'permission-pull-requests: write' \
  'permission-metadata: read'
do
  assert_workflow_literal_once "$literal"
done
app_permissions=$(count_matches "$workflow" '^[[:space:]]*permission-[a-z-]+:')
[ "$app_permissions" -eq 5 ] ||
  fail "bootstrap App permission census must be exactly five, found $app_permissions"
identity_boundary_holds "$transport" ||
  fail 'the minted bootstrap identity is not confined to the bootstrap boundary'

mutant_root="$tmp_root/mutants"
mkdir -p "$mutant_root"
# Each mutant verifies its own application; `applied` with a `!` means absence.
reject_mutant() {
  local label=$1 source=$2 script=$3 applied=$4 why=$5
  shift 5
  local mutant="$mutant_root/$label"
  sed "$script" "$source" >"$mutant"
  if [ "${applied:0:1}" = '!' ]; then
    ! grep -Fq -- "${applied:1}" "$mutant" || fail "mutation did not apply: $label"
  else
    grep -Fq -- "$applied" "$mutant" || fail "mutation did not apply: $label"
  fi
  if "$@" "$mutant"; then
    fail "check accepted $why"
  fi
}
# shellcheck disable=SC2016
reject_mutant leaked.sh "$transport" \
  's#^  receipt)$#  receipt)\n    leak="$bootstrap_identity"#' \
  'leak="$bootstrap_identity"' \
  'a bootstrap identity inside a repository operation' identity_boundary_holds
reject_mutant downgraded.sh "$transport" 's#bootstrap_identity#repository_identity#g' \
  '!bootstrap_identity' \
  'a bootstrap operation without the minted identity' identity_boundary_holds
printf 'IDENTITY-BOUNDARY bootstrap_ops=%s repository_ops=%s mutants_rejected=2\n' \
  "${#bootstrap_boundary_operations[@]}" "${#repository_boundary_operations[@]}"
pass dedicated-app-scope

# INV-213-05: bound exactly once, nowhere else, and never persisted.
for forbidden in DAILY_AMARU_CROSS_REPO_TOKEN MOOG_GITHUB_PAT GITHUB_ENV; do
  if grep -Fq -- "$forbidden" "$workflow" "$controller" "$transport"; then
    fail "forbidden credential path remains: $forbidden"
  fi
done
# shellcheck disable=SC2016
assert_workflow_literal_once 'DAILY_AMARU_IDENTITY: ${{ steps.app-token.outputs.token }}'
# shellcheck disable=SC2016
assert_workflow_literal_once '${{ steps.app-token.outputs.token }}'
secret_value=t213-bootstrap-secret-token-value
run_case failed-stage production "$secret_value"
require_failure
assert_log_count 1 '^mutation:bootstrap '
assert_no_launch
assert_honest_failure_receipt bootstrap-proposal
leaked_artifacts=0
scanned_artifacts=0
while IFS= read -r artifact; do
  scanned_artifacts=$((scanned_artifacts + 1))
  if grep -Fq -- "$secret_value" "$artifact"; then
    printf 'LEAK %s\n' "$artifact" >&2
    leaked_artifacts=$((leaked_artifacts + 1))
  fi
done < <(find "$case_dir" -type f)
[ "$scanned_artifacts" -gt 0 ] ||
  fail 'secret persistence scan inspected no artifact at all'
[ "$leaked_artifacts" -eq 0 ] ||
  fail "minted bootstrap identity persisted into $leaked_artifacts artifact(s)"
# Positive control: the zero above must be absence, not a broken instrument.
printf '%s\n' "$secret_value" >"$case_dir/leak-probe"
grep -Fq -- "$secret_value" "$case_dir/leak-probe" ||
  fail 'leak search cannot detect a known-present secret'
printf 'SECRET-PERSISTENCE artifacts_scanned=%s leaks=0 probe=detected\n' \
  "$scanned_artifacts"
pass bootstrap-token-not-persisted

# F2: separating the identities is not enough — the job must grant the
# repository token what each same-repository operation declares it needs.
job_grants() {
  awk '
    /^  daily-amaru-scheduled:/ { job = 1 }
    job && /^    permissions:/ { block = 1; next }
    block && /^      [a-z-]+:[[:space:]]*[a-z]+[[:space:]]*$/ {
      key = $1; sub(/:$/, "", key); print key "=" $2; next
    }
    block && /^    [^ ]/ { exit }
  ' "$1"
}

permission_rank() {
  case $1 in read) printf 1 ;; write) printf 2 ;; *) printf 0 ;; esac
}

grants_satisfy_transport() {
  local -A granted=()
  local row
  while IFS= read -r row; do
    [ -z "$row" ] || granted[${row%%=*}]=${row#*=}
  done < <(job_grants "$1")
  [ "${#granted[@]}" -gt 0 ] || return 1
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    [ "$(permission_rank "${granted[${row%%=*}]:-none}")" -ge \
      "$(permission_rank "${row#*=}")" ] || return 1
  done < <(
    sed -nE 's/^[[:space:]]*# repository-token-permissions:[[:space:]]*(.*)$/\1/p' "$2" |
      tr ' ' '\n' | sed '/^$/d'
  )
  return 0
}
for operation in "${repository_boundary_operations[@]}"; do
  transport_branch "$transport" "$operation" |
    grep -q '# repository-token-permissions:' ||
    fail "same-repository operation declares no token permission: $operation"
done
grants_satisfy_transport "$workflow" "$transport" ||
  fail 'scheduled job grants do not cover the declared same-repository permissions'
# Both directions of the seam must fail: a downgraded grant, and a newly
# required scope nobody granted.
grants_for_workflow() { grants_satisfy_transport "$1" "$transport"; }
grants_for_transport() { grants_satisfy_transport "$workflow" "$1"; }
reject_mutant downgraded-grant.yaml "$workflow" \
  's/^      contents: write$/      contents: read/' '      contents: read' \
  'a job that cannot perform the consumer push' grants_for_workflow
reject_mutant ungranted-scope.sh "$transport" \
  's/^\([[:space:]]*# repository-token-permissions:\) issues=write$/\1 issues=write packages=write/' \
  'packages=write' 'a required scope the job never granted' grants_for_transport
printf 'TOKEN-GRANTS scopes=%s annotated_operations=%s mutants_rejected=2\n' \
  "$(job_grants "$workflow" | wc -l)" "${#repository_boundary_operations[@]}"
pass repository-token-grants

# F3: counting literals accepts a workflow whose callers are no-ops and whose
# target strings survive in comments. Compare executable command words per job.
workflow_callers() {
  awk '
    /^[[:space:]]*#/ { next }
    /^jobs:[[:space:]]*$/ { jobs = 1; next }
    !jobs { next }
    /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { job = $1; sub(/:$/, "", job); next }
    {
      line = $0
      sub(/^[[:space:]]*-[[:space:]]+/, "", line)
      sub(/^[[:space:]]+/, "", line)
      sub(/^run:[[:space:]]*/, "", line)
      sub(/[[:space:]]+#.*$/, "", line)
      gsub(/^['\''"]|['\''"]$/, "", line)
      if (split(line, word, /[[:space:]]+/) > 0 && word[1] != "") {
        print job "|" word[1]
      }
    }
  ' "$1"
}

wiring_holds() {
  local callers
  callers=$(workflow_callers "$1")
  grep -Fqx 'daily-amaru-dry-run|tests/test-daily-amaru.sh' <<<"$callers" || return 1
  grep -Fqx 'daily-amaru-scheduled|scripts/daily-amaru.sh' <<<"$callers" || return 1
  return 0
}
wiring_holds "$workflow" ||
  fail 'the workflow does not executably call both controller entry points'
assert_workflow_literal_once "if: github.event_name != 'schedule'"
assert_workflow_literal_once "if: github.event_name == 'schedule'"
assert_workflow_literal_once 'DAILY_AMARU_MODE: production'
assert_workflow_literal_once 'uses: actions/upload-artifact@v6'
[ "$(count_literal "$workflow" 'if: always()')" -eq 2 ] ||
  fail 'the scheduled job must always reach both the controller and the publisher'
assert_workflow_literal_once 'continue-on-error: true'
[ "$(count_literal "$workflow" 'ripgrep')" -ge 1 ] ||
  fail 'the scheduled runner does not provision the incident command'
[ "$(count_literal "$workflow" 'setup-nix')" -ge 1 ] ||
  fail 'the scheduled runner does not provision nix for the bootstrap proposal'
# Orphan each caller in turn, leaving the searched literal behind in a comment.
reject_mutant wiring-pull-request.yaml "$workflow" \
  "s|^        run: tests/test-daily-amaru.sh\$|        # run: tests/test-daily-amaru.sh\n        run: 'true'|" \
  "        run: 'true'" 'an orphaned pull-request proof caller' wiring_holds
grep -Fq 'tests/test-daily-amaru.sh' "$mutant_root/wiring-pull-request.yaml" ||
  fail 'pull-request wiring mutant lost the misleading literal'
reject_mutant wiring-scheduled.yaml "$workflow" \
  's|^          scripts/daily-amaru.sh$|          true # scripts/daily-amaru.sh|' \
  '          true # scripts/daily-amaru.sh' \
  'an orphaned scheduled controller caller' wiring_holds
printf 'WIRING pull_request_proof=1 scheduled_controller=1 receipt_upload=1 mutants_rejected=2\n'
pass workflow-wires-scheduled-proof

# A named step's own lines, so a declaration belonging to a neighbouring step
# can never be read as this one's.
workflow_step() {
  awk -v header="      - name: $2" '
    $0 == header { inside = 1 }
    inside && $0 != header && /^      - (name|uses):/ { exit }
    inside { print }
  ' "$1"
}

# INV-213-09: pull-request CI must execute the focused proof from the exact
# candidate head, not from whatever ref the event happens to supply.
pr_head_holds() {
  local checkout
  checkout=$(workflow_step "$1" 'Check out the exact candidate')
  grep -Eq '^          ref: .*github\.event\.pull_request\.head\.sha' \
    <<<"$checkout" || return 1
  wiring_holds "$1"
}

# INV-213-02: the scheduled controller is reached whatever an earlier step did,
# no external date stands before it, and an absent receipt fails the always-run
# publisher instead of warning.
receipt_publication_holds() {
  local controller_step publisher
  controller_step=$(workflow_step "$1" 'Run the once-daily state machine')
  publisher=$(workflow_step "$1" 'Publish the local decision receipt')
  grep -Eq '^        if: always\(\)$' <<<"$controller_step" || return 1
  grep -Eq '^        if: always\(\)$' <<<"$publisher" || return 1
  grep -Eq '^          if-no-files-found: error$' <<<"$publisher" || return 1
  if awk '!/^[[:space:]]*#/' <<<"$controller_step" |
    grep -Eq '(^|[^[:alnum:]_-])date([^[:alnum:]_-]|$)'; then
    return 1
  fi
  return 0
}

pr_head_holds "$workflow" ||
  fail 'pull-request CI does not run the focused proof from the exact candidate head'
# shellcheck disable=SC2016
reject_mutant pr-head-redirect.yaml "$workflow" \
  's/github\.event\.pull_request\.head\.sha/github.sha/' 'github.sha' \
  'a checkout redirected away from the candidate head' pr_head_holds
reject_mutant pr-head-commented.yaml "$workflow" \
  's|^          ref: |          # ref: |' '          # ref: ' \
  'a commented-out candidate-head binding' pr_head_holds
reject_mutant pr-head-caller-noop.yaml "$workflow" \
  "s|^        run: tests/test-daily-amaru.sh\$|        # run: tests/test-daily-amaru.sh\n        run: 'true'|" \
  "        run: 'true'" 'a no-op focused caller under a bound head' pr_head_holds
printf 'PR-HEAD-WIRING explicit=1 focused_caller=1 mutants_rejected=3\n'
pass pull-request-proof-runs-candidate-head

receipt_publication_holds "$workflow" ||
  fail 'the scheduled receipt is not always produced and fatally published'
reject_mutant controller-not-always.yaml "$workflow" \
  '0,/^        if: always()$/{s//        if: success()/}' '        if: success()' \
  'a controller skipped after an earlier step failed' receipt_publication_holds
reject_mutant receipt-warning.yaml "$workflow" \
  's/^          if-no-files-found: error$/          if-no-files-found: warn/' \
  '          if-no-files-found: warn' 'a receipt whose absence only warns' \
  receipt_publication_holds
reject_mutant controller-pre-date.yaml "$workflow" \
  '/^          scripts\/daily-amaru.sh$/i\          date -u +%F >/dev/null' \
  'date -u +%F' 'an external date invocation before controller entry' \
  receipt_publication_holds
printf 'RECEIPT-PUBLICATION controller_always=1 missing_artifact=fatal\n'
pass scheduled-receipt-always-published

# INV-213-E01 / INV-213-E02 / INV-213-E03 / INV-213-E04:
# Effect-stream discriminability: positive controls on gh and non-gh transport,
# negative control on early transport before boundary, and negative control on disabled logger.

# Positive controls for gh and non-gh transport operations.
gh_probe="$tmp_root/gh-positive.probe"
: >"$gh_probe"
DAILY_AMARU_FAKE_GH_LOG="$gh_probe" "$fake_gh" api repos/example >/dev/null
[ -s "$gh_probe" ] && grep -Fq 'gh api repos/example' "$gh_probe" ||
  fail 'fake-gh positive control probe failed to record gh operation'

transport_probe="$tmp_root/transport-positive.probe"
: >"$transport_probe"
DAILY_AMARU_EFFECT_LOG="$transport_probe" "$transport" preflight gh git jq rg sed awk grep tail tr head seq sleep date docker nix >/dev/null 2>&1 || true
[ -s "$transport_probe" ] && grep -Fq 'transport preflight' "$transport_probe" ||
  fail 'transport effect logger positive control failed to record non-gh operation'

# Negative control: disabling the logger must fail the positive probe.
disabled_probe="$tmp_root/disabled-logger.probe"
: >"$disabled_probe"
disabled_mutant="$tmp_root/fake-gh-disabled.sh"
sed 's|} >>"$log_file"|} >/dev/null # effect-stream-logger-disabled|' "$fake_gh" >"$disabled_mutant"
chmod +x "$disabled_mutant"
DAILY_AMARU_FAKE_GH_LOG="$disabled_probe" "$disabled_mutant" api repos/example >/dev/null
if [ -s "$disabled_probe" ]; then
  fail 'disabled logger mutant unexpectedly recorded to probe'
fi

# Negative control: early transport before boundary must be observable in effect stream.
early_mutant="$tmp_root/controller-early-transport.sh"
awk '
  { print }
  $0 == "[ -n \"${DAILY_AMARU_DAY:-}\" ] || bootstrap_command_census+=(date)" {
    print "if command -v bash >/dev/null 2>&1; then"
    print "  early_transport=\"${BASH_SOURCE[0]%/*}/daily-amaru-github.sh\""
    print "  \"$early_transport\" preflight >/dev/null 2>&1 || true"
    print "fi # effect-stream-early-transport"
  }
' "$controller" >"$early_mutant"
chmod +x "$early_mutant"
run_hermetic_case early-transport-check '' 2026-08-02 "$early_mutant"
grep -Fq 'transport preflight' "$hermetic_effects" ||
  fail 'early transport before boundary was not recorded in the effect stream'

printf 'EFFECT-STREAM gh=1 non_gh=1 positive_control=1 logger_required=1\n'
pass effect-stream-discriminability

