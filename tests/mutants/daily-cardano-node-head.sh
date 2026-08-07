#!/usr/bin/env bash
# shellcheck disable=SC2016 # Mutation anchors are intentionally literal shell.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
controller_rel=scripts/daily-cardano-node-head.sh
fake_rel=tests/fixtures/daily-cardano-node-head/fake-transport.sh
suite_rel=tests/test-daily-cardano-node-head.sh
harness_rel=tests/mutants/daily-cardano-node-head.sh
contain_rel=tests/contain/run-suite.sh
functions_model_rel=specs/215-immutable-cardano-node-head-candidate/functions-model.md
data_model_rel=specs/215-immutable-cardano-node-head-candidate/data-model.md
owned=("$controller_rel" "$fake_rel" "$suite_rel" "$harness_rel" "$contain_rel")

die() {
  printf 'MUTATION-HARNESS-FAIL: %s\n' "$*" >&2
  exit 1
}

fingerprint_owned() {
  local path
  for path in "${owned[@]}"; do
    sha256sum "$repo_root/$path"
  done
}

scratch_parent=${MUTANT_WORKDIR:-}
if [ -n "$scratch_parent" ]; then
  case "$scratch_parent" in
    /*) ;;
    *) die 'MUTANT_WORKDIR must be absolute' ;;
  esac
  mkdir -p "$scratch_parent"
  scratch_root=$(mktemp -d "$scratch_parent/daily-cardano-node-head.XXXXXX")
else
  scratch_root=$(mktemp -d)
fi
network_listener_pid=''
filesystem_effect=''
cleanup() {
  if [ -n "$network_listener_pid" ]; then
    kill "$network_listener_pid" 2>/dev/null || true
    wait "$network_listener_pid" 2>/dev/null || true
  fi
  [ -z "$filesystem_effect" ] || rm -f -- "$filesystem_effect"
  rm -rf -- "$scratch_root"
}
trap cleanup EXIT

[ -x "$repo_root/$contain_rel" ] ||
  die "missing containment entrypoint: $contain_rel"

source_fingerprint=$(fingerprint_owned)
baseline_log="$scratch_root/baseline.log"
if ! "$repo_root/$suite_rel" >"$baseline_log" 2>&1; then
  tail -n 20 "$baseline_log" >&2
  die 'unmutated suite is not green'
fi

materialize() {
  local mutant=$1
  case_root="$scratch_root/$mutant"
  mkdir -p \
    "$case_root/scripts" \
    "$case_root/tests/fixtures/daily-cardano-node-head" \
    "$case_root/tests/contain" \
    "$case_root/specs/215-immutable-cardano-node-head-candidate"
  cp -p "$repo_root/$controller_rel" "$case_root/$controller_rel"
  cp -p "$repo_root/$fake_rel" "$case_root/$fake_rel"
  cp -p "$repo_root/$suite_rel" "$case_root/$suite_rel"
  cp -p "$repo_root/$contain_rel" "$case_root/$contain_rel"
  cp -p "$repo_root/$functions_model_rel" "$case_root/$functions_model_rel"
  cp -p "$repo_root/$data_model_rel" "$case_root/$data_model_rel"
}

replace_line_once() {
  local file=$1
  local old=$2
  local new=$3
  local before after count tmp
  count=$(grep -Fxc -- "$old" "$file" || true)
  [ "$count" -eq 1 ] ||
    die "mutation anchor count=$count, expected=1: $old"
  before=$(sha256sum "$file")
  tmp="$file.mutating"
  awk -v old="$old" -v new="$new" \
    '$0 == old { print new; next } { print }' "$file" >"$tmp"
  chmod --reference="$file" "$tmp"
  mv "$tmp" "$file"
  count=$(grep -Fxc -- "$new" "$file" || true)
  [ "$count" -eq 1 ] || die "mutated line count=$count, expected=1: $new"
  if [ "$old" != "$new" ]; then
    count=$(grep -Fxc -- "$old" "$file" || true)
    [ "$count" -eq 0 ] || die "old mutation anchor survived: $old"
  fi
  after=$(sha256sum "$file")
  [ "$before" != "$after" ] || die "mutation did not change $file"
}

insert_before_once() {
  local file=$1
  local anchor=$2
  local inserted=$3
  local before after count tmp
  count=$(grep -Fxc -- "$anchor" "$file" || true)
  [ "$count" -eq 1 ] ||
    die "insertion anchor count=$count, expected=1: $anchor"
  count=$(grep -Fxc -- "$inserted" "$file" || true)
  [ "$count" -eq 0 ] || die "inserted mutant already exists: $inserted"
  before=$(sha256sum "$file")
  tmp="$file.mutating"
  awk -v anchor="$anchor" -v inserted="$inserted" \
    '$0 == anchor { print inserted } { print }' "$file" >"$tmp"
  chmod --reference="$file" "$tmp"
  mv "$tmp" "$file"
  count=$(grep -Fxc -- "$inserted" "$file" || true)
  [ "$count" -eq 1 ] ||
    die "inserted mutation count=$count, expected=1: $inserted"
  after=$(sha256sum "$file")
  [ "$before" != "$after" ] || die "insertion did not change $file"
}

start_network_listener() {
  local listener
  listener=$(command -v socat || true)
  [ -n "$listener" ] && [ -x "$listener" ] ||
    die 'network negative control requires socat'
  network_port=$((20000 + $$ % 20000))
  : >"$case_root/network-effect"
  "$listener" -u \
    "TCP4-LISTEN:$network_port,bind=127.0.0.1,reuseaddr,fork" \
    "OPEN:$case_root/network-effect,creat,append" \
    >"$case_root/network-listener.log" 2>&1 &
  network_listener_pid=$!
  sleep 0.2
  kill -0 "$network_listener_pid" 2>/dev/null || {
    cat "$case_root/network-listener.log" >&2
    die 'network negative-control listener did not start'
  }
}

stop_network_listener() {
  if [ -n "$network_listener_pid" ]; then
    kill "$network_listener_pid" 2>/dev/null || true
    wait "$network_listener_pid" 2>/dev/null || true
    network_listener_pid=''
  fi
}

apply_mutant() {
  local mutant=$1
  local controller="$case_root/$controller_rel"
  local fake="$case_root/$fake_rel"
  local functions_model="$case_root/$functions_model_rel"
  local data_model="$case_root/$data_model_rel"
  case "$mutant" in
    I215-01-remove-observation-cardinality)
      replace_line_once "$controller" \
        'if [ "${#observations[@]}" -ne 1 ]; then' \
        'if [ "${#observations[@]}" -lt 1 ]; then'
      ;;
    I215-01-wrong-fixed-origin)
      replace_line_once "$controller" \
        'origin=https://github.com/IntersectMBO/cardano-node.git' \
        'origin=https://example.invalid/cardano-node.git'
      ;;
    I215-02-remove-tag-equality)
      replace_line_once "$controller" \
        '[ "$tag_part" = "$observed_sha" ] ||' \
        '[ "$tag_part" = "$tag_part" ] ||'
      ;;
    I215-03-remove-revision-equality)
      replace_line_once "$controller" \
        '[ "$binary_revision" = "$observed_sha" ] ||' \
        '[ "$binary_revision" = "$binary_revision" ] ||'
      ;;
    I215-04-remove-zero-census-reason)
      replace_line_once "$controller" \
        '  fail_stage verify-topology zero-topology-census' \
        '  true'
      ;;
    I215-04-describe-ignores-rendered-model)
      replace_line_once "$fake" \
        '    candidate_ref=$(read_rendered_candidate "$rendered_model")' \
        '    candidate_ref=$(candidate_ref_for ghcr.io/cardano-foundation/cardano-node "$upstream_sha")'
      ;;
    I215-04-remove-node-image-equality)
      replace_line_once "$controller" \
        '      fail_stage verify-topology image-mismatch' \
        '      true'
      ;;
    I215-05-validate-wrong-model)
      replace_line_once "$controller" \
        'if ! transport_call validate-compose "$rendered_model"; then' \
        'if ! transport_call validate-compose "$state_dir/not-rendered-model"; then'
      ;;
    I215-06-duplicate-submit)
      insert_before_once "$controller" \
        "submit_output=''" \
        'transport_call fake-submit "$rendered_model" "$candidate_ref" "$observed_sha" >/dev/null'
      ;;
    I215-07-wall-network-egress)
      start_network_listener
      insert_before_once "$fake" \
        '    log fake-submit "$rendered_model" "$candidate_ref" "$sha"' \
        "    exec 9<>/dev/tcp/127.0.0.1/$network_port; printf 'REAL-SUBMIT:%s:%s' \"\$candidate_ref\" \"\$sha\" >&9; exec 9>&-"
      ;;
    I215-07-wall-filesystem-egress)
      filesystem_effect="/dev/shm/daily-cardano-node-head-wall.$$.effect"
      : >"$filesystem_effect"
      insert_before_once "$fake" \
        '    log fake-submit "$rendered_model" "$candidate_ref" "$sha"' \
        "    printf 'REAL-SUBMIT:%s:%s' \"\$candidate_ref\" \"\$sha\" >>\"$filesystem_effect\""
      ;;
    I215-08-manual-specific-validation-target)
      insert_before_once "$controller" \
        'if ! transport_call validate-compose "$rendered_model"; then' \
        'if [ "$mode" = manual ]; then rendered_model="$state_dir/manual-only-model"; fi'
      ;;
    I215-09-later-field-on-compose-failure)
      insert_before_once "$controller" \
        '  for pair in "$@"; do' \
        '  [ "$stage" != validate-compose ] || receipt[submission]=fake://premature'
      ;;
    D05-drop-mode-field)
      replace_line_once "$controller" \
        'receipt[mode]=$mode' \
        "unset 'receipt[mode]'"
      ;;
    D05-constant-mode-field)
      replace_line_once "$controller" \
        'receipt[mode]=$mode' \
        'receipt[mode]=manual'
      ;;
    D05-wrong-upstream-origin)
      replace_line_once "$controller" \
        'receipt[upstream_origin]=$origin' \
        'receipt[upstream_origin]=https://example.invalid/wrong.git'
      ;;
    D05-wrong-upstream-ref)
      replace_line_once "$controller" \
        'receipt[upstream_ref]=$ref' \
        'receipt[upstream_ref]=refs/heads/wrong'
      ;;
    D05-wrong-binary-revision)
      replace_line_once "$controller" \
        'receipt[binary_revision]=$binary_revision' \
        'receipt[binary_revision]=0000000000000000000000000000000000000000'
      ;;
    D05-wrong-rendered-model)
      replace_line_once "$controller" \
        'receipt[rendered_model]=$rendered_model' \
        'receipt[rendered_model]=/nowhere/not-the-rendered-model'
      ;;
    D05-wrong-topology-census)
      replace_line_once "$controller" \
        'receipt[topology_services]=7' \
        'receipt[topology_services]=99'
      ;;
    D05-wrong-topology-image)
      replace_line_once "$controller" \
        'receipt[topology_image]=$candidate_ref' \
        'receipt[topology_image]=ghcr.io/example/not-the-candidate'
      ;;
    MODEL-receipt-gains-field)
      insert_before_once "$data_model" \
        '| `submission` | from `submit-candidate` on | must begin with `fake://` |' \
        '| `audit_marker` | always | literal `witness-required` |'
      ;;
    MODEL-transport-gains-operation)
      insert_before_once "$functions_model" \
        '| `validate-compose` | `rendered_model` | nothing; exit status is the whole contract |' \
        '| `audit-probe` | `upstream_sha` | nothing |'
      ;;
    MODEL-describe-wrong-path)
      replace_line_once "$controller" \
        'if ! topology_output=$(transport_call describe-topology "$rendered_model"); then' \
        'if ! topology_output=$(transport_call describe-topology "$state_dir/not-rendered-model"); then'
      ;;
    MODEL-submit-wrong-path)
      replace_line_once "$controller" \
        '  "$rendered_model" "$candidate_ref" "$observed_sha"); then' \
        '  "$state_dir/not-rendered-model" "$candidate_ref" "$observed_sha"); then'
      ;;
    ENTRY-remove-transport-preflight)
      replace_line_once "$controller" \
        '[ -x "$transport" ] || die "transport is not executable: $transport"' \
        ': # mutant removed transport executable preflight'
      ;;
    *) die "unknown mutant: $mutant" ;;
  esac
}

mutants=(
  I215-01-remove-observation-cardinality
  I215-01-wrong-fixed-origin
  I215-02-remove-tag-equality
  I215-03-remove-revision-equality
  I215-04-remove-zero-census-reason
  I215-04-describe-ignores-rendered-model
  I215-04-remove-node-image-equality
  I215-05-validate-wrong-model
  I215-06-duplicate-submit
  I215-07-wall-network-egress
  I215-07-wall-filesystem-egress
  I215-08-manual-specific-validation-target
  I215-09-later-field-on-compose-failure
  D05-drop-mode-field
  D05-constant-mode-field
  D05-wrong-upstream-origin
  D05-wrong-upstream-ref
  D05-wrong-binary-revision
  D05-wrong-rendered-model
  D05-wrong-topology-census
  D05-wrong-topology-image
  MODEL-receipt-gains-field
  MODEL-transport-gains-operation
  MODEL-describe-wrong-path
  MODEL-submit-wrong-path
  ENTRY-remove-transport-preflight
)

run_guard_ablation_sweep() {
  local line_no original before after
  local survived=0
  local guard_count=0
  local controller
  mapfile -t guard_lines < <(
    awk '
      /^(die|fail_stage)\(\) \{/ { in_definition = 1; next }
      in_definition && /^}/ { in_definition = 0; next }
      !in_definition && /fail_stage |die "/ { print NR }
    ' "$repo_root/$controller_rel"
  )
  [ "${#guard_lines[@]}" -gt 0 ] || die 'guard ablation found no guards'

  for line_no in "${guard_lines[@]}"; do
    guard_count=$((guard_count + 1))
    materialize "GUARD-$guard_count"
    controller="$case_root/$controller_rel"
    original=$(awk -v line="$line_no" 'NR == line' "$controller")
    before=$(sha256sum "$controller")
    awk -v line="$line_no" '
      NR == line {
        indent = $0
        sub(/[^ ].*$/, "", indent)
        if ($0 ~ /;;[[:space:]]*$/) {
          label = $0
          sub(/^[[:space:]]*/, "", label)
          sub(/\)[[:space:]].*$/, ")", label)
          print indent label " true ;;"
        } else {
          print indent "true"
        }
        next
      }
      { print }
    ' "$controller" >"$controller.mutating"
    chmod --reference="$controller" "$controller.mutating"
    mv "$controller.mutating" "$controller"
    after=$(sha256sum "$controller")
    [ "$before" != "$after" ] || die "guard ablation did not apply: $original"
    bash -n "$controller" || die "guard ablation produced invalid shell: $original"
    if "$case_root/$suite_rel" >"$case_root/suite.log" 2>&1; then
      survived=$((survived + 1))
      printf 'GUARD-SURVIVED %s\n' "$original" >&2
    fi
  done
  [ "$survived" -eq 0 ] ||
    die "$survived/${#guard_lines[@]} fail-closed guards survived ablation"
  printf 'GUARD-ABLATION %s/%s\n' \
    "${#guard_lines[@]}" "${#guard_lines[@]}" >&2
}

