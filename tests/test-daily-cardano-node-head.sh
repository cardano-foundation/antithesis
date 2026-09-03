#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
controller="$repo_root/scripts/daily-cardano-node-head.sh"
fake_transport="$repo_root/tests/fixtures/daily-cardano-node-head/fake-transport.sh"
functions_model="$repo_root/specs/215-immutable-cardano-node-head-candidate/functions-model.md"
data_model="$repo_root/specs/215-immutable-cardano-node-head-candidate/data-model.md"

tmp_root=$(mktemp -d)
trap 'rm -rf "$tmp_root"' EXIT

upstream_sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
digest_hex=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
candidate_ref="ghcr.io/cardano-foundation/cardano-node:${upstream_sha}@sha256:${digest_hex}"
image_repository=ghcr.io/cardano-foundation/cardano-node
upstream_origin=https://github.com/IntersectMBO/cardano-node.git
upstream_ref=refs/heads/master
expected_node_services=(p1 p2 p3 p4 relay1 relay2 relay3)

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

assert_log_count() {
  local expected=$1
  local pattern=$2
  local actual
  actual=$(grep -Ec -- "$pattern" "$case_log" || true)
  [ "$actual" -eq "$expected" ] ||
    fail "scenario=$case_name expected $expected log matches for $pattern, found $actual"
}

assert_no_submit() {
  assert_log_count 0 '^fake-submit '
}

last_receipt_block() {
  awk '
    BEGIN { block = "" }
    /^schema=/ { block = $0 ORS; next }
    { block = block $0 ORS }
    END { printf "%s", block }
  ' "$case_receipt"
}

assert_last_receipt_contains() {
  local literal=$1
  local block
  block=$(last_receipt_block)
  grep -Fqx -- "$literal" <<<"$block" ||
    fail "last receipt record lacks exact line: $literal"
}

assert_last_receipt_lacks() {
  local pattern=$1
  local block
  block=$(last_receipt_block)
  if grep -Eq -- "$pattern" <<<"$block"; then
    fail "last receipt record unexpectedly matches: $pattern"
  fi
}

assert_honest_failure_receipt() {
  local stage=$1
  local reason=$2
  local forbidden=''
  assert_last_receipt_contains "stage=$stage"
  assert_last_receipt_contains 'outcome=FAILED'
  assert_last_receipt_contains "error=$reason"
  assert_last_receipt_contains 'schema=CandidateReceiptV1'
  assert_last_receipt_lacks \
    'outcome=(OBSERVED|PUBLISHED|PROVEN|RENDERED|VERIFIED|VALIDATED|PREPARED)'
  case "$stage" in
    resolve-upstream)
      forbidden='^(upstream_sha|candidate_ref|binary_revision|rendered_model|topology_services|topology_image|submission)='
      ;;
    publish-candidate)
      forbidden='^(candidate_ref|binary_revision|rendered_model|topology_services|topology_image|submission)='
      ;;
    prove-revision)
      forbidden='^(binary_revision|rendered_model|topology_services|topology_image|submission)='
      ;;
    render-topology)
      forbidden='^(rendered_model|topology_services|topology_image|submission)='
      ;;
    verify-topology)
      forbidden='^(topology_services|topology_image|submission)='
      ;;
    validate-compose | submit-candidate)
      forbidden='^submission='
      ;;
    *) fail "unknown failing receipt stage: $stage" ;;
  esac
  assert_last_receipt_lacks "$forbidden"
}

transport_operation_surface() {
  awk '
    /^case "\$operation" in$/ { in_op = 1; next }
    in_op && /^esac$/ { exit }
    in_op && /^  [a-z0-9-]+\)$/ {
      name = $1
      sub(/\)$/, "", name)
      print name
    }
  ' "$fake_transport" | sort
}

modeled_transport_operations() {
  awk -F'|' '
    /^## Transport operation surface/ { in_surface = 1; next }
    in_surface && /^Signature-level constraints:/ { exit }
    in_surface && $2 ~ /`[a-z0-9-]+`/ {
      operation = $2
      gsub(/[^a-z0-9-]/, "", operation)
      print operation
    }
  ' "$functions_model" | sort
}

