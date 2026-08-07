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
  local literal=$1
  local actual
  actual=$(count_literal "$workflow" "$literal")
  [ "$actual" -eq 1 ] ||
    fail "workflow must declare exactly once (found $actual): $literal"
}

# --- D213-01 receipt oracle ------------------------------------------------
# A broken precondition is only proved loud when a receipt naming the UTC day,
# the precise stage, `outcome=FAILED`, and a stable specific error exists while
# no business effect was reached. The oracle is exercised in both directions
# below before any verdict it produces is believed.
receipt_oracle() {
  local receipt=$1
  local day=$2
  local stage=$3
  local error=$4
  local effects=$5
  local field forbidden

  [ -f "$receipt" ] && [ ! -L "$receipt" ] && [ -s "$receipt" ] || return 1
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

# --- Hermetic scheduled-runner PATH ---------------------------------------
# Every non-shell command the scheduled production transport can reach, minus
# the incident command `rg`. Seeding an exclusive PATH makes a missing-command
# verdict caused by absence rather than by an unrelated broken harness.
scheduled_seed_commands=(
  bash dirname mkdir git jq sed awk grep tail tr head seq sleep date docker nix
)

seed_scheduled_path() {
  local bin_dir=$1
  local include_rg=$2
  local command target
  mkdir -p "$bin_dir"
  for command in "${scheduled_seed_commands[@]}"; do
    if target=$(command -v "$command" 2>/dev/null) &&
      [ "${target:0:1}" = / ] && [ -x "$target" ]; then
      ln -sf "$target" "$bin_dir/$command"
    else
      printf '#!/bin/sh\nexit 0\n' >"$bin_dir/$command"
      chmod +x "$bin_dir/$command"
    fi
  done
  ln -sf "$fake_gh" "$bin_dir/gh"
  if [ "$include_rg" = with-rg ]; then
    printf '#!/bin/sh\nexit 0\n' >"$bin_dir/rg"
    chmod +x "$bin_dir/rg"
  else
    rm -f "$bin_dir/rg"
  fi

  # Positive control: an exclusive PATH that resolves nothing would report every
  # command as missing and prove nothing at all.
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

run_scheduled_incident() {
  local day=$1
  scheduled_dir="$tmp_root/scheduled-$day"
  scheduled_state="$scheduled_dir/state"
  scheduled_receipt="$scheduled_dir/receipt"
  scheduled_effects="$scheduled_dir/effects"
  mkdir -p "$scheduled_state"
  : >"$scheduled_effects"
  seed_scheduled_path "$scheduled_dir/bin" without-rg

  scheduled_rc=0
  env \
    PATH="$scheduled_dir/bin" \
    DAILY_AMARU_FAKE_GH_LOG="$scheduled_effects" \
    DAILY_AMARU_MODE=production \
    DAILY_AMARU_DAY="$day" \
    DAILY_AMARU_IDENTITY=seed-non-empty-identity \
    DAILY_AMARU_STATE_DIR="$scheduled_state" \
    DAILY_AMARU_RECEIPT="$scheduled_receipt" \
    "$controller" \
    >"$scheduled_dir/stdout" 2>"$scheduled_dir/stderr" || scheduled_rc=$?
}

run_transport_preflight() {
  local bin_dir=$1
  local root=$2
  local label=$3
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

# Extract one transport `case` branch body so identity boundaries can be
# checked per operation rather than across the whole file.
transport_branch() {
  local file=$1
  local operation=$2
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

# INV-213-03 — the minted bootstrap token must not be reachable from any
# same-repository operation, and the bootstrap operations must not silently
# fall back to the repository token.
identity_boundary_holds() {
  local file=$1
  local operation body
  for operation in "${bootstrap_boundary_operations[@]}"; do
    body=$(transport_branch "$file" "$operation")
    [ -n "$body" ] || return 1
    grep -q 'bootstrap_identity' <<<"$body" || return 1
    if grep -q 'repository_identity' <<<"$body"; then
      return 1
    fi
  done
  for operation in "${repository_boundary_operations[@]}"; do
    body=$(transport_branch "$file" "$operation")
    [ -n "$body" ] || return 1
    if grep -q 'bootstrap_identity\|DAILY_AMARU_IDENTITY' <<<"$body"; then
      return 1
    fi
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

# --- Receipt oracle controls ----------------------------------------------
oracle_root="$tmp_root/receipt-oracle"
mkdir -p "$oracle_root"
: >"$oracle_root/clean-effects"
printf 'gh repo clone lambdasistemi/amaru-bootstrap\n' >"$oracle_root/dirty-effects"

printf 'day=2026-08-02\nstage=runner-preflight\noutcome=FAILED\nerror=missing-command-rg\n' \
  >"$oracle_root/valid"
receipt_oracle "$oracle_root/valid" 2026-08-02 runner-preflight missing-command-rg \
  "$oracle_root/clean-effects" ||
  fail 'receipt oracle rejected its positive control'

printf 'day=2026-08-02\nstage=runner-preflight\noutcome=FAILED\n' >"$oracle_root/no-error"
if receipt_oracle "$oracle_root/no-error" 2026-08-02 runner-preflight missing-command-rg \
  "$oracle_root/clean-effects"; then
  fail 'receipt oracle accepted a missing specific error'
fi

printf 'day=2026-08-02\nstage=runner-preflight\noutcome=CHANGED\nerror=missing-command-rg\n' \
  >"$oracle_root/success-like"
if receipt_oracle "$oracle_root/success-like" 2026-08-02 runner-preflight missing-command-rg \
  "$oracle_root/clean-effects"; then
  fail 'receipt oracle accepted a success-like outcome'
fi

if receipt_oracle "$oracle_root/absent" 2026-08-02 runner-preflight missing-command-rg \
  "$oracle_root/clean-effects"; then
  fail 'receipt oracle accepted silence'
fi

if receipt_oracle "$oracle_root/valid" 2026-08-02 runner-preflight missing-command-rg \
  "$oracle_root/dirty-effects"; then
  fail 'receipt oracle accepted a reached business effect'
fi
printf 'RECEIPT-ORACLE-CONTROLS positive=1 negative=4\n'
pass receipt-oracle-controls

# --- FN-213-03 dependency preflight controls -------------------------------
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

run_transport_preflight "$preflight_root/incomplete" "$preflight_root" incomplete
[ "$preflight_rc" -ne 0 ] || fail 'preflight accepted a runner without rg'
grep -Fqx 'daily-amaru-github: missing command: rg' "$preflight_stderr" ||
  fail 'preflight did not name the exact missing command on stderr'
grep -Fqx 'MISSING-COMMAND rg' "$preflight_stdout" ||
  fail 'preflight did not report the missing command machine-readably'

# The verdict must belong to a property class, not to the single `rg` instance.
run_transport_preflight "$preflight_root/complete" "$preflight_root" probe \
  t213-absent-probe
[ "$preflight_rc" -ne 0 ] ||
  fail 'preflight accepted an explicitly required absent command'
grep -Fqx 'daily-amaru-github: missing command: t213-absent-probe' "$preflight_stderr" ||
  fail 'preflight did not name the absent explicit requirement'

[ ! -s "$preflight_root/effects" ] ||
  fail 'dependency preflight reached a GitHub effect'
printf 'DEPENDENCY-CENSUS count=%s rg=required effects=0\n' "$census_count"
pass scheduled-preflight-controls

# --- FR-213-02 dated incident reproduction ---------------------------------
scheduled_effect_logs=()
for incident_day in 2026-08-02 2026-08-03; do
  run_scheduled_incident "$incident_day"
  [ "$scheduled_rc" -ne 0 ] ||
    fail "scenario=scheduled-$incident_day expected a non-zero scheduled exit"
  grep -Fqx 'daily-amaru-github: missing command: rg' "$scheduled_dir/stderr" ||
    fail "scenario=scheduled-$incident_day lacks the exact incident fingerprint"
  receipt_oracle "$scheduled_receipt" "$incident_day" runner-preflight \
    missing-command-rg "$scheduled_effects" ||
    fail "scenario=scheduled-$incident_day lacks a loud durable failure receipt"
  # A broken runner must not even consume the UTC day.
  if grep -Fq "daily-amaru day=$incident_day claim" "$scheduled_effects"; then
    fail "scenario=scheduled-$incident_day claimed the UTC day behind a broken runner"
  fi
  scheduled_effect_logs+=("$scheduled_effects")
  printf 'INCIDENT day=%s base=311dfc1 fingerprint=%s exit=%s business_effects=0\n' \
    "$incident_day" 'daily-amaru-github: missing command: rg' "$scheduled_rc"
  pass "scheduled-missing-rg-$incident_day"
done

# --- Existing controller contract ------------------------------------------
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

# The controller owns the precondition order: a transport-reported missing
# command becomes stage=runner-preflight before the day is even claimed.
run_case missing-tool production seed-non-empty-identity
require_failure
assert_log_count 0 '^claim-day '
assert_log_count 0 '^claim-sha-attempt '
assert_no_mutation
assert_no_launch
assert_honest_failure_receipt runner-preflight
assert_file_contains "$case_receipt" 'day=2026-07-31'
assert_file_contains "$case_receipt" 'error=missing-command-rg'
tool_control_log=$case_log
pass missing-tool

# INV-213-02 — a preflight that reports nothing, or reports an unparsable
# success, cannot be read as a satisfied dependency contract.
for vacuous in silent-preflight malformed-preflight; do
  run_case "$vacuous" production seed-non-empty-identity
  require_failure
  assert_log_count 0 '^claim-day '
  assert_no_mutation
  assert_no_launch
  assert_honest_failure_receipt runner-preflight
  assert_file_contains "$case_receipt" 'error=malformed-dependency-evidence'
  pass "$vacuous"
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

# --- INV-213-06 counted effect census over both broken preconditions -------
for broken_log in "${scheduled_effect_logs[@]}"; do
  for forbidden in 'repo clone' 'pr create' 'pr merge' 'workflow run' 'run watch'; do
    if grep -Fq -- "$forbidden" "$broken_log"; then
      fail "missing-command control reached a business effect: $forbidden"
    fi
  done
done
for broken_log in "$tool_control_log" "$identity_control_log"; do
  for pattern in \
    '^claim-sha-attempt ' \
    '^mutation:' \
    '^await-supervised-integration ' \
    '^fake-launch ' \
    '^real-launch '
  do
    actual=$(count_matches "$broken_log" "$pattern")
    [ "$actual" -eq 0 ] ||
      fail "broken precondition reached $actual effects matching $pattern"
  done
done
printf 'EFFECT-CENSUS controls=2 attempts=0 mutations=0 integrations=0 fake_launches=0 real_launches=0\n'
pass broken-preconditions-no-business-effects

# --- D213-02 dedicated bootstrap App interface -----------------------------
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

# Prove the boundary check can fail: a mutant that reaches for the bootstrap
# identity inside a same-repository operation must be rejected, and a mutant
# that drops it from the bootstrap boundary must be rejected too. Each mutation
# verifies its own application so a silently unapplied edit cannot report a
# caught defect.
mutant_root="$tmp_root/identity-mutants"
mkdir -p "$mutant_root"

# The injected text is transport source read back verbatim, not an expansion.
# shellcheck disable=SC2016
sed 's#^  receipt)$#  receipt)\n    leak="$bootstrap_identity"#' "$transport" \
  >"$mutant_root/leaked.sh"
# shellcheck disable=SC2016
grep -Fq 'leak="$bootstrap_identity"' "$mutant_root/leaked.sh" ||
  fail 'identity-leak mutation did not apply'
if identity_boundary_holds "$mutant_root/leaked.sh"; then
  fail 'boundary check accepted a bootstrap identity inside a repository operation'
fi

sed 's#bootstrap_identity#repository_identity#g' "$transport" \
  >"$mutant_root/downgraded.sh"
if grep -Fq 'bootstrap_identity' "$mutant_root/downgraded.sh"; then
  fail 'identity-downgrade mutation did not apply'
fi
if identity_boundary_holds "$mutant_root/downgraded.sh"; then
  fail 'boundary check accepted a bootstrap operation without the minted identity'
fi
printf 'IDENTITY-BOUNDARY bootstrap_ops=%s repository_ops=%s mutants_rejected=2\n' \
  "${#bootstrap_boundary_operations[@]}" "${#repository_boundary_operations[@]}"
pass dedicated-app-scope

# --- INV-213-05 the minted token is ephemeral ------------------------------
for forbidden in DAILY_AMARU_CROSS_REPO_TOKEN MOOG_GITHUB_PAT GITHUB_ENV; do
  if grep -Fq -- "$forbidden" "$workflow" "$controller" "$transport"; then
    fail "forbidden credential path remains: $forbidden"
  fi
done
# Literal workflow expressions again: the minted token must be bound exactly
# once, and must appear nowhere else in the workflow.
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

# Positive control: the same search finds the value where it is genuinely
# present, so the zero above is absence rather than a broken instrument.
printf '%s\n' "$secret_value" >"$case_dir/leak-probe"
grep -Fq -- "$secret_value" "$case_dir/leak-probe" ||
  fail 'leak search cannot detect a known-present secret'
printf 'SECRET-PERSISTENCE artifacts_scanned=%s leaks=0 probe=detected\n' \
  "$scanned_artifacts"
pass bootstrap-token-not-persisted

# --- INV-213-09 production wiring executes this proof ----------------------
assert_workflow_literal_once 'run: tests/test-daily-amaru.sh'
assert_workflow_literal_once 'scripts/daily-amaru.sh'
assert_workflow_literal_once 'DAILY_AMARU_MODE: production'
assert_workflow_literal_once 'uses: actions/upload-artifact@v6'
assert_workflow_literal_once 'if: always()'
assert_workflow_literal_once 'continue-on-error: true'
[ "$(count_literal "$workflow" 'ripgrep')" -ge 1 ] ||
  fail 'the scheduled runner does not provision the incident command'
[ "$(count_literal "$workflow" 'setup-nix')" -ge 1 ] ||
  fail 'the scheduled runner does not provision nix for the bootstrap proposal'
printf 'WIRING pull_request_proof=1 scheduled_controller=1 receipt_upload=1\n'
pass workflow-wires-scheduled-proof
