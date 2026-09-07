#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
controller="$repo_root/scripts/daily-amaru.sh"
transport="$repo_root/scripts/daily-amaru-github.sh"
workflow="$repo_root/.github/workflows/daily-amaru.yaml"
fake_transport="$repo_root/tests/fixtures/daily-amaru/fake-transport.sh"
fake_gh="$repo_root/tests/fixtures/daily-amaru/fake-gh.sh"
pre_slice_base=01f96e4b1352b2558260e9401e422eaf3136a320
s4_base=2e7b35a8b01be73142d648b720654158f16934ae
default_workflow_head=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
tmp_root=$(mktemp -d)
trap 'rm -rf "$tmp_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

ensure_history_commit() {
  local repository=$1 commit=$2
  if git -C "$repository" cat-file -e "$commit^{commit}" 2>/dev/null; then
    return 0
  fi
  if ! git -C "$repository" fetch --no-tags --depth=1 origin "$commit" \
    >/dev/null 2>&1; then
    printf 'HISTORY-BASE-UNAVAILABLE repository=%s commit=%s fetch=failed\n' \
      "$repository" "$commit" >&2
    return 1
  fi
  if ! git -C "$repository" cat-file -e "$commit^{commit}" 2>/dev/null; then
    printf 'HISTORY-BASE-UNAVAILABLE repository=%s commit=%s fetch=incomplete\n' \
      "$repository" "$commit" >&2
    return 1
  fi
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
  assert_file_lacks "$case_receipt" 'outcome=(UNCHANGED|AWAITING|CHANGED|SUCCESS)|run_outcome=(success|awaiting-integration)|findings_complete=true'
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
  if grep -Eq '^(outcome=(UNCHANGED|AWAITING|CHANGED|SUCCESS)|run_outcome=(success|requested|awaiting-integration))$' \
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
  local app_id=${4-}
  local app_key=${5-}
  local head_source=${6:-daily:$default_workflow_head}
  local shared_state=${7:-}
  local controller_under_test=${8:-$controller}
  local head_env=()
  case_number=$((case_number + 1))
  case_dir="$tmp_root/$case_number-$case_name"
  case_state=${shared_state:-$case_dir/state}
  case_log="$case_dir/transport.log"
  case_receipt="$case_dir/receipt"
  case_stdout="$case_dir/stdout"
  case_stderr="$case_dir/stderr"
  mkdir -p "$case_state" "$case_dir"
  : >"$case_log"

  if [ "$case_name" = duplicate-same-day ]; then
    printf '<!-- daily-amaru day=2026-07-31 claim head=%s -->\n' \
      "$default_workflow_head" >"$case_state/markers"
  fi
  if [ "$case_name" = same-sha-retry ]; then
    printf '<!-- daily-amaru attempted-sha=1111111111111111111111111111111111111111 head=%s -->\n' \
      "$default_workflow_head" >"$case_state/markers"
  fi
  if [ "$case_name" = same-sha-retry-succeeded ]; then
    # A prior night already completed at this exact sha and head: its receipt
    # stands in the durable record, and the guard must let the night proceed.
    printf '<!-- daily-amaru attempted-sha=1111111111111111111111111111111111111111 head=%s -->\n' \
      "$default_workflow_head" >"$case_state/markers"
    printf '%s\n' '--- receipt ---' \
      'day=2026-07-31' \
      'stage=complete' \
      'outcome=AWAITING' \
      "workflow_head=$default_workflow_head" \
      'upstream_sha=1111111111111111111111111111111111111111' \
      'run_outcome=awaiting-integration' >>"$case_state/receipt-history"
  fi

  case "$head_source" in
    daily:*) head_env=(DAILY_AMARU_HEAD="${head_source#daily:}") ;;
    github:*) head_env=(GITHUB_SHA="${head_source#github:}") ;;
    absent) head_env=() ;;
    *) fail "unknown head source: $head_source" ;;
  esac

  case_rc=0
  env -u DAILY_AMARU_HEAD -u GITHUB_SHA \
    FAKE_SCENARIO="$case_name" \
    FAKE_LOG="$case_log" \
    DAILY_AMARU_TRANSPORT="$fake_transport" \
    DAILY_AMARU_MODE="$mode" \
    DAILY_AMARU_DAY=2026-07-31 \
    DAILY_AMARU_IDENTITY="$identity" \
    DAILY_AMARU_APP_ID="$app_id" \
    DAILY_AMARU_APP_PRIVATE_KEY="$app_key" \
    DAILY_AMARU_STATE_DIR="$case_state" \
    DAILY_AMARU_RECEIPT="$case_receipt" \
    DAILY_AMARU_ALLOW_REAL=1 \
    "${head_env[@]}" \
    "$controller_under_test" >"$case_stdout" 2>"$case_stderr" || case_rc=$?
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
    GITHUB_SHA="$default_workflow_head" \
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
  claim-day last-success-sha awaiting-integration-age claim-sha-attempt claim-launch
  prepare-consumer-repin require-consumer-checks await-supervised-integration
  real-launch receipt
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

job_condition() {
  awk -v job="  $2:" '
    $0 == job { inside = 1; next }
    inside && /^  [A-Za-z0-9_-]+:/ { exit }
    inside && /^    if: / { sub(/^    if: /, ""); print; exit }
  ' "$1"
}

workflow_job_steps() {
  awk -v job="  $2:" '
    $0 == job { inside = 1; next }
    inside && /^  [A-Za-z0-9_-]+:/ { exit }
    inside && $0 == "    steps:" { steps = 1 }
    inside && steps { print }
  ' "$1"
}

routing_holds() {
  local file=$1 dispatch production dry
  dispatch=$(awk '
    /^  workflow_dispatch:$/ { inside = 1 }
    inside && /^  pull_request:/ { exit }
    inside { print }
  ' "$file")
  grep -Fqx '  workflow_dispatch:' <<<"$dispatch" || return 1
  grep -Fqx '      production:' <<<"$dispatch" || return 1
  grep -Fqx '        type: boolean' <<<"$dispatch" || return 1
  grep -Fqx '        default: false' <<<"$dispatch" || return 1
  production=$(job_condition "$file" daily-amaru-scheduled)
  dry=$(job_condition "$file" daily-amaru-dry-run)
  [ "$production" = "github.event_name == 'schedule' || (github.event_name == 'workflow_dispatch' && inputs.production)" ] || return 1
  [ "$dry" = "github.event_name == 'pull_request' || (github.event_name == 'workflow_dispatch' && !inputs.production)" ] || return 1
  [ "$(grep -Ec '^  daily-amaru-scheduled:$' "$file" || true)" -eq 1 ] || return 1
  [ "$(grep -Ec '^[[:space:]]+scripts/daily-amaru[.]sh$' "$file" || true)" -eq 1 ] || return 1
  # shellcheck disable=SC2016
  grep -Fqx '  group: daily-amaru-${{ github.ref }}' "$file" || return 1
  grep -Fqx '  cancel-in-progress: false' "$file" || return 1
}

workflow_job() {
  awk -v job="  $2:" '
    $0 == job { inside = 1 }
    inside && $0 != job && /^  [A-Za-z0-9_-]+:/ { exit }
    inside { print }
  ' "$1"
}

production_job_untouched() {
  local file=$1 repository=${2:-$repo_root}
  local base_commit=${3:-$s4_base}
  local base_workflow=$tmp_root/canonical-entry-base-workflow.yaml
  ensure_history_commit "$repository" "$base_commit" || return 1
  git -C "$repository" show \
    "$base_commit:.github/workflows/daily-amaru.yaml" >"$base_workflow" || return 1
  cmp -s \
    <(workflow_job "$file" daily-amaru-scheduled) \
    <(workflow_job "$base_workflow" daily-amaru-scheduled)
}

canonical_dry_run_steps() {
  # shellcheck disable=SC2016
  printf '%s\n' \
    '    steps:' \
    '      - name: Check out the exact candidate' \
    '        uses: actions/checkout@v6' \
    '        with:' \
    '          ref: ${{ github.event.pull_request.head.sha }}' \
    '      - uses: paolino/dev-assets/setup-nix@v0.0.1' \
    '        with:' \
    '          cachix-auth-token: "${{ secrets.CACHIX_AUTH_TOKEN }}"' \
    '      - name: Run the canonical proof entry' \
    '        run: nix develop --quiet -c just ci'
}

canonical_dry_run_entry_holds() {
  local file=$1 repository=${2:-$repo_root}
  local base_commit=${3:-$s4_base}
  local dry_steps expected_steps
  dry_steps=$(workflow_job_steps "$file" daily-amaru-dry-run) || return 1
  expected_steps=$(canonical_dry_run_steps) || return 1
  [ "$dry_steps" = "$expected_steps" ] || return 1
  [ "$(job_condition "$file" daily-amaru-dry-run)" = \
    "github.event_name == 'pull_request' || (github.event_name == 'workflow_dispatch' && !inputs.production)" ] || return 1
  production_job_untouched "$file" "$repository" "$base_commit"
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

ensure_history_commit "$repo_root" "$pre_slice_base" ||
  fail "history baseline unavailable: $pre_slice_base"

# Complete #223 proof bundle is intentionally RED on the unchanged base.
routing_holds "$workflow" ||
  fail 'INV-223-DISPATCH-ROUTING: typed manual production routing is absent'

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

run_case awaiting-integration
require_success
assert_file_contains "$case_receipt" 'stage=complete'
assert_file_contains "$case_receipt" 'outcome=AWAITING'
assert_file_contains "$case_receipt" 'run_outcome=awaiting-integration'
assert_file_contains "$case_stdout" \
  'AWAITING 2026-07-31 1111111111111111111111111111111111111111 https://example.invalid/pull/17'
assert_log_count 1 '^await-supervised-integration '
assert_log_count 1 '^awaiting-integration-age '
assert_no_launch
pass awaiting-integration

DAILY_AMARU_AWAITING_MAX_DAYS=3 run_case awaiting-integration-threshold
require_success
assert_file_contains "$case_receipt" 'outcome=AWAITING'
assert_file_contains "$case_receipt" 'run_outcome=awaiting-integration'
assert_no_launch
pass awaiting-integration-at-threshold

for integration_case in integration-head-mismatch integration-not-exact-main; do
  run_case "$integration_case"
  require_failure
  assert_no_launch
  assert_honest_failure_receipt supervised-integration
  case "$integration_case" in
    integration-head-mismatch)
      assert_file_contains "$case_stderr" \
        'daily-amaru-github: integrated PR head differs from the verified candidate'
      ;;
    integration-not-exact-main)
      assert_file_contains "$case_stderr" \
        'daily-amaru-github: merged consumer commit is not exact current main'
      ;;
  esac
  pass "$integration_case"
done

