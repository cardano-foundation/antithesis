#!/usr/bin/env bash
set -euo pipefail

repo_root=${1:?repository root is required}
scenario=${2:-all}
controller="$repo_root/scripts/daily-amaru.sh"
transport=${DAILY_AMARU_BOUNDARY_TRANSPORT:-$repo_root/scripts/daily-amaru-github.sh}
fixture_root="$repo_root/tests/fixtures/daily-amaru"
fake_gh="$fixture_root/boundary-gh.sh"
fake_nix="$fixture_root/boundary-nix.sh"
fake_docker="$fixture_root/boundary-docker.sh"
tmp_root=$(mktemp -d)
trap 'rm -rf "$tmp_root"' EXIT

upstream_sha=1111111111111111111111111111111111111111
old_sha=0000000000000000000000000000000000000000
foreign_sha=2222222222222222222222222222222222222222
day=2026-08-19
branch="daily-amaru/bootstrap-$day-${upstream_sha:0:12}"
workflow_head=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

write_lock() {
  local path=$1 sha=$2
  mkdir -p "$(dirname "$path")"
  printf '%s\n' \
    '{' \
    '  "nodes": {' \
    '    "root": {"inputs": {"amaru": "stock"}},' \
    '    "stock": {' \
    '      "original": {"owner": "pragma-org", "repo": "amaru"},' \
    "      \"locked\": {\"rev\": \"$sha\", \"narHash\": \"sha256-old\", \"lastModified\": 1}" \
    '    }' \
    '  },' \
    '  "root": "root",' \
    '  "version": 7' \
    '}' >"$path"
}

create_remote() {
  local label=$1
  local seed="$tmp_root/$label-seed"
  local remote="$tmp_root/$label.git"
  git init --quiet --initial-branch=main "$seed"
  git -C "$seed" config user.name boundary
  git -C "$seed" config user.email boundary@example.invalid
  write_lock "$seed/flake.lock" "$old_sha"
  printf 'boundary\n' >"$seed/README.md"
  git -C "$seed" add .
  git -C "$seed" commit --quiet -m base
  git clone --quiet --bare "$seed" "$remote"
  printf '%s\n' "$remote"
}

create_consumer_remote() {
  local label=$1
  local seed="$tmp_root/$label-consumer-seed"
  local remote="$tmp_root/$label-consumer.git"
  git init --quiet --initial-branch=main "$seed"
  git -C "$seed" config user.name boundary
  git -C "$seed" config user.email boundary@example.invalid
  mkdir -p "$seed/testnets" "$seed/scripts"
  printf 'services:\n  producer:\n    image: ghcr.io/lambdasistemi/amaru-bootstrap-producer:old@sha256:%064d\n' \
    0 >"$seed/testnets/compose.yaml"
  cp "$repo_root/scripts/check-amaru-producer-image-refs.sh" "$seed/scripts/"
  chmod +x "$seed/scripts/check-amaru-producer-image-refs.sh"
  git -C "$seed" add .
  git -C "$seed" commit --quiet -m base
  git clone --quiet --bare "$seed" "$remote"
  printf '%s\n' "$remote"
}

seed_proposal() {
  local remote=$1 kind=$2
  local work
  work=$(mktemp -d "$tmp_root/seed-$kind.XXXXXX")
  git clone --quiet "file://$remote" "$work"
  git -C "$work" config user.name boundary
  git -C "$work" config user.email boundary@example.invalid
  git -C "$work" checkout --quiet -b "$branch" origin/main
  case "$kind" in
    adopt)
      (cd "$work" && "$fake_nix" flake lock --override-input amaru \
        "github:pragma-org/amaru/$upstream_sha")
      ;;
    foreign)
      (cd "$work" && "$fake_nix" flake lock --override-input amaru \
        "github:pragma-org/amaru/$foreign_sha")
      ;;
    *) fail "unknown seed kind: $kind" ;;
  esac
  git -C "$work" add .
  git -C "$work" commit --quiet -m "$kind proposal"
  git -C "$work" push --quiet origin "HEAD:refs/heads/$branch"
  git --git-dir="$remote" rev-parse "refs/heads/$branch"
}