caught=0
for mutant in "${mutants[@]}"; do
  materialize "$mutant"
  apply_mutant "$mutant"
  bash -n \
    "$case_root/$controller_rel" \
    "$case_root/$fake_rel" \
    "$case_root/$suite_rel" || die "$mutant produced invalid shell"
  suite_rc=0
  case "$mutant" in
    I215-07-wall-network-egress | I215-07-wall-filesystem-egress)
      control_rc=0
      "$case_root/$suite_rel" >"$case_root/control.log" 2>&1 || control_rc=$?
      [ "$control_rc" -eq 0 ] ||
        die "$mutant seed failed without containment"
      case "$mutant" in
        I215-07-wall-network-egress) effect_file="$case_root/network-effect" ;;
        *) effect_file="$filesystem_effect" ;;
      esac
      [ -s "$effect_file" ] ||
        die "$mutant did not execute its uncontained negative control"
      : >"$effect_file"
      "$case_root/$contain_rel" >"$case_root/suite.log" 2>&1 || suite_rc=$?
      if [ -s "$effect_file" ]; then
        suite_rc=0
      elif [ "$suite_rc" -ne 0 ]; then
        printf 'WALL-CONTROL %s seed=proved containment=blocked\n' "$mutant"
      fi
      ;;
    *)
      "$case_root/$suite_rel" >"$case_root/suite.log" 2>&1 || suite_rc=$?
      ;;
  esac
  stop_network_listener
  if [ "$suite_rc" -eq 0 ]; then
    printf '%s survived\n' "$mutant"
  else
    caught=$((caught + 1))
    printf '%s caught\n' "$mutant"
  fi
done

run_guard_ablation_sweep
[ "$(fingerprint_owned)" = "$source_fingerprint" ] ||
  die 'source artifacts changed while running mutants'
printf 'MUTANTS %s/%s\n' "$caught" "${#mutants[@]}"
[ "$caught" -eq "${#mutants[@]}" ]