DAILY_AMARU_AWAITING_MAX_DAYS=3 run_case awaiting-integration-stale
require_failure
assert_no_launch
assert_honest_failure_receipt supervised-integration
assert_file_contains "$case_receipt" 'error=awaiting-integration-stale-4-days'
pass awaiting-integration-stale-alarm

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
assert_file_contains "$case_receipt" 'error=missing-credentials-DAILY_AMARU_APP_ID,DAILY_AMARU_APP_PRIVATE_KEY'
identity_control_log=$case_log
pass missing-identity

for cred_case in 'missing-app-id|DAILY_AMARU_APP_ID||key-present' 'missing-app-key|DAILY_AMARU_APP_PRIVATE_KEY|id-present|'; do
  IFS='|' read -r cname cmissing cid ckey <<<"$cred_case"
  run_case "$cname" production '' "$cid" "$ckey"
  require_failure
  assert_no_mutation
  assert_no_launch
  assert_honest_failure_receipt identity
  assert_file_contains "$case_receipt" "error=missing-credentials-$cmissing"
  pass "$cname"
done

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
assert_file_contains "$case_state/markers" \
  "<!-- daily-amaru day=2026-07-31 claim head=$default_workflow_head -->"
assert_log_count 0 '^resolve-upstream '
assert_no_mutation
assert_no_launch
assert_honest_failure_receipt day-claim
assert_file_contains "$case_receipt" 'error=unchanged-head'
pass duplicate-same-day

run_case same-sha-retry
require_failure
assert_file_contains "$case_state/markers" \
  "<!-- daily-amaru attempted-sha=1111111111111111111111111111111111111111 head=$default_workflow_head -->"
assert_no_mutation
assert_no_launch
assert_honest_failure_receipt launch-attempt
assert_file_contains "$case_receipt" 'error=unchanged-head'
pass same-sha-retry

# A completed receipt naming the earlier attempt at the same sha and head
# makes the night a recorded no-op: the guard must not refuse it, and the
# night continues through integration to its launch.
run_case same-sha-retry-succeeded
require_success
assert_file_contains "$case_state/markers" \
  "<!-- daily-amaru attempted-sha=1111111111111111111111111111111111111111 head=$default_workflow_head -->"
assert_log_count 1 '^claim-sha-attempt '
assert_file_lacks "$case_stderr" 'unchanged-head'
assert_log_count 1 '^fake-launch '
assert_log_count 0 '^real-launch '
assert_file_contains "$case_receipt" 'outcome=CHANGED'
assert_file_lacks "$case_receipt" 'claim_supersedes'
pass same-sha-retry-succeeded

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
  grep -Fqx 'daily-amaru-dry-run|nix' <<<"$callers" || return 1
  grep -Fqx 'daily-amaru-scheduled|scripts/daily-amaru.sh' <<<"$callers" || return 1
  return 0
}
wiring_holds "$workflow" ||
  fail 'the workflow does not executably call both controller entry points'
assert_workflow_literal_once \
  "if: github.event_name == 'pull_request' || (github.event_name == 'workflow_dispatch' && !inputs.production)"
assert_workflow_literal_once \
  "if: github.event_name == 'schedule' || (github.event_name == 'workflow_dispatch' && inputs.production)"
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
  "s|^        run: nix develop --quiet -c just ci\$|        # run: nix develop --quiet -c just ci\n        run: 'true'|" \
  "        run: 'true'" 'an orphaned pull-request proof caller' wiring_holds
grep -Fq 'nix develop --quiet -c just ci' "$mutant_root/wiring-pull-request.yaml" ||
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
  "s|^        run: nix develop --quiet -c just ci\$|        # run: nix develop --quiet -c just ci\n        run: 'true'|" \
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
if [ ! -s "$gh_probe" ] || ! grep -Fq 'gh api repos/example' "$gh_probe"; then
  fail 'fake-gh positive control probe failed to record gh operation'
fi

transport_probe="$tmp_root/transport-positive.probe"
: >"$transport_probe"
DAILY_AMARU_EFFECT_LOG="$transport_probe" "$transport" preflight gh git jq rg sed awk grep tail tr head seq sleep date docker nix >/dev/null 2>&1 || true
if [ ! -s "$transport_probe" ] || ! grep -Fq 'transport preflight' "$transport_probe"; then
  fail 'transport effect logger positive control failed to record non-gh operation'
fi

# Negative control: disabling the logger must fail the positive probe.
disabled_probe="$tmp_root/disabled-logger.probe"
: >"$disabled_probe"
disabled_mutant="$tmp_root/fake-gh-disabled.sh"
# shellcheck disable=SC2016
sed 's|} >>"$log_file"|} >/dev/null # effect-stream-logger-disabled|' "$fake_gh" >"$disabled_mutant"
chmod +x "$disabled_mutant"
DAILY_AMARU_FAKE_GH_LOG="$disabled_probe" "$disabled_mutant" api repos/example >/dev/null
if [ -s "$disabled_probe" ]; then
  fail 'disabled logger mutant unexpectedly recorded to probe'
fi

# Negative control: early transport before boundary must be observable in effect stream.
early_mutant="$tmp_root/controller-early-transport.sh"
awk -v transport="$transport" '
  { print }
  $0 == "[ -n \"${DAILY_AMARU_DAY:-}\" ] || bootstrap_command_census+=(date)" {
    print "if command -v bash >/dev/null 2>&1; then"
    print "  \"" transport "\" preflight >/dev/null 2>&1 || true"
    print "fi # effect-stream-early-transport"
  }
' "$controller" >"$early_mutant"
chmod +x "$early_mutant"
run_hermetic_case early-transport-check dirname 2026-08-02 "$early_mutant"
grep -Fq 'transport preflight' "$hermetic_effects" ||
  fail 'early transport before boundary was not recorded in the effect stream'

printf 'EFFECT-STREAM gh=1 non_gh=1 positive_control=1 logger_required=1\n'
pass effect-stream-discriminability

# INV-213-C05: a generic-only identity error must not satisfy the proof.
generic_id_dir="$tmp_root/generic-id-mutant"
mkdir -p "$generic_id_dir"
generic_id_controller="$generic_id_dir/daily-amaru.sh"
sed 's/fail_stage identity .*/fail_stage identity missing-production-identity/' "$controller" >"$generic_id_controller"
chmod +x "$generic_id_controller"
generic_id_effects="$generic_id_dir/effects"
: >"$generic_id_effects"
generic_id_rc=0
env \
  PATH="$PATH" \
  FAKE_SCENARIO=missing-identity \
  FAKE_LOG="$generic_id_dir/transport.log" \
  DAILY_AMARU_TRANSPORT="$fake_transport" \
  DAILY_AMARU_MODE=production \
  GITHUB_SHA="$default_workflow_head" \
  DAILY_AMARU_DAY=2026-07-31 \
  DAILY_AMARU_IDENTITY="" \
  DAILY_AMARU_STATE_DIR="$generic_id_dir/state" \
  DAILY_AMARU_RECEIPT="$generic_id_dir/receipt" \
  DAILY_AMARU_ALLOW_REAL=1 \
  "$generic_id_controller" >/dev/null 2>&1 || generic_id_rc=$?
if [ "$generic_id_rc" -eq 0 ] || grep -Fqx 'error=missing-credentials-DAILY_AMARU_APP_ID,DAILY_AMARU_APP_PRIVATE_KEY' "$generic_id_dir/receipt" 2>/dev/null; then
  fail 'generic identity mutant unexpectedly passed named credential check'
fi

printf 'IDENTITY-CREDENTIALS named=1 set_exact=1 generic_rejected=1 effects=0\n'
pass identity-named-credentials

# INV-213-B01: scheduled controller environment bindings
scheduled_bindings_hold() {
  local step
  step=$(workflow_step "$1" 'Run the once-daily state machine')
  grep -Eq '^[[:space:]]*DAILY_AMARU_APP_ID:[[:space:]]*\$\{\{[[:space:]]*vars\.DAILY_AMARU_APP_ID[[:space:]]*\}\}' <<<"$step" || return 1
  grep -Eq '^[[:space:]]*DAILY_AMARU_APP_PRIVATE_KEY:[[:space:]]*\$\{\{[[:space:]]*secrets\.DAILY_AMARU_APP_PRIVATE_KEY[[:space:]]*\}\}' <<<"$step" || return 1
}
scheduled_bindings_hold "$workflow" ||
  fail 'scheduled controller missing required credential env bindings'
reject_mutant drop-app-id.yaml "$workflow" \
  '/^[[:space:]]*DAILY_AMARU_APP_ID:/d' '!DAILY_AMARU_APP_ID:' \
  'missing App ID binding' scheduled_bindings_hold
reject_mutant drop-app-key.yaml "$workflow" \
  '/^[[:space:]]*DAILY_AMARU_APP_PRIVATE_KEY:/d' '!DAILY_AMARU_APP_PRIVATE_KEY:' \
  'missing App key binding' scheduled_bindings_hold

# INV-213-P01: fully provisioned production path with 3 distinct nonempty sentinels
prod_id=sentinel-prod-token
prod_app=sentinel-prod-app-id
prod_key=sentinel-prod-key
[ "$prod_id" != "$prod_app" ] && [ "$prod_id" != "$prod_key" ] && [ "$prod_app" != "$prod_key" ] ||
  fail 'sentinels must be distinct'
run_case changed production "$prod_id" "$prod_app" "$prod_key"
require_success
assert_file_contains "$case_receipt" 'stage=complete'
assert_file_contains "$case_receipt" 'outcome=CHANGED'
assert_log_count 1 '^real-launch '
! grep -rq "$prod_key" "$case_dir" || fail 'private key sentinel leaked to disk or log'

# INV-213-B02: docs must describe named credentials and not promise generic missing-production-identity
assert_file_lacks "$repo_root/docs/daily-amaru.md" 'error=missing-production-identity'
grep -Fq 'error=missing-credentials-' "$repo_root/docs/daily-amaru.md" ||
  fail 'docs must describe named-credential error'

printf 'CREDENTIAL-BINDING workflow=1 tuple=1 docs=1\n'
pass credential-binding-contract

# INV-221: the scheduled shape never injects a day. Existing cases all set
# DAILY_AMARU_DAY, so they cannot see a child that does not inherit $day.
#
# The expected day is assembled at runtime from components so it is not a
# YYYY-MM-DD literal in this file or in the controller. A controller that
# hardcodes a harness-known constant therefore cannot match it.
real_utc_day=$(date -u +%F)
omitted_day_y=1999
omitted_day_m=6
omitted_day_d=12
omitted_day_fake=
while [ -z "$omitted_day_fake" ]; do
  trial=$(printf '%04d-%02d-%02d' "$omitted_day_y" "$omitted_day_m" "$omitted_day_d")
  if [ "$trial" != "$real_utc_day" ] &&
    ! grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' \
      "$controller" \
      "$repo_root/tests/test-daily-amaru.sh" \
      "$repo_root/tests/fixtures/daily-amaru/fake-transport.sh" |
      grep -qxF "$trial"; then
    omitted_day_fake=$trial
  else
    omitted_day_d=$((omitted_day_d + 1))
    [ "$omitted_day_d" -le 28 ] ||
      fail 'could not assemble a derived-day nonce absent from the suite'
  fi