prepare_case() {
  local label=$1
  case_root=$(mktemp -d "$tmp_root/$label.XXXXXX")
  state="$case_root/state"
  bin="$case_root/bin"
  effects="$case_root/effects"
  comments="$case_root/comments"
  stdout="$case_root/stdout"
  stderr="$case_root/stderr"
  receipt="$case_root/receipt"
  mkdir -p "$state" "$bin"
  : >"$effects"
  : >"$comments"
  ln -s "$fake_gh" "$bin/gh"
  ln -s "$fake_nix" "$bin/nix"
  ln -s "$fake_docker" "$bin/docker"
}

run_transport() {
  local label=$1 remote=$2
  prepare_case "$label"
  transport_rc=0
  env \
    PATH="$bin:$PATH" \
    DAILY_AMARU_DAY="$day" \
    DAILY_AMARU_IDENTITY=boundary-bootstrap-token \
    GH_TOKEN=boundary-repository-token \
    DAILY_AMARU_STATE_DIR="$state" \
    DAILY_AMARU_RECEIPT="$receipt" \
    DAILY_AMARU_BOUNDARY_GH_LOG="$effects" \
    DAILY_AMARU_BOUNDARY_COMMENTS="$comments" \
    DAILY_AMARU_BOUNDARY_BOOTSTRAP_REMOTE="$remote" \
    DAILY_AMARU_BOUNDARY_REPOSITORY_REMOTE="$remote" \
    "$transport" propose-bootstrap "$upstream_sha" \
    >"$stdout" 2>"$stderr" || transport_rc=$?
}

assert_adopt() {
  local remote before after output
  remote=$(create_remote adopt)
  before=$(seed_proposal "$remote" adopt)
  run_transport adopt "$remote"
  output=$(cat "$stdout")
  after=$(git --git-dir="$remote" rev-parse "refs/heads/$branch")
  [ "$transport_rc" -eq 0 ] ||
    fail "PROPOSAL-REATTEMPT reproduced=non-fast-forward: $(tr '\n' ' ' <"$stderr")"
  [ "$output" = "$before" ] || fail "adopt emitted '$output', expected $before"
  [ "$after" = "$before" ] || fail 'adopt changed the remote ref'
  ! grep -Fq 'gh pr create' "$effects" || fail 'adopt attempted to create a PR'
  grep -Fq 'gh pr view' "$effects" || fail 'adopt did not reuse the existing PR lookup'
  ! git -C "$state/bootstrap" show-ref --verify --quiet "refs/heads/$branch" ||
    fail 'adopt created the proposal branch locally before classification'
}

assert_foreign() {
  local remote before after
  remote=$(create_remote foreign)
  before=$(seed_proposal "$remote" foreign)
  run_transport foreign "$remote"
  after=$(git --git-dir="$remote" rev-parse "refs/heads/$branch")
  [ "$transport_rc" -ne 0 ] || fail 'foreign proposal was accepted'
  [ ! -s "$stdout" ] || fail 'foreign proposal emitted a value'
  grep -Fq 'foreign-proposal-branch' "$stderr" || fail 'foreign proposal lacked its named red'
  [ "$after" = "$before" ] || fail 'foreign proposal changed the remote ref'
  ! grep -Eq 'gh pr (create|view)' "$effects" || fail 'foreign proposal reached a PR effect'
  ! git -C "$state/bootstrap" show-ref --verify --quiet "refs/heads/$branch" ||
    fail 'foreign classification ran after local branch creation'
}

assert_fresh() {
  local remote output remote_head changed
  remote=$(create_remote fresh)
  run_transport fresh "$remote"
  output=$(cat "$stdout")
  [ "$transport_rc" -eq 0 ] || fail "fresh proposal failed: $(tr '\n' ' ' <"$stderr")"
  [[ "$output" =~ ^[0-9a-f]{40}$ ]] || fail "fresh proposal emitted malformed head: $output"
  remote_head=$(git --git-dir="$remote" rev-parse "refs/heads/$branch")
  [ "$output" = "$remote_head" ] || fail 'fresh output differs from pushed head'
  changed=$(git --git-dir="$remote" diff --name-only main "$branch")
  [ "$changed" = flake.lock ] || fail "fresh proposal changed: $changed"
  grep -Fq 'gh pr create' "$effects" || fail 'fresh proposal did not create its PR'
}