modeled_rendered_model_operations() {
  awk -F'|' '
    $2 ~ /`[a-z0-9-]+`/ && $3 ~ /`rendered_model/ {
      operation = $2
      gsub(/[^a-z0-9-]/, "", operation)
      print operation
    }
  ' "$functions_model" | sort
}

modeled_receipt_fields() {
  awk -F'|' '
    /^## D-05 / { in_receipt = 1; next }
    in_receipt && /^State invariants:/ { exit }
    in_receipt && $2 ~ /`[a-z_]+`/ {
      cell = $2
      while (match(cell, /`[a-z_]+`/)) {
        print substr(cell, RSTART + 1, RLENGTH - 2)
        cell = substr(cell, RSTART + RLENGTH)
      }
    }
  ' "$data_model" | sort
}

assert_complete_receipt() {
  local expected_mode=$1
  local actual_fields expected_fields field modeled_fields
  declare -A expected=(
    [schema]=CandidateReceiptV1
    [stage]=submit-candidate
    [outcome]=PREPARED
    [mode]="$expected_mode"
    [upstream_origin]="$upstream_origin"
    [upstream_ref]="$upstream_ref"
    [upstream_sha]="$upstream_sha"
    [candidate_ref]="$candidate_ref"
    [binary_revision]="$upstream_sha"
    [rendered_model]="$case_state/rendered-model"
    [topology_services]="${#expected_node_services[@]}"
    [topology_image]="$candidate_ref"
    [submission]="fake://$upstream_sha"
  )
  modeled_fields=$(modeled_receipt_fields | grep -vx error)
  expected_fields=$(printf '%s\n' "${!expected[@]}" | sort)
  [ "$modeled_fields" = "$expected_fields" ] ||
    fail "complete receipt witness inventory differs from D-05
modeled:
$modeled_fields
witnessed:
$expected_fields"
  actual_fields=$(last_receipt_block | sed '/^$/d; s/=.*//' | sort)
  [ "$actual_fields" = "$modeled_fields" ] ||
    fail "complete receipt field inventory differs from D-05
modeled:
$modeled_fields
actual:
$actual_fields"
  while IFS= read -r field; do
    assert_last_receipt_contains "$field=${expected[$field]}"
  done <<<"$modeled_fields"
  assert_last_receipt_lacks '^error='
}

case_number=0
run_case() {
  case_name=$1
  local mode=${2:-test}
  local transport_path=${3:-$fake_transport}
  local repository=${4:-$image_repository}
  local -a controller_env=()
  case_number=$((case_number + 1))
  case_dir="$tmp_root/$case_number-$case_name"
  case_state="$case_dir/state"
  case_log="$case_dir/transport.log"
  case_receipt="$case_dir/receipt"
  case_stdout="$case_dir/stdout"
  case_stderr="$case_dir/stderr"
  mkdir -p "$case_state"
  : >"$case_log"
  : >"$case_receipt"

  controller_env=(
    "FAKE_SCENARIO=$case_name"
    "FAKE_LOG=$case_log"
    "HEAD_CANDIDATE_TRANSPORT=$transport_path"
    "HEAD_CANDIDATE_MODE=$mode"
    "HEAD_CANDIDATE_STATE_DIR=$case_state"
    "HEAD_CANDIDATE_RECEIPT=$case_receipt"
  )
  if [ "$repository" != DEFAULT ]; then
    controller_env+=("HEAD_CANDIDATE_IMAGE_REPOSITORY=$repository")
  fi

  case_rc=0
  env -u HEAD_CANDIDATE_IMAGE_REPOSITORY "${controller_env[@]}" \
    "$controller" >"$case_stdout" 2>"$case_stderr" || case_rc=$?
}

require_success() {
  [ "$case_rc" -eq 0 ] ||
    fail "scenario=$case_name expected success, exit=$case_rc: $(tr '\n' ' ' <"$case_stderr")"
}

require_failure() {
  [ "$case_rc" -ne 0 ] || fail "scenario=$case_name expected failure"
}

normalized_interaction_log() {
  local log_file=$1
  local state_path=$2
  sed \
    -e "s|$state_path|<state>|g" \
    -e 's/mode=\(test\|manual\)/mode=<mode>/g' \
    "$log_file"
}

run_rejection() {
  local scenario=$1
  local stage=$2
  local reason=$3
  shift 3
  run_case "$scenario"
  require_failure
  if [ "$stage" = submit-candidate ]; then
    assert_log_count 1 '^fake-submit '
  else
    assert_no_submit
  fi
  while [ "$#" -gt 0 ]; do
    assert_log_count 0 "^$1 "
    shift
  done
  assert_honest_failure_receipt "$stage" "$reason"
  pass "$scenario"
}

if [ ! -x "$fake_transport" ]; then
  fail "fake transport is absent or not executable: $fake_transport"
fi

if [ ! -x "$controller" ]; then
  fail "controller behavior absent: expected executable $controller"
fi

if [ ! -f "$functions_model" ]; then
  fail "functions model absent: $functions_model"
fi

if [ ! -f "$data_model" ]; then
  fail "data model absent: $data_model"
fi

run_case prepared
require_success
assert_complete_receipt test
assert_log_count 1 '^resolve-upstream '
assert_log_count 1 '^publish-candidate '
assert_log_count 1 '^prove-revision '
assert_log_count 1 '^render-topology '
assert_log_count 1 '^describe-topology '
assert_log_count 1 '^validate-compose '
assert_log_count 1 "^fake-submit .* ${upstream_sha}\$"
assert_log_count 7 '^receipt '
stage_records=$(grep -c '^stage=' "$case_receipt" || true)
[ "$stage_records" -eq 7 ] ||
  fail "prepared expected 7 append-only stage records, found $stage_records"
assert_file_contains "$case_receipt" 'stage=resolve-upstream'
assert_file_contains "$case_receipt" 'stage=publish-candidate'
assert_file_contains "$case_receipt" 'stage=prove-revision'
assert_file_contains "$case_receipt" 'stage=render-topology'
assert_file_contains "$case_receipt" 'stage=verify-topology'
assert_file_contains "$case_receipt" 'stage=validate-compose'
assert_file_contains "$case_receipt" 'stage=submit-candidate'
assert_file_contains "$case_stdout" \
  "PREPARED $upstream_sha $candidate_ref fake://$upstream_sha"
pass prepared

run_case prepared test "$fake_transport" DEFAULT
require_success
assert_log_count 1 "^publish-candidate $upstream_sha $image_repository\$"
pass default-image-repository

run_case prepared test
require_success
test_interactions=$(normalized_interaction_log "$case_log" "$case_state")
assert_log_count 1 '^fake-submit '

run_case prepared manual
require_success
assert_complete_receipt manual
manual_interactions=$(normalized_interaction_log "$case_log" "$case_state")

[ "$test_interactions" = "$manual_interactions" ] ||
  fail "mode-parity full interactions differ
test:
$test_interactions
manual:
$manual_interactions"
assert_log_count 1 '^fake-submit '
pass mode-parity

run_rejection wrong-ref resolve-upstream wrong-ref publish-candidate
run_rejection wrong-origin resolve-upstream wrong-origin publish-candidate
run_rejection resolve-failure resolve-upstream observation-command-failed publish-candidate
run_rejection malformed-observation resolve-upstream malformed-sha publish-candidate
run_rejection zero-observation resolve-upstream observation-count-0 publish-candidate
run_rejection ambiguous-observation resolve-upstream observation-count-2 publish-candidate
run_rejection trailing-field-observation resolve-upstream malformed-observation publish-candidate
run_rejection publish-failure publish-candidate publish-failed prove-revision
run_rejection malformed-candidate-form publish-candidate malformed-candidate-form prove-revision
run_rejection repository-whitespace publish-candidate malformed-candidate-form prove-revision
run_rejection tag-sha-mismatch publish-candidate tag-sha-mismatch prove-revision
run_rejection multiline-candidate-form publish-candidate multi-line-candidate prove-revision
run_rejection revision-mismatch prove-revision revision-mismatch render-topology
run_rejection revision-absent prove-revision revision-absent render-topology
run_rejection multiline-revision prove-revision multi-line-revision render-topology
run_rejection unparsable-revision prove-revision unparsable-revision render-topology
run_rejection render-failure render-topology render-failed describe-topology
run_rejection multiline-model-path render-topology multi-line-model-path describe-topology
run_rejection model-outside-state-dir render-topology model-outside-state-dir describe-topology
run_rejection describe-failure verify-topology describe-failed validate-compose
run_rejection stale-topology-override verify-topology stale-topology-override validate-compose
run_rejection missing-node-service verify-topology missing-node-service-relay3 validate-compose
run_rejection zero-topology-census verify-topology zero-topology-census validate-compose
run_rejection trailing-field-topology verify-topology malformed-topology-row validate-compose
run_rejection empty-topology-service verify-topology empty-service validate-compose
run_rejection empty-topology-image verify-topology empty-image validate-compose
run_rejection whitespace-topology-image verify-topology whitespace-image validate-compose
run_rejection duplicate-node-service verify-topology census-count-8 validate-compose
run_rejection rendered-model-candidate-mismatch verify-topology image-mismatch validate-compose
run_rejection compose-failure validate-compose compose-failed
run_rejection submission-failure submit-candidate submission-failed
run_rejection multiline-submission submit-candidate multi-line-submission
run_rejection malformed-submission submit-candidate malformed-submission

model_operations=(describe-topology validate-compose fake-submit)
modeled_operations=$(modeled_rendered_model_operations)
witnessed_operations=$(printf '%s\n' "${model_operations[@]}" | sort)
[ "$modeled_operations" = "$witnessed_operations" ] ||
  fail "rendered-model witness inventory differs from the operation surface
modeled:
$modeled_operations
witnessed:
$witnessed_operations"

for model_operation in "${model_operations[@]}"; do
  witness_dir="$tmp_root/model-witness-$model_operation"
  mkdir -p "$witness_dir/state"
  witness_log="$witness_dir/transport.log"
  : >"$witness_log"
  witness_args=("$witness_dir/not-rendered-model")
  if [ "$model_operation" = fake-submit ]; then
    witness_args+=("$candidate_ref" "$upstream_sha")
  fi
  if env \
    FAKE_SCENARIO=prepared \
    FAKE_LOG="$witness_log" \
    HEAD_CANDIDATE_STATE_DIR="$witness_dir/state" \
    HEAD_CANDIDATE_RECEIPT="$witness_dir/receipt" \
    "$fake_transport" "$model_operation" "${witness_args[@]}" \
    2>"$witness_dir/stderr"; then
    fail "$model_operation accepted a model it could not witness"
  fi
  assert_file_contains "$witness_log" \
    "$model_operation ${witness_args[*]}"
  grep -Fq 'rendered model missing:' "$witness_dir/stderr" ||
    fail "$model_operation did not report the missing rendered model"
done
pass rendered-model-witnesses

run_case unsupported-mode bogus
require_failure
assert_log_count 0 '.'
assert_no_submit
pass unsupported-mode

missing_transport_path="$tmp_root/non-executable-transport"
printf '#!/usr/bin/env bash\necho should-not-run\n' >"$missing_transport_path"
chmod a-x "$missing_transport_path"
run_case missing-transport test "$missing_transport_path"
require_failure
grep -Fq 'transport is not executable' "$case_stderr" ||
  fail "missing-transport stderr lacks preflight rejection token"
assert_no_submit
pass missing-transport

actual_ops=$(transport_operation_surface)
expected_ops=$(modeled_transport_operations)
[ "$actual_ops" = "$expected_ops" ] ||
  fail "transport operation surface mismatch
expected:
$expected_ops
actual:
$actual_ops"
controller_ops=$(grep -Eoh 'transport_call [a-z0-9-]+' "$controller" |
  awk '{print $2}' | sort -u)
while IFS= read -r op; do
  [ -n "$op" ] || continue
  grep -Fqx -- "$op" <<<"$expected_ops" ||
    fail "controller invokes undocumented transport operation: $op"
done <<<"$controller_ops"
run_case prepared
require_success
assert_log_count 1 '^fake-submit '
pass no-real-submission

run_case revision-mismatch
require_failure
assert_honest_failure_receipt prove-revision revision-mismatch
assert_last_receipt_contains "candidate_ref=$candidate_ref"
assert_file_contains "$case_receipt" 'stage=resolve-upstream'
assert_file_contains "$case_receipt" 'outcome=OBSERVED'
assert_file_contains "$case_receipt" 'stage=publish-candidate'
assert_file_contains "$case_receipt" 'outcome=PUBLISHED'
assert_no_submit
pass receipt-honesty