done

fake_date_bin="$tmp_root/fake-date-bin"
fake_date_log="$tmp_root/fake-date-invocations"
mkdir -p "$fake_date_bin"
: >"$fake_date_log"
real_date=$(command -v date)
[ -x "$real_date" ] || fail 'cannot resolve the real date binary'
# shellcheck disable=SC2016
cat >"$fake_date_bin/date" <<EOF
#!/bin/sh
if [ "\$#" -eq 2 ] && [ "\$1" = -u ] && [ "\$2" = +%F ]; then
  printf 'date -u +%%F -> %s\n' '$omitted_day_fake' >>'$fake_date_log'
  printf '%s\n' '$omitted_day_fake'
  exit 0
fi
exec '$real_date' "\$@"
EOF
chmod +x "$fake_date_bin/date"
fake_date_out=$(PATH="$fake_date_bin:$PATH" date -u +%F)
[ "$fake_date_out" = "$omitted_day_fake" ] ||
  fail "fake date returned $fake_date_out, not $omitted_day_fake"
[ "$(date -u +%F)" = "$real_utc_day" ] ||
  fail 'real date is no longer the system UTC day'
# The probe above proves the binary works. It does not prove the controller
# invoked it; that is observed per run from fake_date_log.

# The production expansion is compared as a literal, not expanded here.
# shellcheck disable=SC2016
day_bind='${DAILY_AMARU_DAY:?DAILY_AMARU_DAY is required}'
operations_requiring_day() {
  local file=$1 operation body
  while IFS= read -r operation; do
    [ -n "$operation" ] || continue
    body=$(transport_branch "$file" "$operation")
    [ -n "$body" ] || continue
    if grep -Fq -- "$day_bind" <<<"$body"; then
      printf '%s\n' "$operation"
    fi
  done < <(grep -E '^  [a-z0-9-]+\)$' "$file" | sed 's/^  //; s/)$//')
}