assert_pollution_closed() {
  local bootstrap_remote upstream_remote final_error candidate
  bootstrap_remote=$(create_remote bootstrap)
  upstream_remote=$(create_remote upstream)
  prepare_case pollution
  controller_rc=0
  env \
    PATH="$bin:$PATH" \
    GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0="url.file://$upstream_remote.insteadOf" \
    GIT_CONFIG_VALUE_0=https://github.com/pragma-org/amaru.git \
    DAILY_AMARU_MODE=production \
    DAILY_AMARU_DAY="$day" \
    DAILY_AMARU_HEAD="$workflow_head" \
    DAILY_AMARU_IDENTITY=boundary-bootstrap-token \
    GH_TOKEN=boundary-repository-token \
    DAILY_AMARU_STATE_DIR="$state" \
    DAILY_AMARU_RECEIPT="$receipt" \
    DAILY_AMARU_BOUNDARY_GH_LOG="$effects" \
    DAILY_AMARU_BOUNDARY_COMMENTS="$comments" \
    DAILY_AMARU_BOUNDARY_BOOTSTRAP_REMOTE="$bootstrap_remote" \
    DAILY_AMARU_BOUNDARY_REPOSITORY_REMOTE="$bootstrap_remote" \
    DAILY_AMARU_TRANSPORT="$transport" \
    "$controller" >"$stdout" 2>"$stderr" || controller_rc=$?
  final_error=$(sed -n 's/^error=//p' "$receipt" | tail -1)
  candidate=$(sed -n 's/^bootstrap_candidate_sha=//p' "$receipt" | tail -1)
  if [ "$final_error" = malformed-candidate-sha ]; then
    grep -Fq 'bootstrap-proposal: malformed-candidate-sha' "$stderr" ||
      fail 'pollution reached the wrong malformed-candidate fingerprint'
    fail 'VALUE-CHANNEL-FIRED reproduced=malformed-candidate-sha real_git=1 real_transport=1'
  fi
  [[ "$candidate" =~ ^[0-9a-f]{40}$ ]] ||
    fail "fixed controller recorded no bootstrap candidate (error=$final_error rc=$controller_rc)"
}

declare -A executed_value_operations=()

