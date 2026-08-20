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

seeded_commands=(
  bash cat date dirname find git grep head jq mkdir mv sed seq sleep sort tail tr awk
)
standin_commands=(gh nix docker rg)
scheduled_command_census=()

declare -A boundary_seed_sources=()
declare -A boundary_standin_sources=()
boundary_sources_bound=0
boundary_seeded_count=0
boundary_standins_verified=0
boundary_census_ablated=0
boundary_path_mutants_rejected=0

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

write_rg_standin() {
  local path=$1
  cat >"$path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ "$#" -eq 7 ] && [ "$1" = -l ] && [ "$4" = -g ] &&
  [ "$5" = '*.yaml' ] && [ "$6" = -g ] && [ "$7" = '*.yml' ] || exit 64
pattern=$2
root=$3
for file in "$root"/*.yaml "$root"/*.yml; do
  [ -f "$file" ] || continue
  grep -Eq "$pattern" "$file" && printf '%s\n' "$file"
done
EOF
  chmod +x "$path"
}

bind_boundary_sources() {
  local command source_dir target
  [ "$boundary_sources_bound" -eq 0 ] || return 0

  mapfile -t scheduled_command_census < <(awk '
    /^scheduled_command_census=\($/ { inside = 1; next }
    inside && /^\)$/ { exit }
    inside { for (i = 1; i <= NF; i++) print $i }
  ' "$transport")
  [ "${#scheduled_command_census[@]}" -gt 0 ] ||
    fail 'transport scheduled command census is empty'

  for command in "${seeded_commands[@]}"; do
    target=$(command -v "$command" 2>/dev/null || true)
    [ "${target:0:1}" = / ] && [ -x "$target" ] ||
      fail "cannot bind seeded command $command: ${target:-unresolved}"
    boundary_seed_sources["$command"]=$target
  done

  source_dir="$tmp_root/boundary-standins"
  mkdir -p "$source_dir"
  ln -sf "$fake_gh" "$source_dir/gh"
  ln -sf "$fake_nix" "$source_dir/nix"
  ln -sf "$fake_docker" "$source_dir/docker"
  write_rg_standin "$source_dir/rg"
  for command in "${standin_commands[@]}"; do
    target="$source_dir/$command"
    [ "${target:0:1}" = / ] && [ -x "$target" ] ||
      fail "cannot bind stand-in $command: $target"
    boundary_standin_sources["$command"]=$target
  done
  boundary_sources_bound=1
}

seed_boundary_path() {
  local bin_dir=$1 command target
  bind_boundary_sources
  for command in "${seeded_commands[@]}"; do
    target=${boundary_seed_sources[$command]:-}
    [ "${target:0:1}" = / ] && [ -x "$target" ] ||
      fail "cannot bind seeded command $command: ${target:-unresolved}"
    ln -sf "$target" "$bin_dir/$command"
    boundary_seeded_count=$((boundary_seeded_count + 1))
  done
  for command in "${standin_commands[@]}"; do
    target=${boundary_standin_sources[$command]:-}
    [ "${target:0:1}" = / ] && [ -x "$target" ] ||
      fail "cannot bind stand-in $command: ${target:-unresolved}"
    ln -sf "$target" "$bin_dir/$command"
    boundary_seeded_count=$((boundary_seeded_count + 1))
  done
}

assert_boundary_path() {
  local expected_bin=$1 command expected resolved target
  [ "${expected_bin:0:1}" = / ] ||
    fail "boundary bin root is not absolute: $expected_bin"
  [ "$PATH" = "$expected_bin" ] ||
    fail "boundary PATH inherited host entries: $PATH"
  for command in "${seeded_commands[@]}"; do
    expected="$expected_bin/$command"
    resolved=$(command -v "$command" 2>/dev/null || true)
    target=${boundary_seed_sources[$command]:-}
    [ "$resolved" = "$expected" ] && [ -x "$resolved" ] &&
      [ -n "$target" ] && [ "$resolved" -ef "$target" ] ||
      fail "seeded command $command is not bound to its proved source: ${resolved:-unresolved}"
  done
  for command in "${standin_commands[@]}"; do
    expected="$expected_bin/$command"
    resolved=$(command -v "$command" 2>/dev/null || true)
    target=${boundary_standin_sources[$command]:-}
    [ "$resolved" = "$expected" ] && [ -x "$resolved" ] &&
      [ -n "$target" ] && [ "$resolved" -ef "$target" ] ||
      fail "stand-in $command is not bound to its fixture binary: ${resolved:-unresolved}"
    boundary_standins_verified=$((boundary_standins_verified + 1))
  done
}

run_boundary_command() {
  local expected_bin=$1
  shift
  local PATH=$expected_bin
  export PATH
  hash -r
  assert_boundary_path "$expected_bin"
  "$@"
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
  seed_boundary_path "$bin"
}

run_transport() {
  local label=$1 remote=$2
  prepare_case "$label"
  transport_rc=0
  DAILY_AMARU_DAY="$day" \
    DAILY_AMARU_IDENTITY=boundary-bootstrap-token \
    GH_TOKEN=boundary-repository-token \
    GIT_CONFIG_NOSYSTEM=1 \
    GIT_CONFIG_GLOBAL=/dev/null \
    DAILY_AMARU_STATE_DIR="$state" \
    DAILY_AMARU_RECEIPT="$receipt" \
    DAILY_AMARU_BOUNDARY_GH_LOG="$effects" \
    DAILY_AMARU_BOUNDARY_COMMENTS="$comments" \
    DAILY_AMARU_BOUNDARY_BOOTSTRAP_REMOTE="$remote" \
    DAILY_AMARU_BOUNDARY_REPOSITORY_REMOTE="$remote" \
    run_boundary_command "$bin" "$transport" propose-bootstrap "$upstream_sha" \
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

assert_pollution_with_remotes() {
  local label=$1 bootstrap_remote=$2 upstream_remote=$3
  local record_census_ablation=${4:-false}
  local final_error='' candidate='' key value
  prepare_case "$label"
  controller_rc=0
  GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0="url.file://$upstream_remote.insteadOf" \
    GIT_CONFIG_VALUE_0=https://github.com/pragma-org/amaru.git \
    GIT_CONFIG_NOSYSTEM=1 \
    GIT_CONFIG_GLOBAL=/dev/null \
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
    run_boundary_command "$bin" "$controller" >"$stdout" 2>"$stderr" || controller_rc=$?
  [ -f "$receipt" ] ||
    fail "fixed controller wrote no receipt: $(tr '\n' ' ' <"$stderr")"
  while IFS='=' read -r key value; do
    case "$key" in
      error) final_error=$value ;;
      bootstrap_candidate_sha) candidate=$value ;;
    esac
  done <"$receipt"
  if [ "$final_error" = malformed-candidate-sha ]; then
    grep -Fq 'bootstrap-proposal: malformed-candidate-sha' "$stderr" ||
      fail 'pollution reached the wrong malformed-candidate fingerprint'
    fail 'VALUE-CHANNEL-FIRED reproduced=malformed-candidate-sha real_git=1 real_transport=1'
  fi
  [[ "$candidate" =~ ^[0-9a-f]{40}$ ]] ||
    fail "fixed controller recorded no bootstrap candidate (error=$final_error rc=$controller_rc)"
  boundary_pollution_verdict="$final_error|valid-candidate"
  if [ "$record_census_ablation" = true ]; then
    boundary_census_ablated=$((boundary_census_ablated + 1))
  fi
}

assert_pollution_closed() {
  local label=${1:-pollution} bootstrap_remote upstream_remote
  bootstrap_remote=$(create_remote "$label-bootstrap")
  upstream_remote=$(create_remote "$label-upstream")
  assert_pollution_with_remotes "$label" "$bootstrap_remote" "$upstream_remote"
}

assert_boundary_census_ablation() {
  local control=$boundary_pollution_verdict omit label host_bin command target
  local bootstrap_remote upstream_remote
  local -a support_commands=(bash ln mkdir mktemp)

  for omit in "${scheduled_command_census[@]}"; do
    label="boundary-ablate-$omit"
    bootstrap_remote=$(create_remote "$label-bootstrap")
    upstream_remote=$(create_remote "$label-upstream")
    host_bin="$tmp_root/$label-host-bin"
    mkdir -p "$host_bin"
    for command in "${support_commands[@]}" "${scheduled_command_census[@]}"; do
      [ "$command" = "$omit" ] && continue
      target=${boundary_seed_sources[$command]:-${boundary_standin_sources[$command]:-}}
      [ -n "$target" ] || target=$(command -v "$command" 2>/dev/null || true)
      [ -n "$target" ] && [ -x "$target" ] || continue
      ln -sf "$target" "$host_bin/$command"
    done
    if PATH="$host_bin" command -v "$omit" >/dev/null 2>&1; then
      fail "boundary census ablation still resolves omitted command: $omit"
    fi
    PATH="$host_bin" command -v bash >/dev/null 2>&1 ||
      fail "boundary census ablation host PATH cannot resolve its positive control: bash"
    PATH="$host_bin" assert_pollution_with_remotes \
      "$label" "$bootstrap_remote" "$upstream_remote" true
    [ "$boundary_pollution_verdict" = "$control" ] ||
      fail "boundary proof verdict changed without host command $omit: $boundary_pollution_verdict"
  done
}

assert_boundary_census_complete() {
  [ "$boundary_census_ablated" -eq "${#scheduled_command_census[@]}" ] ||
    fail "boundary census ablation completed $boundary_census_ablated re-runs, expected ${#scheduled_command_census[@]}"
}

assert_boundary_census_derivation() {
  local mutant="$tmp_root/boundary-census-ablation-removed.sh"
  local log="$tmp_root/boundary-census-ablation-removed.log" before after
  local ablation_call line_continuation="\\"
  printf -v ablation_call '    PATH="$%s" assert_pollution_with_remotes %s' \
    host_bin "$line_continuation"
  before=$(grep -Fxc "$ablation_call" "$0")
  [ "$before" -eq 1 ] ||
    fail "census-ablation-removal mutant expected one re-run call, found $before"
  awk -v needle="$ablation_call" '
    $0 == needle {
      print "    : # MUTANT: census ablation re-run removed"
      getline
      next
    }
    { print }
  ' "$0" >"$mutant"
  chmod +x "$mutant"
  after=$(grep -c '^    : # MUTANT: census ablation re-run removed$' "$mutant")
  [ "$after" -eq 1 ] &&
    [ "$(grep -Fxc "$ablation_call" "$mutant" || true)" -eq 0 ] ||
    fail 'census-ablation-removal mutation did not apply'
  if "$mutant" "$repo_root" ablation >"$log" 2>&1; then
    fail 'census-ablation-removal mutant passed'
  fi
  grep -Fq 'boundary census ablation completed 0 re-runs' "$log" ||
    fail "census-ablation-removal mutant failed for the wrong reason: $(tr '\n' ' ' <"$log")"
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

  GIT_TRACE=1 DAILY_AMARU_DAY="$day" GIT_CONFIG_NOSYSTEM=1 \
    GIT_CONFIG_GLOBAL=/dev/null \
    DAILY_AMARU_IDENTITY=boundary-bootstrap-token GH_TOKEN=boundary-repository-token \
    DAILY_AMARU_STATE_DIR="$state" DAILY_AMARU_BOUNDARY_GH_LOG="$effects" \
    DAILY_AMARU_BOUNDARY_COMMENTS="$comments" \
    DAILY_AMARU_BOUNDARY_BOOTSTRAP_REMOTE="$bootstrap_remote" \
    DAILY_AMARU_BOUNDARY_REPOSITORY_REMOTE="$consumer_remote" \
    DAILY_AMARU_BOUNDARY_HEAD_SHA="$workflow_head" \
    DAILY_AMARU_BOUNDARY_INTEGRATED_SHA=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
    run_boundary_command "$bin" "$transport" "$operation" "${arguments[@]}" \
    >"$stdout" 2>"$stderr" || rc=$?
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

assert_boundary_path_mutants() {
  local original_path=$PATH log
  boundary_path_mutants_rejected=0
  prepare_case boundary-path-mutants

  log="$case_root/host-inheritance.log"
  if (PATH="$bin:$original_path" assert_boundary_path "$bin") >"$log" 2>&1; then
    fail 'host-inheritance mutant passed'
  fi
  grep -Fq 'boundary PATH inherited host entries' "$log" ||
    fail "host-inheritance mutant failed for the wrong reason: $(tr '\n' ' ' <"$log")"
  boundary_path_mutants_rejected=$((boundary_path_mutants_rejected + 1))

  rm -f "$bin/gh"
  ln -s "$case_root/missing-gh" "$bin/gh"
  [ -L "$bin/gh" ] && [ ! -e "$bin/gh" ] ||
    fail 'dangling stand-in mutation did not apply'
  log="$case_root/standin-resolution.log"
  if (PATH="$bin" assert_boundary_path "$bin") >"$log" 2>&1; then
    fail 'stand-in-resolution mutant passed'
  fi
  grep -Fq 'stand-in gh is not bound to its fixture binary' "$log" ||
    fail "stand-in-resolution mutant failed for the wrong reason: $(tr '\n' ' ' <"$log")"
  boundary_path_mutants_rejected=$((boundary_path_mutants_rejected + 1))

  ln -sf "${boundary_standin_sources[gh]}" "$bin/gh"
  rm -f "$bin/jq"
  printf '#!/bin/sh\nexit 0\n' >"$bin/jq"
  chmod +x "$bin/jq"
  grep -Fqx 'exit 0' "$bin/jq" || fail 'fabricated seed mutation did not apply'
  log="$case_root/fabricated-seed.log"
  if (PATH="$bin" assert_boundary_path "$bin") >"$log" 2>&1; then
    fail 'fabricated-seed mutant passed'
  fi
  grep -Fq 'seeded command jq is not bound to its proved source' "$log" ||
    fail "fabricated-seed mutant failed for the wrong reason: $(tr '\n' ' ' <"$log")"
  boundary_path_mutants_rejected=$((boundary_path_mutants_rejected + 1))

  ln -sf "${boundary_seed_sources[jq]}" "$bin/jq"
  mkdir -p "$case_root/missing-source-bin"
  log="$case_root/missing-seed-source.log"
  if (
    boundary_seed_sources[jq]="$case_root/missing-jq"
    seed_boundary_path "$case_root/missing-source-bin"
  ) >"$log" 2>&1; then
    fail 'missing-seed-source mutant passed'
  fi
  grep -Fq 'cannot bind seeded command jq:' "$log" ||
    fail "missing-seed-source mutant failed for the wrong reason: $(tr '\n' ' ' <"$log")"
  boundary_path_mutants_rejected=$((boundary_path_mutants_rejected + 1))

  log="$case_root/relative-root.log"
  if (cd "$case_root" && PATH=bin assert_boundary_path bin) >"$log" 2>&1; then
    fail 'relative-bin-root mutant passed'
  fi
  grep -Fq 'boundary bin root is not absolute: bin' "$log" ||
    fail "relative-bin-root mutant failed for the wrong reason: $(tr '\n' ' ' <"$log")"
  boundary_path_mutants_rejected=$((boundary_path_mutants_rejected + 1))
}

print_boundary_path_marker() {
  [ "$boundary_seeded_count" -gt 0 ] ||
    fail 'boundary path seeded no proved commands'
  [ "$boundary_standins_verified" -gt 0 ] ||
    fail 'boundary operation path verified no stand-ins'
  printf 'BOUNDARY-PATH hermetic=1 seeded=%s host_inherited=0 standins_verified=%s census_ablated=%s mutants_rejected=%s\n' \
    "$boundary_seeded_count" "$boundary_standins_verified" \
    "$boundary_census_ablated" "$boundary_path_mutants_rejected"
}

assert_boundary_marker_derivation() {
  local mutant="$tmp_root/boundary-verification-removed.sh"
  local log="$tmp_root/boundary-verification-removed.log" before after
  local assertion_line
  printf -v assertion_line '  assert_boundary_path "$%s"' expected_bin
  before=$(grep -Fxc "$assertion_line" "$0")
  [ "$before" -eq 1 ] ||
    fail "verification-removal mutant expected one operation-path assertion, found $before"
  awk -v needle="$assertion_line" '
    $0 == needle { print "  : # MUTANT: operation-path verification removed"; next }
    { print }
  ' "$0" >"$mutant"
  chmod +x "$mutant"
  after=$(grep -c '^  : # MUTANT: operation-path verification removed$' "$mutant")
  [ "$after" -eq 1 ] &&
    [ "$(grep -Fxc "$assertion_line" "$mutant" || true)" -eq 0 ] ||
    fail 'verification-removal mutation did not apply'
  if "$mutant" "$repo_root" marker >"$log" 2>&1; then
    fail 'verification-removal mutant passed'
  fi
  grep -Fq 'boundary operation path verified no stand-ins' "$log" ||
    fail "verification-removal mutant failed for the wrong reason: $(tr '\n' ' ' <"$log")"
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
    assert_boundary_census_ablation
    assert_boundary_census_complete
    assert_boundary_path_mutants
    assert_boundary_marker_derivation
    assert_boundary_census_derivation
    printf 'VALUE-CHANNEL operations=%s executed=%s census=complete mutants_rejected=%s\n' \
      "$value_operation_count" "$value_executed_count" "$value_mutants_rejected"
    printf 'VALUE-CHANNEL-FIRED reproduced=malformed-candidate-sha real_git=1 real_transport=1\n'
    printf 'PROPOSAL-REATTEMPT adopt=1 foreign=1 fresh=1 mutants_rejected=4\n'
    print_boundary_path_marker
    printf 'BOUNDARY-PATH-DERIVED verification_removed=rejected seed_fabricated=rejected relative_root=rejected census_ablation_removed=rejected\n'
    ;;
  ablation)
    assert_pollution_closed ablation-control
    assert_boundary_census_ablation
    assert_boundary_census_complete
    ;;
  marker)
    prepare_case marker
    run_boundary_command "$bin" "$bin/bash" -c :
    print_boundary_path_marker
    ;;
  *) fail "unknown scenario: $scenario" ;;
esac