mapfile -t prod_day_ops < <(operations_requiring_day "$transport" | sort -u)
mapfile -t fix_day_ops < <(operations_requiring_day "$fake_transport" | sort -u)
required_ops=${#prod_day_ops[@]}
matched=0
if [ "$required_ops" -ge 2 ] &&
  [ "${#fix_day_ops[@]}" -eq "$required_ops" ] &&
  [ "${prod_day_ops[*]}" = "${fix_day_ops[*]}" ]; then
  matched=1
fi
printf 'DAY-FIXTURE-RECONCILIATION required_ops=%s matched=%s\n' \
  "$required_ops" "$matched"
# Negative control: dropping the production expansion must unmatch.
fixture_day_mutant="$tmp_root/fake-transport-no-day.sh"
# Delete only the production expansion; leave every other arm intact.
sed '/DAILY_AMARU_DAY:?DAILY_AMARU_DAY is required/d' \
  "$fake_transport" >"$fixture_day_mutant"
grep -Fq -- "$day_bind" "$fake_transport" ||
  fail 'fixture does not contain the production day expansion'
! grep -Fq -- "$day_bind" "$fixture_day_mutant" ||
  fail 'fixture day-bind mutation did not apply'
mapfile -t fix_mut_ops < <(operations_requiring_day "$fixture_day_mutant" | sort -u)
[ "${prod_day_ops[*]}" != "${fix_mut_ops[*]}" ] ||
  fail 'reconciliation cannot detect a fixture that dropped the day bind'
[ "$required_ops" -ge 2 ] && [ "$matched" -eq 1 ] ||
  fail "fixture day requirement does not match production: prod=[${prod_day_ops[*]}] fixture=[${fix_day_ops[*]}]"
pass day-fixture-reconciliation

run_omitted_day_case() {
  local label=$1 scenario=$2 script=${3:-$controller}
  case_name=$label
  case_number=$((case_number + 1))
  case_dir="$tmp_root/$case_number-$case_name"
  case_state="$case_dir/state"
  case_log="$case_dir/transport.log"
  case_receipt="$case_dir/receipt"
  case_stdout="$case_dir/stdout"
  case_stderr="$case_dir/stderr"
  case_effects="$case_dir/effects"
  mkdir -p "$case_state"
  : >"$case_log"
  : >"$case_effects"
  : >"$fake_date_log"
  case_rc=0
  env -u DAILY_AMARU_DAY \
    PATH="$fake_date_bin:$PATH" \
    FAKE_SCENARIO="$scenario" \
    FAKE_LOG="$case_log" \
    DAILY_AMARU_TRANSPORT="$fake_transport" \
    DAILY_AMARU_MODE=test \
    GITHUB_SHA="$default_workflow_head" \
    DAILY_AMARU_IDENTITY=test-identity \
    DAILY_AMARU_STATE_DIR="$case_state" \
    DAILY_AMARU_RECEIPT="$case_receipt" \
    DAILY_AMARU_ALLOW_REAL=1 \
    "$bash_binary" "$script" \
    >"$case_stdout" 2>"$case_stderr" || case_rc=$?
}

receipt_day() {
  if [ -f "$case_receipt" ]; then
    sed -nE 's/^day=([0-9]{4}-[0-9]{2}-[0-9]{2})$/\1/p' "$case_receipt" |
      head -1
  fi
}

observed_day_for() {
  sed -n "s/^observed-day $1 //p" "$case_log" | tail -n 1
}

fake_date_invocations() {
  if [ -f "$fake_date_log" ]; then
    grep -c 'date -u +%F' "$fake_date_log" || true
  else
    printf '0\n'
  fi
}

observed_date_source() {
  if [ "$(fake_date_invocations)" -ge 1 ]; then
    printf 'fake-date\n'
  else
    printf 'uninvoked\n'
  fi
}

# True only when the last omitted-day run used the fake date's output as
# the derived day and the script under test does not contain that day as
# a literal. A hardcoded default, a printf constant, or invoke-and-discard
# cannot satisfy this.
controller_used_fake_date() {
  local script=$1
  local day
  day=$(receipt_day)
  [ "$(fake_date_invocations)" -ge 1 ] || return 1
  [ "$day" = "$omitted_day_fake" ] || return 1
  ! grep -Fq -- "$omitted_day_fake" "$script" || return 1
  return 0
}

# Family of hardcoded/default substitutions. Closing only
# day=${DAILY_AMARU_DAY:-<known-literal>} is not enough.
source_mutant_root="$tmp_root/source-mutants"
mkdir -p "$source_mutant_root"
rejected_source_mutants=0
reject_source_mutant() {
  local label=$1 script=$2 applied=$3 why=$4
  local mutant="$source_mutant_root/$label"
  sed "$script" "$controller" >"$mutant"
  if [ "${applied:0:1}" = '!' ]; then
    ! grep -Fq -- "${applied:1}" "$mutant" ||
      fail "mutation did not apply: $label"
  else
    grep -Fq -- "$applied" "$mutant" || fail "mutation did not apply: $label"
  fi
  chmod +x "$mutant"
  run_omitted_day_case "source-$label" changed "$mutant"
  [ -n "$(receipt_day)" ] ||
    fail "source mutant $label never produced a derived day"
  if controller_used_fake_date "$mutant"; then
    fail "source-use check accepted $why"
  fi
  rejected_source_mutants=$((rejected_source_mutants + 1))
}

# shellcheck disable=SC2016
reject_source_mutant hardcoded-default \
  's|^day=${DAILY_AMARU_DAY:-$(date -u +%F)}$|day=${DAILY_AMARU_DAY:-2024-11-05}|' \
  'day=${DAILY_AMARU_DAY:-2024-11-05}' \
  'a controller that defaults to a hardcoded day instead of date'
# shellcheck disable=SC2016
reject_source_mutant printf-default \
  's|$(date -u +%F)|$(printf %s 2023-01-01)|' \
  '$(printf %s 2023-01-01)' \
  'a controller that substitutes a printf constant for date'
# shellcheck disable=SC2016
reject_source_mutant invoke-and-discard \
  's|^day=${DAILY_AMARU_DAY:-$(date -u +%F)}$|day=${DAILY_AMARU_DAY:-$(date -u +%F >/dev/null; printf %s 2024-11-05)}|' \
  'date -u +%F >/dev/null; printf %s 2024-11-05' \
  'a controller that invokes date and then ignores its output'
[ "$rejected_source_mutants" -eq 3 ] ||
  fail "source-use family rejected $rejected_source_mutants mutants, expected 3"
printf 'DAY-SOURCE-MUTANTS rejected=%s\n' "$rejected_source_mutants"
pass omitted-day-source-use-family

run_omitted_day_case omitted-day-success changed
derived_day=$(receipt_day)
propose_day=$(observed_day_for propose-bootstrap)
repin_day=$(observed_day_for prepare-consumer-repin)
injected_day=absent
observed_source=$(observed_date_source)
printf 'DAY-PROPAGATION derived_day=%s source=%s injected_day=%s propose-bootstrap=%s prepare-consumer-repin=%s\n' \
  "${derived_day:-missing}" "$observed_source" "$injected_day" \
  "${propose_day:-missing}" "${repin_day:-missing}"
[ "$case_rc" -eq 0 ] ||
  fail "omitted-day success failed: exit=$case_rc: $(tr '\n' ' ' <"$case_stderr")"
controller_used_fake_date "$controller" ||
  fail 'fake date was not used by the controller'
[ "$observed_source" = fake-date ] ||
  fail "fake date was not used by the controller (source=$observed_source)"
[ "$derived_day" = "$omitted_day_fake" ] ||
  fail "derived day ${derived_day:-missing} is not the fake date $omitted_day_fake"
[ "$propose_day" = "$derived_day" ] ||
  fail "propose-bootstrap observed ${propose_day:-missing}, not $derived_day"
[ "$repin_day" = "$derived_day" ] ||
  fail "prepare-consumer-repin observed ${repin_day:-missing}, not $derived_day"
assert_log_count 1 '^mutation:bootstrap '
assert_log_count 1 '^mutation:repin '
assert_log_count 0 '^real-launch '
pass omitted-day-propagation

prop_mutant="$tmp_root/controller-no-day-export.sh"
sed '/^export DAILY_AMARU_DAY=/d' "$controller" >"$prop_mutant"
applied=0
if grep -Eq '^export DAILY_AMARU_DAY=' "$controller" &&
  ! grep -Eq '^export DAILY_AMARU_DAY=' "$prop_mutant"; then
  applied=1
fi
run_omitted_day_case omitted-day-mutant changed "$prop_mutant"
mutant_rejected=0
fingerprint=absent
mutant_stage=missing
mutant_error=missing
[ "$case_rc" -ne 0 ] && mutant_rejected=1
if grep -Fq 'DAILY_AMARU_DAY: DAILY_AMARU_DAY is required' "$case_stderr"; then
  fingerprint=matched
fi
if [ -f "$case_receipt" ]; then
  mutant_stage=$(sed -nE 's/^stage=(.*)$/\1/p' "$case_receipt" | head -1)
  mutant_error=$(sed -nE 's/^error=(.*)$/\1/p' "$case_receipt" | head -1)
fi
printf 'DAY-PROPAGATION-MUTANT applied=%s rejected=%s fingerprint=%s stage=%s error=%s\n' \
  "$applied" "$mutant_rejected" "$fingerprint" "$mutant_stage" "$mutant_error"
[ "$applied" -eq 1 ] && [ "$mutant_rejected" -eq 1 ] &&
  [ "$fingerprint" = matched ] &&
  [ "$mutant_stage" = bootstrap-proposal ] &&
  [ "$mutant_error" = proposal-failed ] ||
  fail 'remove-propagation mutant was not applied and rejected as production'
pass omitted-day-propagation-mutant

run_omitted_day_case omitted-day-failed-stage failed-stage
derived_day=$(receipt_day)
day_claim=0
if [ -n "$derived_day" ] && [ -f "$case_state/day-claim" ] &&
  grep -Fqx "$derived_day" "$case_state/day-claim"; then
  day_claim=1
fi
mapfile -t receipt_stages < <(
  sed -nE 's/^receipt .* stage=([^ ]+).*/\1/p' "$case_log"
)
stage_receipts=${#receipt_stages[@]}
expected_stages=(day-claim resolve-upstream launch-attempt bootstrap-proposal)
ordered=0
if [ "$stage_receipts" -eq "${#expected_stages[@]}" ]; then
  ordered=1
  for i in "${!expected_stages[@]}"; do
    [ "${receipt_stages[$i]}" = "${expected_stages[$i]}" ] || ordered=0
  done
fi
real_launches=$(count_matches "$case_log" '^real-launch ')
fake_launches=$(count_matches "$case_log" '^fake-launch ')
printf 'DAY-RECEIPTS derived_day=%s day_claim=%s stage_receipts=%s ordered=%s real_launches=%s fake_launches=%s\n' \
  "${derived_day:-missing}" "$day_claim" "$stage_receipts" "$ordered" \
  "$real_launches" "$fake_launches"
[ "$case_rc" -ne 0 ] || fail 'omitted-day failed-stage unexpectedly succeeded'
[ "$derived_day" = "$omitted_day_fake" ] ||
  fail "failure-path derived day ${derived_day:-missing} is not $omitted_day_fake"
[ "$day_claim" -eq 1 ] ||
  fail "issue #210 day claim is missing or not $derived_day"
[ "$stage_receipts" -ge 1 ] || fail 'no stage receipts were published'
[ "$ordered" -eq 1 ] ||
  fail "stage receipts were dropped or reordered: ${receipt_stages[*]}"
[ "$real_launches" -eq 0 ] && [ "$fake_launches" -eq 0 ] ||
  fail "failure path reached a launcher: real=$real_launches fake=$fake_launches"
receipt_oracle "$case_receipt" "$derived_day" bootstrap-proposal \
  proposal-failed "$case_effects" ||
  fail 'omitted-day failure receipt was not an honest failure'
for forbidden in 'repo clone' 'pr create' 'pr merge' 'workflow run' 'run watch'; do
  if grep -Fq -- "$forbidden" "$case_log" "$case_effects"; then
    fail "omitted-day failure path reached a business effect: $forbidden"
  fi
done
pass omitted-day-receipts-survive-failure

# ---------------------------------------------------------------------------
# Issue #223 — manual production routing and controller-owned daily launch cap.
# ---------------------------------------------------------------------------

claim_call() {
  local root=$1 script=$2 census_failure=$3 operation=$4
  shift 4
  mkdir -p "$root/bin"
  ln -sf "$fake_gh" "$root/bin/gh"
  [ "$(PATH="$root/bin:$PATH" command -v gh)" = "$root/bin/gh" ] ||
    fail 'claim harness did not resolve the deterministic gh fixture'
  claim_stdout=$root/stdout
  claim_stderr=$root/stderr
  claim_rc=0
  env \
    PATH="$root/bin:$PATH" \
    GH_TOKEN=fake-repository-token \
    DAILY_AMARU_FAKE_GH_LOG="$root/gh.log" \
    DAILY_AMARU_FAKE_GH_COMMENTS="$root/comments" \
    DAILY_AMARU_FAKE_GH_CENSUS_FAIL="$census_failure" \
    DAILY_AMARU_STATE_DIR="$root/state" \
    DAILY_AMARU_RECEIPT="$root/receipt" \
    bash "$script" "$operation" "$@" \
    >"$claim_stdout" 2>"$claim_stderr" || claim_rc=$?
  claim_output=$(cat "$claim_stdout")
}

launch_cap_holds() {
  local script=$1 root
  root=$(mktemp -d "$tmp_root/launch-cap.XXXXXX")
  mkdir -p "$root/state"
  : >"$root/comments"
  : >"$root/gh.log"
  claim_call "$root" "$script" 0 claim-day 2026-08-19 \
    aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  [ "$claim_rc" -eq 0 ] && [ "$claim_output" = CLAIMED ] || return 1
  claim_call "$root" "$script" 0 claim-launch 2026-08-19 \
    aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  [ "$claim_rc" -eq 0 ] && [ "$claim_output" = CLAIMED ] || return 1
  claim_call "$root" "$script" 0 claim-day 2026-08-19 \
    bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  [ "$claim_rc" -ne 0 ] && [ "$claim_output" = 'BLOCKED launch-consumed' ] || return 1
  [ "$(grep -c 'launch-consumed' "$root/comments" || true)" -eq 1 ]
}

supersede_holds() {
  local script=$1 root before after
  root=$(mktemp -d "$tmp_root/supersede.XXXXXX")
  mkdir -p "$root/state"
  printf '<!-- daily-amaru day=2026-08-19 claim head=%s -->\n' \
    aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa >"$root/comments"
  : >"$root/gh.log"
  before=$(wc -l <"$root/comments")
  claim_call "$root" "$script" 0 claim-day 2026-08-19 \
    aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  [ "$claim_rc" -ne 0 ] && [ "$claim_output" = 'BLOCKED unchanged-head' ] || return 1
  claim_call "$root" "$script" 0 claim-day 2026-08-19 \
    bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  [ "$claim_rc" -eq 0 ] &&
    [ "$claim_output" = 'SUPERSEDED previous-head=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' ] || return 1
  after=$(wc -l <"$root/comments")
  [ "$after" -eq $((before + 1)) ] || return 1
  grep -Fqx '<!-- daily-amaru day=2026-08-19 claim head=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa -->' \
    "$root/comments"
}

census_failure_holds() {
  local script=$1 operation positive_root failure_root before after
  local -a arguments
  census_positive_controls=0
  census_forced_failures=0
  census_unchanged_stores=0
  for operation in claim-day claim-sha-attempt claim-launch; do
    case "$operation" in
      claim-sha-attempt)
        arguments=(1111111111111111111111111111111111111111 \
          aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa)
        ;;
      *)
        arguments=(2026-08-20 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa)
        ;;
    esac
    positive_root=$(mktemp -d "$tmp_root/census-positive.XXXXXX")
    failure_root=$(mktemp -d "$tmp_root/census-failure.XXXXXX")
    mkdir -p "$positive_root/state" "$failure_root/state"
    : >"$positive_root/comments"
    : >"$positive_root/gh.log"
    : >"$failure_root/comments"
    : >"$failure_root/gh.log"
    claim_call "$positive_root" "$script" 0 "$operation" "${arguments[@]}"
    [ "$claim_rc" -eq 0 ] && [ "$claim_output" = CLAIMED ] || return 1
    census_positive_controls=$((census_positive_controls + 1))
    before=$(sha256sum "$failure_root/comments" | awk '{print $1}')
    claim_call "$failure_root" "$script" 1 "$operation" "${arguments[@]}"
    after=$(sha256sum "$failure_root/comments" | awk '{print $1}')
    [ "$claim_rc" -ne 0 ] && [ "$claim_output" = 'BLOCKED census-unreadable' ] &&
      [ "$before" = "$after" ] || return 1
    census_forced_failures=$((census_forced_failures + 1))
    census_unchanged_stores=$((census_unchanged_stores + 1))
  done
}

claim_operations() {
  grep -E '^  claim-(day|sha-attempt|launch)\)$' "$1" |
    sed 's/^  //; s/)$//' | sort -u
}

claim_operation_sets_match() {
  local production=$1 fixture=$2
  [ "$(claim_operations "$production")" = "$(claim_operations "$fixture")" ] &&
    [ "$(claim_operations "$production" | grep -c . || true)" -eq 3 ]
}

declare -A issue_223_mutant_invariant=()
issue_223_declared_invariants=(
  INV-223-DISPATCH-ROUTING
  INV-223-DRY-RUN-CANONICAL-ENTRY
  INV-223-ONE-LAUNCH-PER-DAY
  INV-223-PRELAUNCH-SUPERSEDE
  INV-223-MARKER-CENSUS-FAILS-CLOSED
  INV-223-HEAD-CROSSES-PROCESS
  INV-223-PROOFS-NONVACUOUS
  INV-223-SCOPE-AND-EFFECT-FENCE
)
issue_223_declared_mutants=(
  routing-string-input
  dry-run-wrong-entry
  dry-run-path-tampered
  dry-run-step-key-added
  launch-cap-exit-open
  supersede-inverted
  census-open
  head-export-removed
  fixture-claim-launch-removed
  claim-after-launch
  legacy-marker-ignored
  legacy-verdict-corrupted
  sha-prefix-blinded
  launch-marker-blinded
  receipt-workflow-head-removed
  receipt-supersedes-removed
  receipt-launch-claim-removed
  receipt-launch-cap-write-removed
  scope-path-outside-fence
  history-base-unavailable
)
issue_225_allowed_paths=(
  .github/workflows/daily-amaru.yaml
  docs/daily-amaru.md
  scripts/daily-amaru-github.sh
  scripts/daily-amaru.sh
  tests/test-daily-amaru.sh
  tests/fixtures/daily-amaru/boundary-gh.sh
  tests/fixtures/daily-amaru/boundary-docker.sh
  tests/fixtures/daily-amaru/fake-transport.sh
  tests/fixtures/daily-amaru/boundary-nix.sh
  tests/fixtures/daily-amaru/boundary-resolver.sh
  tests/fixtures/daily-amaru/test-transport-boundary.sh
  specs/225-transport-value-channel/data-model.md
  specs/225-transport-value-channel/functions-model.md
  specs/225-transport-value-channel/modules-model.md
  specs/225-transport-value-channel/plan.md
  specs/225-transport-value-channel/spec.md
  specs/225-transport-value-channel/tasks.md
  specs/227-atomic-peer-snapshot-bump/data-model.md
  specs/227-atomic-peer-snapshot-bump/functions-model.md
  specs/227-atomic-peer-snapshot-bump/modules-model.md
  specs/227-atomic-peer-snapshot-bump/plan.md
  specs/227-atomic-peer-snapshot-bump/spec.md
  specs/227-atomic-peer-snapshot-bump/tasks.md
  specs/229-bounded-check-observation/data-model.md
  specs/229-bounded-check-observation/functions-model.md
  specs/229-bounded-check-observation/modules-model.md
  specs/229-bounded-check-observation/plan.md
  specs/229-bounded-check-observation/spec.md
  specs/229-bounded-check-observation/tasks.md
  tests/fixtures/daily-amaru/check-observation.sh
  tests/fixtures/daily-amaru/observation-gh.sh
)