execute_value_operation() {
  local operation=$1 expected='' candidate='' rc=0
  local bootstrap_remote consumer_remote origin_sha image_ref
  local -a arguments=()
  bootstrap_remote=$(create_remote "value-$operation-bootstrap")
  consumer_remote=$(create_consumer_remote "value-$operation")
  prepare_case "value-$operation"
  image_ref="ghcr.io/lambdasistemi/amaru-bootstrap-producer:$upstream_sha@sha256:$(printf '%064d' 0)"

  case "$operation" in
    preflight) arguments=(gh git jq); expected='OK: 3 scheduled dependencies present: gh git jq' ;;
    claim-day) arguments=("$day" "$workflow_head"); expected=CLAIMED ;;
    claim-sha-attempt) arguments=("$upstream_sha" "$workflow_head"); expected=CLAIMED ;;
    claim-launch) arguments=("$day" "$workflow_head"); expected=CLAIMED ;;
    resolve-upstream)
      origin_sha=$(git --git-dir="$bootstrap_remote" rev-parse refs/heads/main)
      arguments=("file://$bootstrap_remote" refs/heads/main)
      expected="file://$bootstrap_remote|refs/heads/main|$origin_sha"
      ;;
    last-success-sha)
      printf '<!-- daily-amaru last-success sha=%s -->\n' "$upstream_sha" >"$comments"
      expected=$upstream_sha
      ;;
    propose-bootstrap) arguments=("$upstream_sha") ;;
    require-bootstrap-checks)
      arguments=("$workflow_head")
      expected=$(printf 'Bootstrap CI|%s|%s|success\n' \
        Build "$workflow_head" 'Run unit Tests' "$workflow_head" \
        'Check code quality' "$workflow_head" publish-images "$workflow_head")
      ;;
    resolve-image)
      arguments=("$upstream_sha")
      expected=$image_ref
      ;;
    prepare-consumer-repin) arguments=("$image_ref") ;;
    require-consumer-checks)
      arguments=("$workflow_head")
      expected=$(printf '%s|%s|%s|success\n' \
        'Build and push component images for cardano-node testnet' publish-images "$workflow_head" \
        'Build and push component images for cardano-node testnet' 'Compose smoke test' "$workflow_head" \
        'tracer-sidecar CI' Build "$workflow_head" \
        'tracer-sidecar CI' 'Run unit Tests' "$workflow_head" \
        'tracer-sidecar CI' 'Check code quality' "$workflow_head" \
        'Build documentation' build-docs "$workflow_head" \
        'PR preview' preview "$workflow_head")
      ;;
    run-producer-check)
      git clone --quiet "file://$consumer_remote" "$state/consumer"
      candidate=$(git -C "$state/consumer" rev-parse HEAD)
      arguments=("$candidate")
      expected="OK: 1 producer-image reference(s), all pinned to ghcr.io/lambdasistemi/amaru-bootstrap-producer:old@sha256:$(printf '%064d' 0)"
      ;;
    await-supervised-integration)
      printf 'https://example.invalid/pull/1\n' >"$state/consumer-pr"
      arguments=("$workflow_head")
      expected=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
      ;;
    fake-launch)
      arguments=(cardano-node.yaml cardano_amaru duration=1 no-faults=false "$workflow_head")
      expected="fake://cardano-node.yaml/cardano_amaru/duration=1/no-faults=false/$workflow_head"
      ;;
    real-launch)
      arguments=(cardano-node.yaml cardano_amaru duration=1 no-faults=false bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb)
      expected='https://github.com/cardano-foundation/cardano-node-antithesis/actions/runs/4242'
      ;;
    *) fail "unknown value operation: $operation" ;;
  esac

  env PATH="$bin:$PATH" GIT_TRACE=1 DAILY_AMARU_DAY="$day" \
    DAILY_AMARU_IDENTITY=boundary-bootstrap-token GH_TOKEN=boundary-repository-token \
    DAILY_AMARU_STATE_DIR="$state" DAILY_AMARU_BOUNDARY_GH_LOG="$effects" \
    DAILY_AMARU_BOUNDARY_COMMENTS="$comments" \
    DAILY_AMARU_BOUNDARY_BOOTSTRAP_REMOTE="$bootstrap_remote" \
    DAILY_AMARU_BOUNDARY_REPOSITORY_REMOTE="$consumer_remote" \
    DAILY_AMARU_BOUNDARY_HEAD_SHA="$workflow_head" \
    DAILY_AMARU_BOUNDARY_INTEGRATED_SHA=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
    "$transport" "$operation" "${arguments[@]}" >"$stdout" 2>"$stderr" || rc=$?
  [ "$rc" -eq 0 ] || fail "value operation $operation failed: $(tr '\n' ' ' <"$stderr")"
  case "$operation" in
    propose-bootstrap) expected=$(git --git-dir="$bootstrap_remote" rev-parse "refs/heads/$branch") ;;
    prepare-consumer-repin)
      expected=$(git --git-dir="$consumer_remote" rev-parse "refs/heads/daily-amaru/consumer-$day")
      ;;
  esac
  printf '%s\n' "$expected" >"$case_root/expected"
  cmp -s "$case_root/expected" "$stdout" ||
    fail "value operation $operation emitted non-exact bytes: $(od -An -tx1 "$stdout" | tr -d ' \n')"
  executed_value_operations["$operation"]=1
}