register_223_mutant() {
  local invariant=$1 label=$2
  [ -z "${issue_223_mutant_invariant[$label]:-}" ] ||
    fail "duplicate #223 mutant registration: $label"
  issue_223_mutant_invariant[$label]=$invariant
}

reject_223_mutant() {
  local invariant=$1 label=$2
  shift 2
  reject_mutant "$@"
  register_223_mutant "$invariant" "$label"
}

evaluate_job_condition() {
  local condition=$1 event=$2 input=$3
  case "$condition" in
    "github.event_name == 'schedule' || (github.event_name == 'workflow_dispatch' && inputs.production)")
      [ "$event" = schedule ] ||
        { [ "$event" = workflow_dispatch ] && [ "$input" = true ]; }
      ;;
    "github.event_name == 'pull_request' || (github.event_name == 'workflow_dispatch' && !inputs.production)")
      [ "$event" = pull_request ] ||
        { [ "$event" = workflow_dispatch ] && [ "$input" = false ]; }
      ;;
    *) return 2 ;;
  esac
}

routing_truth_table_holds() {
  local file=$1 production dry row event input expected_production expected_dry
  local actual_production actual_dry
  production=$(job_condition "$file" daily-amaru-scheduled)
  dry=$(job_condition "$file" daily-amaru-dry-run)
  routing_census_rows=()
  routing_cases=(
    'schedule|false|1|0'
    'workflow_dispatch|true|1|0'
    'workflow_dispatch|false|0|1'
    'pull_request|false|0|1'
  )
  for row in "${routing_cases[@]}"; do
    IFS='|' read -r event input expected_production expected_dry <<<"$row"
    actual_production=0
    evaluate_job_condition "$production" "$event" "$input" && actual_production=1
    actual_dry=0
    evaluate_job_condition "$dry" "$event" "$input" && actual_dry=1
    [ "$actual_production" -eq "$expected_production" ] &&
      [ "$actual_dry" -eq "$expected_dry" ] || return 1
    routing_census_rows+=("event=$event production_input=$input production=$actual_production dry_run=$actual_dry")
  done
}

claim_backend_call() {
  local backend=$1 root=$2 script=$3 operation=$4
  shift 4
  if [ "$backend" = production ]; then
    claim_call "$root" "$script" 0 "$operation" "$@"
    return
  fi
  mkdir -p "$root/state"
  : >"$root/fixture.log"
  claim_stdout=$root/stdout
  claim_stderr=$root/stderr
  claim_rc=0
  env \
    FAKE_SCENARIO=changed \
    FAKE_LOG="$root/fixture.log" \
    DAILY_AMARU_STATE_DIR="$root/state" \
    DAILY_AMARU_RECEIPT="$root/receipt" \
    bash "$script" "$operation" "$@" \
    >"$claim_stdout" 2>"$claim_stderr" || claim_rc=$?
  claim_output=$(cat "$claim_stdout")
}

claim_verdict_table_holds() {
  local script=$1 backend=$2 row kind prior expected_output expected_rc
  local root store operation value marker before after appended
  local old_head=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  local new_head=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  claim_verdict_rows=(
    'day|none|CLAIMED|0'
    'day|legacy|SUPERSEDED previous-head=legacy|0'
    'day|same|BLOCKED unchanged-head|1'
    'day|same-succeeded|SUPERSEDED previous-head=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb|0'
    'day|changed|SUPERSEDED previous-head=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa|0'
    'day|launched|BLOCKED launch-consumed|1'
    'sha|none|CLAIMED|0'
    'sha|legacy|SUPERSEDED previous-head=legacy|0'
    'sha|same|BLOCKED unchanged-head|1'
    'sha|same-succeeded|SUPERSEDED previous-head=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb|0'
    'sha|changed|SUPERSEDED previous-head=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa|0'
    'launch|none|CLAIMED|0'
    'launch|launched|BLOCKED launch-consumed|1'
  )
  # Operation names ending in "-day" are strings, not arithmetic updates.
  # shellcheck disable=SC2100
  for row in "${claim_verdict_rows[@]}"; do
    IFS='|' read -r kind prior expected_output expected_rc <<<"$row"
    root=$(mktemp -d "$tmp_root/verdict-$backend.XXXXXX")
    mkdir -p "$root/state"
    if [ "$backend" = production ]; then
      store=$root/comments
      : >"$root/gh.log"
    else
      store=$root/state/markers
    fi
    : >"$store"
    case "$kind" in
      day)
        operation=claim-day
        value=2026-08-21
        marker="<!-- daily-amaru day=$value claim head=$new_head -->"
        ;;
      sha)
        operation=claim-sha-attempt
        value=1111111111111111111111111111111111111111
        marker="<!-- daily-amaru attempted-sha=$value head=$new_head -->"
        ;;
      launch)
        operation=claim-launch
        value=2026-08-21
        marker="<!-- daily-amaru day=$value launch-consumed head=$new_head -->"
        ;;
    esac
    case "$prior" in
      none) ;;
      legacy)
        if [ "$kind" = day ]; then
          printf '<!-- daily-amaru day=%s claim -->\n' "$value" >"$store"
        else
          printf '<!-- daily-amaru attempted-sha=%s -->\n' "$value" >"$store"
        fi
        ;;
      same)
        printf '%s\n' "${marker%"$new_head" -->}$new_head -->" >"$store"
        ;;
      same-succeeded)
        printf '%s\n' "${marker%"$new_head" -->}$new_head -->" >"$store"
        # The standing attempt completed: its receipt names the same value and
        # head, so the guard reads a success where `same` reads a refusal.
        if [ "$backend" = production ]; then
          printf '%s\n' '<!-- daily-amaru receipt -->' \
            '- day=2026-08-21' \
            '- stage=complete' \
            '- outcome=AWAITING' \
            "- workflow_head=$new_head" \
            '- upstream_sha=1111111111111111111111111111111111111111' \
            '- run_outcome=awaiting-integration' >>"$store"
        else
          printf '%s\n' '--- receipt ---' \
            'day=2026-08-21' \
            'stage=complete' \
            'outcome=AWAITING' \
            "workflow_head=$new_head" \
            'upstream_sha=1111111111111111111111111111111111111111' \
            'run_outcome=awaiting-integration' >>"$root/state/receipt-history"
        fi
        ;;
      changed)
        printf '%s\n' "${marker%"$new_head" -->}$old_head -->" >"$store"
        ;;
      launched)
        printf '<!-- daily-amaru day=%s launch-consumed head=%s -->\n' \
          "$value" "$old_head" >"$store"
        ;;
    esac
    before=$(wc -l <"$store")
    claim_backend_call "$backend" "$root" "$script" "$operation" "$value" "$new_head"
    if [ "$claim_output" != "$expected_output" ]; then
      printf 'claim verdict mismatch backend=%s kind=%s prior=%s expected=%s actual=%s\n' \
        "$backend" "$kind" "$prior" "$expected_output" "$claim_output" >&2
      return 1
    fi
    if { [ "$expected_rc" -eq 0 ] && [ "$claim_rc" -ne 0 ]; } ||
      { [ "$expected_rc" -ne 0 ] && [ "$claim_rc" -eq 0 ]; }; then
      printf 'claim exit mismatch backend=%s kind=%s prior=%s expected=%s actual=%s\n' \
        "$backend" "$kind" "$prior" "$expected_rc" "$claim_rc" >&2
      return 1
    fi
    after=$(wc -l <"$store")
    appended=0
    if [ "$expected_rc" -eq 0 ]; then
      [ "$after" -eq $((before + 1)) ] || return 1
      tail -n 1 "$store" | grep -Fqx -- "$marker" || return 1
      appended=1
    else
      [ "$after" -eq "$before" ] || return 1
    fi
    claim_verdict_observations+=("backend=$backend kind=$kind prior=$prior stdout=$claim_output exit=$expected_rc appended=$appended")
  done
}

production_claim_verdict_table_holds() {
  claim_verdict_table_holds "$1" production 2>/dev/null
}

effect_order_holds() {
  local script=$1 claim effect claim_line effect_line
  ordered_claim_effect_pairs=0
  run_case order-proof production token app key \
    daily:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb '' "$script"
  [ "$case_rc" -eq 0 ] || return 1
  for claim in 'claim-day ' 'claim-sha-attempt '; do
    claim_line=$(grep -n -m1 "^$claim" "$case_log" | cut -d: -f1)
    for effect in 'mutation:bootstrap ' 'mutation:image ' 'mutation:repin ' 'real-launch '; do
      effect_line=$(grep -n -m1 "^$effect" "$case_log" | cut -d: -f1)
      [ -n "$claim_line" ] && [ -n "$effect_line" ] &&
        [ "$claim_line" -lt "$effect_line" ] || return 1
      ordered_claim_effect_pairs=$((ordered_claim_effect_pairs + 1))
    done
  done
  claim_line=$(grep -n -m1 '^claim-launch ' "$case_log" | cut -d: -f1)
  effect_line=$(grep -n -m1 '^real-launch ' "$case_log" | cut -d: -f1)
  [ -n "$claim_line" ] && [ -n "$effect_line" ] &&
    [ "$claim_line" -lt "$effect_line" ] || return 1
  ordered_claim_effect_pairs=$((ordered_claim_effect_pairs + 1))
}

receipt_model_keys() {
  awk '
    /^## Receipt fields added$/ { inside = 1; next }
    inside && /^## / { exit }
    inside && /^\| `/ {
      sub(/^\| `/, "")
      sub(/`.*/, "")
      print
    }
  ' "$repo_root/specs/223-manual-production-trigger/data-model.md"
}

receipt_model_holds() {
  local script=$1 state key history
  state=$(mktemp -d "$tmp_root/receipt-model.XXXXXX")
  run_case failed-stage production token app key \
    daily:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa "$state" "$script"
  [ "$case_rc" -ne 0 ] || return 1
  run_case changed production token app key \
    daily:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb "$state" "$script"
  [ "$case_rc" -eq 0 ] || return 1
  history=$state/receipt-history
  mapfile -t receipt_declared_keys < <(receipt_model_keys)
  [ "${#receipt_declared_keys[@]}" -gt 0 ] || return 1
  for key in "${receipt_declared_keys[@]}"; do
    if ! grep -Eq "^$key=" "$history"; then
      printf 'receipt model key lacks durable evidence: %s\n' "$key" >&2
      return 1
    fi
  done
  if ! awk -v head=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb '
    BEGIN { RS="--- receipt ---\n"; found=0 }
    $0 ~ /(^|\n)stage=launch-cap(\n|$)/ &&
    $0 ~ /(^|\n)outcome=CLAIMED(\n|$)/ &&
    $0 ~ "(^|\\n)workflow_head=" head "(\\n|$)" &&
    $0 ~ /(^|\n)launch_claim=consumed(\n|$)/ { found++ }
    END { exit(found == 1 ? 0 : 1) }
  ' "$history"; then
    printf 'launch-cap receipt lacks exact workflow_head/outcome/launch_claim evidence\n' >&2
    return 1
  fi
}


receipt_model_mutant_rejected() {
  receipt_model_holds "$1" 2>/dev/null
}

paths_within_slice_fence() {
  local path allowed allowed_path
  for path in "$@"; do
    allowed=0
    for allowed_path in "${issue_225_allowed_paths[@]}"; do
      [ "$path" = "$allowed_path" ] && allowed=1
    done
    [ "$allowed" -eq 1 ] || return 1
  done
}

history_base_controls() {
  local seed=$tmp_root/history-seed
  local origin=$tmp_root/history-origin.git
  local positive=$tmp_root/history-positive
  local negative=$tmp_root/history-negative
  local control_base
  local changed_output negative_error=$tmp_root/history-negative.stderr
  local -a control_paths=()

  git init --quiet --initial-branch=main "$seed" || return 1
  git -C "$seed" config user.name history-control || return 1
  git -C "$seed" config user.email history-control@example.invalid || return 1
  mkdir -p "$seed/.github/workflows" "$seed/tests" || return 1
  cp "$workflow" "$seed/.github/workflows/daily-amaru.yaml" || return 1
  printf 'base\n' >"$seed/tests/test-daily-amaru.sh"
  git -C "$seed" add . || return 1
  git -C "$seed" commit --quiet -m base || return 1
  control_base=$(git -C "$seed" rev-parse HEAD) || return 1
  printf 'head\n' >"$seed/tests/test-daily-amaru.sh"
  git -C "$seed" commit --quiet -am head || return 1
  git clone --quiet --bare "$seed" "$origin" || return 1

  git clone --quiet --depth=1 --single-branch --branch main \
    "file://$origin" "$positive" || return 1
  [ "$(git -C "$positive" rev-list --count HEAD)" -eq 1 ] || return 1
  ! git -C "$positive" cat-file -e "$control_base^{commit}" 2>/dev/null || return 1
  ensure_history_commit "$positive" "$control_base" || return 1
  git -C "$positive" cat-file -e "$control_base^{commit}" 2>/dev/null || return 1
  production_job_untouched \
    "$positive/.github/workflows/daily-amaru.yaml" "$positive" "$control_base" || return 1
  changed_output=$(git -C "$positive" diff --name-only "$control_base" --) || return 1
  mapfile -t control_paths < <(printf '%s' "$changed_output")
  [ "${#control_paths[@]}" -gt 0 ] || return 1
  paths_within_slice_fence "${control_paths[@]}" || return 1

  git clone --quiet --depth=1 --single-branch --branch main \
    "file://$origin" "$negative" || return 1
  ! git -C "$negative" cat-file -e "$control_base^{commit}" 2>/dev/null || return 1
  git -C "$negative" remote set-url origin \
    "file://$tmp_root/missing-origin.git" || return 1
  if ensure_history_commit "$negative" "$control_base" \
    >"$tmp_root/history-negative.stdout" 2>"$negative_error"; then
    return 1
  fi
  grep -Fqx "HISTORY-BASE-UNAVAILABLE repository=$negative commit=$control_base fetch=failed" \
    "$negative_error" || return 1
  ! git -C "$negative" cat-file -e "$control_base^{commit}" 2>/dev/null || return 1

  register_223_mutant INV-223-PROOFS-NONVACUOUS history-base-unavailable
  history_positive_fetches=1
  history_negative_refusals=1
  history_dry_run_checks=1
  history_path_censuses=1
}

head_propagation_holds() {
  local script=$1 head=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  run_case head-property production token app key "github:$head" '' "$script"
  [ "$case_rc" -eq 0 ] || return 1
  grep -Fqx "claim-day 2026-07-31 $head" "$case_log" || return 1
  grep -Fqx "claim-sha-attempt 1111111111111111111111111111111111111111 $head" \
    "$case_log" || return 1
  grep -Fqx "claim-launch 2026-07-31 $head" "$case_log"
}

history_base_controls || fail 'history baseline controls did not hold'
routing_holds "$workflow" || fail 'typed dispatch routing is not exact'
routing_truth_table_holds "$workflow" || fail 'observed workflow conditions failed their truth table'
canonical_dry_run_entry_holds "$workflow" ||
  fail 'dry-run job does not run the canonical proof entry with the production job untouched'

for routing_row in "${routing_census_rows[@]}"; do
  printf 'ROUTING %s\n' "$routing_row"
done

# Both production-trigger orderings reach exactly one fake real-launch effect.
trigger_pairs=(schedule-dispatch dispatch-schedule)
launch_scenario_launches=()
for trigger_pair in "${trigger_pairs[@]}"; do
  first=${trigger_pair%-*}
  second=${trigger_pair#*-}
  pair_state="$tmp_root/cap-$trigger_pair"
  mkdir -p "$pair_state"
  run_case "$first-first" production token app key \
    daily:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa "$pair_state"
  require_success
  assert_log_count 1 '^real-launch '
  run_case "$second-second" production token app key \
    daily:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb "$pair_state"
  require_failure
  assert_no_launch
  assert_honest_failure_receipt day-claim
  assert_file_contains "$case_receipt" 'error=launch-consumed'
  launches=$(cat "$pair_state/real-launch-count")
  [ "$launches" -eq 1 ] || fail "$trigger_pair reached $launches launch effects"
  launch_scenario_launches+=("$launches")
  printf 'LAUNCH-SCENARIO first=%s second=%s day=2026-07-31 launches=%s refusal_stage=day-claim error=launch-consumed\n' \
    "$first" "$second" "$launches"
done

# A pre-launch death is blocked at the same head and superseded at a new head.
prelaunch_state="$tmp_root/prelaunch-state"
mkdir -p "$prelaunch_state"
run_case failed-stage production token app key \
  daily:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa "$prelaunch_state"
require_failure
assert_honest_failure_receipt bootstrap-proposal
markers_before=$(wc -l <"$prelaunch_state/markers")
receipts_before=$(grep -c '^--- receipt ---$' "$prelaunch_state/receipt-history" || true)
run_case prelaunch-unchanged production token app key \
  daily:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa "$prelaunch_state"
require_failure
assert_honest_failure_receipt day-claim
assert_file_contains "$case_receipt" 'error=unchanged-head'
run_case prelaunch-changed production token app key \
  daily:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb "$prelaunch_state"
require_success
markers_after=$(wc -l <"$prelaunch_state/markers")
receipts_after=$(grep -c '^--- receipt ---$' "$prelaunch_state/receipt-history" || true)
[ "$markers_after" -gt "$markers_before" ] || fail 'supersede did not append markers'
[ "$receipts_after" -gt "$receipts_before" ] || fail 'supersede lost prior receipts'
assert_file_contains "$case_receipt" \
  'claim_supersedes=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
printf 'SUPERSEDE-SCENARIO recorded_head=%s current_head=%s verdict=SUPERSEDED superseded_head=%s markers_before=%s markers_after=%s receipts_before=%s receipts_after=%s\n' \
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  "$markers_before" "$markers_after" "$receipts_before" "$receipts_after"

# A legacy headless claim differs from every valid current head and is retained.
legacy_state="$tmp_root/legacy-state"
mkdir -p "$legacy_state"
printf '%s\n%s\n' \
  '<!-- daily-amaru day=2026-07-31 claim -->' \
  '<!-- daily-amaru attempted-sha=1111111111111111111111111111111111111111 -->' \
  >"$legacy_state/markers"
legacy_before=$(wc -l <"$legacy_state/markers")
run_case legacy-supersede production token app key \
  daily:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb "$legacy_state"
require_success
legacy_after=$(wc -l <"$legacy_state/markers")
[ "$legacy_after" -gt "$legacy_before" ] || fail 'legacy supersede did not append'
assert_file_contains "$legacy_state/markers" '<!-- daily-amaru day=2026-07-31 claim -->'
assert_file_contains "$case_receipt" 'claim_supersedes=legacy'
printf 'SUPERSEDE-SCENARIO recorded_head=legacy current_head=%s verdict=SUPERSEDED superseded_head=legacy markers_before=%s markers_after=%s\n' \
  bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb "$legacy_before" "$legacy_after"

# The production transport itself fails closed when its census command fails.
census_failure_holds "$transport" || fail 'failed marker census admitted a claim'
launch_cap_holds "$transport" || fail 'production transport admitted a post-launch claim'
supersede_holds "$transport" || fail 'production transport violated the supersede rule'

# The controller derives GITHUB_SHA once and every claim child observes it.
head_propagation_holds "$controller" || fail 'workflow head did not cross every claim child'
invalid_heads=(absent daily:not-a-sha)
for invalid_head in "${invalid_heads[@]}"; do
  run_case "head-${invalid_head%%:*}" test token '' '' "$invalid_head"
  require_failure
  assert_honest_failure_receipt head-resolution
  assert_log_count 0 '^claim-(day|sha-attempt|launch) '
done

# Production and deterministic transports expose exactly the same claim set.
claim_operation_sets_match "$transport" "$fake_transport" ||
  fail 'fixture and production claim operation sets differ'

# The behavioral table is one oracle driven against both implementations.
claim_verdict_observations=()
claim_verdict_table_holds "$transport" production ||
  fail 'production transport failed the claim verdict table'
claim_verdict_table_holds "$fake_transport" fixture ||
  fail 'deterministic transport failed the claim verdict table'
claim_verdict_rows_per_backend=${#claim_verdict_rows[@]}
claim_verdict_backends=2
printf 'CLAIM-VERDICT-TABLE rows_per_backend=%s backends=%s observations=%s\n' \
  "$claim_verdict_rows_per_backend" "$claim_verdict_backends" \
  "${#claim_verdict_observations[@]}"

# Actual effect-log indexes prove each durable guard precedes what it guards.
effect_order_holds "$controller" ||
  fail 'durable claim operations did not precede their guarded effects'

# Every receipt key added by the data model is exercised in durable history.
receipt_model_holds "$controller" ||
  fail 'declared #223 receipt fields lack executing durable evidence'

# Applied-then-rejected mutants, one for every critical #223 protection.
# shellcheck disable=SC2016
reject_223_mutant INV-223-DISPATCH-ROUTING routing-string-input \
  dispatch-string-form.yaml "$workflow" \
  's/inputs[.]production/github.event.inputs.production/g' \
  'github.event.inputs.production' \
  'the truthy string-form dispatch input' routing_truth_table_holds

reject_223_mutant INV-223-DRY-RUN-CANONICAL-ENTRY dry-run-wrong-entry \
  dry-run-wrong-entry.yaml "$workflow" \
  's|nix develop --quiet -c just ci|tests/test-daily-amaru.sh|' \
  'tests/test-daily-amaru.sh' \
  'a dry-run job that bypasses the canonical entry' canonical_dry_run_entry_holds

# shellcheck disable=SC2016
reject_223_mutant INV-223-DRY-RUN-CANONICAL-ENTRY dry-run-path-tampered \
  dry-run-path-tampered.yaml "$workflow" \
  's/github\.event\.pull_request\.head\.sha/github.sha/' \
  'github.sha' \
  'a dry-run checkout redirected away from the candidate head' canonical_dry_run_entry_holds

reject_223_mutant INV-223-DRY-RUN-CANONICAL-ENTRY dry-run-step-key-added \
  dry-run-step-key-added.yaml "$workflow" \
  '/^      - name: Run the canonical proof entry$/a\
        if: github.event_name == '\''deployment'\''' \
  "        if: github.event_name == 'deployment'" \
  'an added key that makes the canonical entry conditional' canonical_dry_run_entry_holds

reject_223_mutant INV-223-ONE-LAUNCH-PER-DAY launch-cap-exit-open \
  launch-cap-open.sh "$transport" \
  's/return 1 # launch-consumed-final/return 0 # launch-consumed-final/' \
  'return 0 # launch-consumed-final' \
  'a launch-consumed verdict that exits successfully' launch_cap_holds

# shellcheck disable=SC2016
reject_223_mutant INV-223-PRELAUNCH-SUPERSEDE supersede-inverted \
  supersede-inverted.sh "$transport" \
  's/if \[ "$recorded_head" = "$head" \]; then # unchanged-head-guard/if [ "$recorded_head" != "$head" ]; then # unchanged-head-guard/' \
  'if [ "$recorded_head" != "$head" ]; then # unchanged-head-guard' \
  'an inverted unchanged-head guard' supersede_holds

# shellcheck disable=SC2016
reject_223_mutant INV-223-MARKER-CENSUS-FAILS-CLOSED census-open \
  census-open.sh "$transport" \
  's/if ! census=$(marker_census); then # census-fails-closed/if census=$(marker_census); then # census-fails-closed/' \
  'if census=$(marker_census); then # census-fails-closed' \
  'a census failure interpreted as an empty census' census_failure_holds

head_mutant="$mutant_root/controller-no-head-export.sh"
sed '/^export DAILY_AMARU_HEAD=/d' "$controller" >"$head_mutant"
grep -Fq 'export DAILY_AMARU_HEAD=' "$controller" ||
  fail 'head propagation mutation has no production line to remove'
! grep -Fq 'export DAILY_AMARU_HEAD=' "$head_mutant" ||
  fail 'head propagation mutation did not apply'
if head_propagation_holds "$head_mutant"; then
  fail 'controller without head export passed propagation proof'
fi
register_223_mutant INV-223-HEAD-CROSSES-PROCESS head-export-removed

fixture_claim_mutant="$mutant_root/fake-transport-no-claim-launch.sh"
sed 's/^  claim-launch)$/  claim-launch-disabled)/' "$fake_transport" \
  >"$fixture_claim_mutant"
grep -Fqx '  claim-launch-disabled)' "$fixture_claim_mutant" ||
  fail 'fixture claim-set mutation did not apply'
if claim_operation_sets_match "$transport" "$fixture_claim_mutant"; then
  fail 'claim operation reconciliation accepted a missing fixture operation'
fi
register_223_mutant INV-223-PROOFS-NONVACUOUS fixture-claim-launch-removed

# F1: move the launch claim after the launch effect; the log-order proof must kill it.
order_mutant="$mutant_root/controller-claim-after-launch.sh"
awk '
  /^  claim_operation launch-cap claim-launch no / { next }
  /^  receipt\[launch_claim\]=consumed$/ { next }
  /^  write_receipt launch-cap CLAIMED$/ { next }
  /^  fail_stage launch submission-failed$/ { after_launch_failure = 1 }
  { print }
  after_launch_failure && /^fi$/ {
    print ""
    print "if [ \"$mode\" = production ]; then"
    print "  claim_operation launch-cap claim-launch no \"$day\" \"$head\""
    print "  receipt[launch_claim]=consumed"
    print "  write_receipt launch-cap CLAIMED"
    print "fi"
    after_launch_failure = 0
  }
' "$controller" >"$order_mutant"
[ "$(grep -n '^  claim_operation launch-cap ' "$order_mutant" | cut -d: -f1)" -gt \
  "$(grep -n '^if ! launch_request=' "$order_mutant" | cut -d: -f1)" ] ||
  fail 'claim-after-launch mutation did not apply'
if effect_order_holds "$order_mutant"; then
  fail 'effect-order proof accepted a launch claim after the launcher'
fi
register_223_mutant INV-223-ONE-LAUNCH-PER-DAY claim-after-launch

# F2: production-transport defect classes are all judged by the shared table.
# shellcheck disable=SC2016
reject_223_mutant INV-223-PRELAUNCH-SUPERSEDE legacy-marker-ignored \
  legacy-marker-ignored.sh "$transport" \
  's/if \[ "$line" = "$legacy_marker" \]; then/if [ "$line" = "ignored-$legacy_marker" ]; then/' \
  'if [ "$line" = "ignored-$legacy_marker" ]; then' \
  'a legacy claim ignored by production' production_claim_verdict_table_holds
# shellcheck disable=SC2016
reject_223_mutant INV-223-PRELAUNCH-SUPERSEDE legacy-verdict-corrupted \
  legacy-verdict-corrupted.sh "$transport" \
  's/previous_head=legacy/previous_head=unrecognized/' \
  'previous_head=unrecognized' \
  'a legacy claim reported with an unrecognized predecessor' production_claim_verdict_table_holds
# shellcheck disable=SC2016
reject_223_mutant INV-223-PRELAUNCH-SUPERSEDE sha-prefix-blinded \
  sha-prefix-blinded.sh "$transport" \
  's/attempted-sha=$value head=/attempted-sha-blind=$value head=/' \
  'attempted-sha-blind=$value head=' \
  'a SHA claim scan with the wrong marker prefix' production_claim_verdict_table_holds
reject_223_mutant INV-223-ONE-LAUNCH-PER-DAY launch-marker-blinded \
  launch-marker-blinded.sh "$transport" \
  's/launch-consumed\\ head=/launch-blind\\ head=/g' \
  'launch-blind\ head=' \
  'a launch claim scan blind to consumed markers' production_claim_verdict_table_holds

# F5: remove each modeled receipt artifact and require executing evidence to fail.
# The mutation expressions intentionally match literal shell variable syntax.
# shellcheck disable=SC2016
reject_223_mutant INV-223-HEAD-CROSSES-PROCESS receipt-workflow-head-removed \
  receipt-workflow-head-removed.sh "$controller" \
  '/^receipt\[workflow_head\]=\$head$/d' \
  '!receipt[workflow_head]=$head' \
  'a controller that omits workflow_head receipts' receipt_model_mutant_rejected
# shellcheck disable=SC2016
reject_223_mutant INV-223-PRELAUNCH-SUPERSEDE receipt-supersedes-removed \
  receipt-supersedes-removed.sh "$controller" \
  '/receipt\[claim_supersedes\]=\$previous_head/d' \
  '!receipt[claim_supersedes]=$previous_head' \
  'a controller that omits claim_supersedes receipts' receipt_model_mutant_rejected
reject_223_mutant INV-223-ONE-LAUNCH-PER-DAY receipt-launch-claim-removed \
  receipt-launch-claim-removed.sh "$controller" \
  '/^  receipt\[launch_claim\]=consumed$/d' \
  '!receipt[launch_claim]=consumed' \
  'a controller that omits launch_claim receipts' receipt_model_mutant_rejected
reject_223_mutant INV-223-ONE-LAUNCH-PER-DAY receipt-launch-cap-write-removed \
  receipt-launch-cap-write-removed.sh "$controller" \
  '/^  write_receipt launch-cap CLAIMED$/d' \
  '!write_receipt launch-cap CLAIMED' \
  'a controller that never durably writes the launch-cap receipt' receipt_model_mutant_rejected

allowed_path_count=${#issue_225_allowed_paths[@]}
changed_paths_output=$(git -C "$repo_root" diff --name-only "$pre_slice_base" --) ||
  fail 'history baseline path diff is unreadable'
mapfile -t changed_paths < <(printf '%s' "$changed_paths_output")
paths_within_slice_fence "${changed_paths[@]}" || fail 'changed path outside slice fence'
scope_mutant_paths=("${changed_paths[@]}" outside/issue-225-mutant)
[ "${#scope_mutant_paths[@]}" -eq $((${#changed_paths[@]} + 1)) ] ||
  fail 'scope path mutation did not apply'
if paths_within_slice_fence "${scope_mutant_paths[@]}"; then
  fail 'scope fence accepted an out-of-scope path'
fi
register_223_mutant INV-223-SCOPE-AND-EFFECT-FENCE scope-path-outside-fence

# Derive the effect fence from artifacts produced by the executing harness.
mapfile -t issue_223_effect_artifacts < <(
  find "$tmp_root" -type f \( -name transport.log -o -name gh.log -o -name effects \)
)
forbidden_effects=0
credential_material_hits=0
for effect_artifact in "${issue_223_effect_artifacts[@]}"; do
  for forbidden in 'gh workflow run' 'repo clone' 'pr create' 'pr merge' 'run watch'; do
    if grep -Fq -- "$forbidden" "$effect_artifact"; then
      forbidden_effects=$((forbidden_effects + 1))
    fi
  done
  for credential_sentinel in "$secret_value" "$prod_id" "$prod_app" "$prod_key"; do
    if grep -Fq -- "$credential_sentinel" "$effect_artifact"; then
      credential_material_hits=$((credential_material_hits + 1))
    fi
  done
done
[ "$forbidden_effects" -eq 0 ] || fail "effect fence observed $forbidden_effects forbidden effects"
[ "$credential_material_hits" -eq 0 ] ||
  fail "effect fence observed $credential_material_hits credential material hits"

# The census itself is executable: registry drift or an untested invariant fails.
mapfile -t registered_mutants < <(printf '%s\n' "${!issue_223_mutant_invariant[@]}" | sort)
mapfile -t declared_mutants < <(printf '%s\n' "${issue_223_declared_mutants[@]}" | sort)
proof_residuals=$(comm -3 \
  <(printf '%s\n' "${registered_mutants[@]}") \
  <(printf '%s\n' "${declared_mutants[@]}") | grep -c . || true)
[ "$proof_residuals" -eq 0 ] ||
  fail "#223 mutant registry drift: registered=${registered_mutants[*]} declared=${declared_mutants[*]}"
for invariant in "${issue_223_declared_invariants[@]}"; do
  invariant_mutants=0
  for mutant in "${registered_mutants[@]}"; do
    [ "${issue_223_mutant_invariant[$mutant]}" = "$invariant" ] &&
      invariant_mutants=$((invariant_mutants + 1))
  done
  [ "$invariant_mutants" -gt 0 ] || fail "invariant has no rejecting mutant: $invariant"
done

# Re-run the live observations after mutant predicates so all reported counts
# are measurements of the candidate, never side effects left by a rejected mutant.
routing_truth_table_holds "$workflow" || fail 'final routing census failed'
census_failure_holds "$transport" || fail 'final marker census failed'
effect_order_holds "$controller" || fail 'final effect-order census failed'
claim_verdict_observations=()
claim_verdict_table_holds "$transport" production || fail 'final production verdict census failed'
claim_verdict_table_holds "$fake_transport" fixture || fail 'final fixture verdict census failed'
receipt_model_holds "$controller" || fail 'final receipt-model census failed'
claim_operation_count=$(claim_operations "$transport" | grep -c . || true)
production_jobs=$(grep -Ec '^  daily-amaru-scheduled:$' "$workflow" || true)
controller_callers=$(grep -Ec '^[[:space:]]+scripts/daily-amaru[.]sh$' "$workflow" || true)
launches_per_day=${launch_scenario_launches[0]}
for launches in "${launch_scenario_launches[@]}"; do
  [ "$launches" -eq "$launches_per_day" ] || fail 'launch scenario counts disagree'
done
routing_mutants=0
dry_run_mutants=0
launch_cap_mutants=0
for mutant in "${registered_mutants[@]}"; do
  case "${issue_223_mutant_invariant[$mutant]}" in
    INV-223-DISPATCH-ROUTING) routing_mutants=$((routing_mutants + 1)) ;;
    INV-223-DRY-RUN-CANONICAL-ENTRY) dry_run_mutants=$((dry_run_mutants + 1)) ;;
    INV-223-ONE-LAUNCH-PER-DAY) launch_cap_mutants=$((launch_cap_mutants + 1)) ;;
  esac
done
printf 'DISPATCH-ROUTING rows=%s production_jobs=%s controller_callers=%s mutants_rejected=%s\n' \
  "${#routing_census_rows[@]}" "$production_jobs" "$controller_callers" \
  "$routing_mutants"
printf 'DRY-RUN-ENTRY canonical=1 dev_shell=1 production_job_untouched=1 whole_block=1 mutants_rejected=%s\n' \
  "$dry_run_mutants"
printf 'LAUNCH-CAP trigger_pairs=%s launches_per_day=%s refusal=launch-consumed ordered_claim_effect_pairs=%s mutants_rejected=%s\n' \
  "${#trigger_pairs[@]}" "$launches_per_day" "$ordered_claim_effect_pairs" \
  "$launch_cap_mutants"
printf 'PRELAUNCH-SUPERSEDE unchanged=blocked changed=admitted legacy=admitted append_only=1 table_rows=%s\n' \
  "$claim_verdict_rows_per_backend"
printf 'CENSUS-FAILS-CLOSED operations=%s positive_controls=%s forced_failures=%s comments_unchanged=%s\n' \
  "$claim_operation_count" "$census_positive_controls" "$census_forced_failures" \
  "$census_unchanged_stores"
printf 'HEAD-PROPAGATION source=GITHUB_SHA claims_observed=%s invalid_heads_refused=%s receipt_keys=%s\n' \
  "$claim_operation_count" "${#invalid_heads[@]}" "${#receipt_declared_keys[@]}"
printf 'CLAIM-OPERATION-RECONCILIATION operations=%s matched=1 verdict_observations=%s\n' \
  "$claim_operation_count" "${#claim_verdict_observations[@]}"
printf 'HISTORY-BASE-CONTROLS positive_fetches=%s negative_refusals=%s dry_run_checks=%s path_censuses=%s mutants_rejected=1\n' \
  "$history_positive_fetches" "$history_negative_refusals" \
  "$history_dry_run_checks" "$history_path_censuses"
printf 'SCOPE-EFFECT-FENCE changed_paths=%s allowed_paths=%s effect_artifacts=%s forbidden_effects=%s credential_material_hits=%s\n' \
  "${#changed_paths[@]}" "$allowed_path_count" "${#issue_223_effect_artifacts[@]}" \
  "$forbidden_effects" "$credential_material_hits"
printf 'PROOF-CENSUS invariants=%s claim_operations=%s mutants_rejected=%s residuals=%s\n' \
  "${#issue_223_declared_invariants[@]}" "$claim_operation_count" \
  "${#registered_mutants[@]}" "$proof_residuals"
pass issue-223-manual-production-cap

# The observation surface is a claim about another repository, and every
# scheduled run between 2026-08-23 and 2026-09-01 was red because that claim was
# false: the transport waited on a workflow named "Bootstrap CI" and four check
# names lifted from this repository's own CI, none of which
# `lambdasistemi/amaru-bootstrap` publishes. The mechanism tests could not see
# it -- their fixtures asserted the same names back. Nothing here reaches the
# network; this pins the shipped defaults against the surface recorded in
# docs/daily-amaru.md so a rename must break a test rather than a nightly.
bootstrap_surface_default() {
  local variable=$1 override=$2 source=${3:-$transport}
  sed -n "s/^$variable=\${$override:-\(.*\)}\$/\1/p" "$source"
}

bootstrap_surface_defaults_hold() {
  local source=${1:-$transport}
  local workflow checks
  workflow=$(bootstrap_surface_default bootstrap_check_workflow \
    DAILY_AMARU_BOOTSTRAP_CHECK_WORKFLOW "$source")
  checks=$(bootstrap_surface_default bootstrap_required_checks \
    DAILY_AMARU_BOOTSTRAP_CHECKS "$source")
  [ "$workflow" = 'CI' ] || return 1
  [ "$checks" = 'Build Gate,Live Bootstrap Producer' ] || return 1
}

bootstrap_surface_defaults_hold ||
  fail "shipped bootstrap surface is not lambdasistemi/amaru-bootstrap's: workflow=$(bootstrap_surface_default bootstrap_check_workflow DAILY_AMARU_BOOTSTRAP_CHECK_WORKFLOW) checks=$(bootstrap_surface_default bootstrap_required_checks DAILY_AMARU_BOOTSTRAP_CHECKS)"

# The dead names must not survive anywhere in the production surface: the
# consumer's own required checks are a separate array and must not be reachable
# as a bootstrap default again.
for dead_name in 'Bootstrap CI' 'Build,Run unit Tests,Check code quality,publish-images'; do
  if grep -Fq -- "$dead_name" "$transport" "$controller"; then
    fail "retired bootstrap surface name is still shipped: $dead_name"
  fi
done

# A check that has never failed is not evidence. Both halves of the claim are
# mutated back to the exact strings that produced the eleven red nights.
# shellcheck disable=SC2016
reject_mutant bootstrap-surface-workflow.sh "$transport" \
  's#^bootstrap_check_workflow=${DAILY_AMARU_BOOTSTRAP_CHECK_WORKFLOW:-CI}$#bootstrap_check_workflow=${DAILY_AMARU_BOOTSTRAP_CHECK_WORKFLOW:-Bootstrap CI}#' \
  'DAILY_AMARU_BOOTSTRAP_CHECK_WORKFLOW:-Bootstrap CI' \
  'a duration probe naming a workflow amaru-bootstrap does not publish' \
  bootstrap_surface_defaults_hold
# shellcheck disable=SC2016
reject_mutant bootstrap-surface-checks.sh "$transport" \
  's#^bootstrap_required_checks=${DAILY_AMARU_BOOTSTRAP_CHECKS:-Build Gate,Live Bootstrap Producer}$#bootstrap_required_checks=${DAILY_AMARU_BOOTSTRAP_CHECKS:-Build,Run unit Tests,Check code quality,publish-images}#' \
  'DAILY_AMARU_BOOTSTRAP_CHECKS:-Build,Run unit Tests' \
  'required bootstrap checks copied from this repository CI' \
  bootstrap_surface_defaults_hold
printf 'BOOTSTRAP-SURFACE workflow=CI checks=2 retired_names=2 mutants_rejected=2\n'
pass bootstrap-surface-defaults

# Issue #225: execute the real transport at a local git boundary. The focused
# fixture owns its repositories under mktemp and never reads this checkout's
# history.
"$repo_root/tests/fixtures/daily-amaru/test-transport-boundary.sh" "$repo_root" all

# INV-225-E1: the boundary proof must not change its verdict with the runner's
# command inventory. Reproduce the CI runner shape by removing one member of
# the production transport's scheduled census from an otherwise seeded host
# PATH. The fixture itself must supply that member instead of inheriting it.
boundary_host_bin="$tmp_root/boundary-host/bin"
boundary_host_log="$tmp_root/boundary-host.log"
seed_scheduled_path "$boundary_host_bin" without-rg
for command in cat chmod cp cmp env find gpg ln mktemp mv od rm sort; do
  target=$(command -v "$command")
  ln -sf "$target" "$boundary_host_bin/$command"
done
if PATH="$boundary_host_bin" command -v rg >/dev/null 2>&1; then
  fail 'boundary host PATH still resolves the omitted scheduled command: rg'
fi
if ! PATH="$boundary_host_bin" "$bash_binary" \
  "$repo_root/tests/fixtures/daily-amaru/test-transport-boundary.sh" \
  "$repo_root" pollution >"$boundary_host_log" 2>&1; then
  cat "$boundary_host_log" >&2
  fail 'boundary proof verdict depends on host PATH without rg'
fi