assert_value_census() {
  local operation
  local -a dispatched_operations executed_operations
  for operation in preflight claim-day resolve-upstream last-success-sha \
    claim-sha-attempt claim-launch propose-bootstrap require-bootstrap-checks \
    resolve-image prepare-consumer-repin require-consumer-checks run-producer-check \
    await-supervised-integration fake-launch real-launch; do
    execute_value_operation "$operation"
  done
  mapfile -t dispatched_operations < <(
    grep -E '^  [a-z0-9-]+\)$' "$transport" | sed 's/^  //; s/)$//' |
      grep -vx receipt | sort
  )
  mapfile -t executed_operations < <(printf '%s\n' "${!executed_value_operations[@]}" | sort)
  [ "${dispatched_operations[*]}" = "${executed_operations[*]}" ] ||
    fail "value operation dispatch drift: dispatched=${dispatched_operations[*]} executed=${executed_operations[*]}"
  value_operation_count=${#dispatched_operations[@]}
  value_executed_count=${#executed_operations[@]}

  prepare_case strict-api
  if DAILY_AMARU_BOUNDARY_GH_LOG="$effects" DAILY_AMARU_BOUNDARY_COMMENTS="$comments" \
    "$fake_gh" api repos/example/unsupported >"$stdout" 2>"$stderr"; then
    fail 'boundary-gh accepted an API endpoint outside the real CLI surface'
  fi
}

assert_receipt_schema() {
  local mutant="$tmp_root/receipt-schema-mutant.sh"
  local -a expected actual mutant_actual
  expected=(
    day stage outcome error workflow_head claim_supersedes launch_claim
    dependency_census upstream_origin upstream_ref upstream_sha
    bootstrap_candidate_sha image_ref consumer_candidate_sha check_evidence
    producer_count producer_evidence consumer_integrated_sha launch_workflow
    launch_test launch_duration launch_no_faults launch_request moog_request
    run_outcome
  )
  mapfile -t actual < <(awk '
    /^receipt_keys=\($/ { inside = 1; next }
    inside && /^\)$/ { exit }
    inside { for (i = 1; i <= NF; i++) print $i }
  ' "$controller")
  [ "${actual[*]}" = "${expected[*]}" ] || fail 'receipt_keys changed from the frozen schema'
  sed 's/launch_request moog_request/launch_request_removed moog_request/' \
    "$controller" >"$mutant"
  grep -Fq 'launch_request_removed moog_request' "$mutant" ||
    fail 'receipt schema mutation did not apply'
  mapfile -t mutant_actual < <(awk '
    /^receipt_keys=\($/ { inside = 1; next }
    inside && /^\)$/ { exit }
    inside { for (i = 1; i <= NF; i++) print $i }
  ' "$mutant")
  [ "${mutant_actual[*]}" != "${expected[*]}" ] ||
    fail 'receipt schema oracle accepted a changed key'
  printf 'RECEIPT-SCHEMA keys=%s unchanged=true\n' "${#actual[@]}"
}

assert_value_mutants() {
  local mutant_root="$tmp_root/value-mutants" mutant operation marker
  mkdir -p "$mutant_root"
  value_mutants_rejected=0
  for operation in real-launch prepare-consumer-repin require-consumer-checks resolve-image; do
    mutant="$mutant_root/$operation.sh"
    marker="# value-mutant-$operation"
    awk -v operation="$operation" -v marker="$marker" '
      $0 == "  " operation ")" { inside = 1 }
      inside && operation == "real-launch" && /gh run watch/ {
        sub(/with_identity/, "watch_output=$(with_identity")
        sub(/--exit-status$/, "--exit-status)")
        print
        print "    emit \"$watch_output\" " marker
        next
      }
      { print }
      inside && operation == "prepare-consumer-repin" && /consumer-pr/ && /^    printf/ {
        print "    emit \"$pr_url\" " marker
      }
      inside && operation == "require-consumer-checks" && /^    emit "\$rows"/ {
        print "    emit \"$rows\" " marker
      }
      inside && operation == "resolve-image" && /invalid registry digest/ {
        print "    emit \"$digest\" " marker
      }
      inside && $0 == "    ;;" { inside = 0 }
    ' "$transport" >"$mutant"
    grep -Fq "$marker" "$mutant" || fail "value mutation did not apply: $operation"
    bash -n "$mutant" || fail "value mutation is not valid shell: $operation"
    chmod +x "$mutant"
    reject_scenario_mutant "value-$operation" "$mutant" census \
      "value operation $operation emitted non-exact bytes"
    value_mutants_rejected=$((value_mutants_rejected + 1))
    printf 'VALUE-MUTANT name=%s rejected=true\n' "$operation"
  done
}

reject_scenario_mutant() {
  local label=$1 script=$2 mutant_scenario=$3 fingerprint=$4
  local log="$tmp_root/$label.log"
  if DAILY_AMARU_BOUNDARY_TRANSPORT="$script" "$0" "$repo_root" \
    "$mutant_scenario" >"$log" 2>&1; then
    fail "mutant passed: $label"
  fi
  grep -Fq "$fingerprint" "$log" ||
    fail "mutant $label failed for the wrong reason: $(tr '\n' ' ' <"$log")"
}

assert_mutants() {
  local mutant_root="$tmp_root/mutants"
  local pollution adoption foreign fresh ordering
  mkdir -p "$mutant_root"

  pollution="$mutant_root/pollution.sh"
  sed '/^exec 1>&2$/d' "$transport" >"$pollution"
  ! grep -Fqx 'exec 1>&2' "$pollution" || fail 'pollution mutation did not apply'
  chmod +x "$pollution"
  reject_scenario_mutant pollution "$pollution" pollution \
    'VALUE-CHANNEL-FIRED reproduced=malformed-candidate-sha'

  adoption="$mutant_root/adoption.sh"
  sed "0,/printf 'adoptable\\\\n'/{s//printf 'absent\\\\n'/}" "$transport" >"$adoption"
  grep -Fq "printf 'absent\\n'" "$adoption" || fail 'adoption mutation did not apply'
  chmod +x "$adoption"
  reject_scenario_mutant adoption "$adoption" reattempt \
    'PROPOSAL-REATTEMPT reproduced=non-fast-forward'

  foreign="$mutant_root/foreign.sh"
  sed "s/printf 'foreign\\\\n'/printf 'adoptable\\\\n'/g" "$transport" >"$foreign"
  grep -Fq "printf 'adoptable\\n'" "$foreign" || fail 'foreign mutation did not apply'
  chmod +x "$foreign"
  reject_scenario_mutant foreign "$foreign" foreign 'foreign proposal was accepted'

  fresh="$mutant_root/fresh.sh"
  sed "0,/printf 'absent\\\\n'/{s//printf 'foreign\\\\n'/}" "$transport" >"$fresh"
  grep -Fq "printf 'foreign\\n'" "$fresh" || fail 'fresh mutation did not apply'
  chmod +x "$fresh"
  reject_scenario_mutant fresh "$fresh" fresh 'fresh proposal failed'

  ordering="$mutant_root/ordering.sh"
  awk '
    { print }
    $0 ~ /^  local merge_base/ {
      print "  git -C \"$directory\" checkout -b \"$branch\" origin/main >/dev/null # ordering-mutant"
    }
  ' "$transport" >"$ordering"
  grep -Fq '# ordering-mutant' "$ordering" || fail 'ordering mutation did not apply'
  chmod +x "$ordering"
  reject_scenario_mutant ordering "$ordering" foreign \
    'classification ran after local branch creation'
}

case "$scenario" in
  pollution)
    assert_pollution_closed
    ;;
  reattempt)
    assert_adopt
    ;;
  foreign)
    assert_foreign
    ;;
  fresh)
    assert_fresh
    ;;
  census)
    assert_value_census
    ;;
  all)
    assert_pollution_closed
    assert_adopt
    assert_foreign
    assert_fresh
    assert_value_census
    assert_value_mutants
    assert_receipt_schema
    assert_mutants
    printf 'VALUE-CHANNEL operations=%s executed=%s census=complete mutants_rejected=%s\n' \
      "$value_operation_count" "$value_executed_count" "$value_mutants_rejected"
    printf 'VALUE-CHANNEL-FIRED reproduced=malformed-candidate-sha real_git=1 real_transport=1\n'
    printf 'PROPOSAL-REATTEMPT adopt=1 foreign=1 fresh=1 mutants_rejected=4\n'
    ;;
  *) fail "unknown scenario: $scenario" ;;
esac
