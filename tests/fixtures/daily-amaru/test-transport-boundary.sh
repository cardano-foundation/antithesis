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
guard_forced_failures=0
guard_named_failures=0
guard_mutants_rejected=0
guard_sites=0

upstream_sha=1111111111111111111111111111111111111111
old_sha=0000000000000000000000000000000000000000
foreign_sha=2222222222222222222222222222222222222222
old_configs_sha=3333333333333333333333333333333333333333
selected_configs_sha=4444444444444444444444444444444444444444
foreign_configs_sha=5555555555555555555555555555555555555555
day=2026-08-19
branch="daily-amaru/bootstrap-$day-${upstream_sha:0:12}"
workflow_head=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
atomic_paths=$'flake.lock\nnix/peer-snapshots/resolution.json'
resolver_invocations=0
amaru_overrides=0
configs_overrides=0
changed_paths=0
proposal_commits=0
lock_only_mutants=0
resolver_failures=0
named_receipts=0
pushes_after_failure=0
prs_after_failure=0
launches=0

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
  local configs_sha=${3:-$old_configs_sha}
  mkdir -p "$(dirname "$path")"
  printf '%s\n' \
    '{' \
    '  "nodes": {' \
    '    "root": {"inputs": {"amaru": "amaru", "cardano-configurations": "cardano-configurations"}},' \
    '    "amaru": {' \
    '      "original": {"owner": "pragma-org", "repo": "amaru"},' \
    "      \"locked\": {\"rev\": \"$sha\", \"narHash\": \"sha256-old\", \"lastModified\": 1}" \
    '    },' \
    '    "cardano-configurations": {' \
    '      "original": {"owner": "cardano-foundation", "repo": "cardano-configurations"},' \
    "      \"locked\": {\"rev\": \"$configs_sha\", \"narHash\": \"sha256-old-configs\", \"lastModified\": 1}" \
    '    }' \
    '  },' \
    '  "root": "root",' \
    '  "version": 7' \
    '}' >"$path"
}

write_resolution() {
  local path=$1 amaru_rev=$2 configs_rev=$3
  mkdir -p "$(dirname "$path")"
  jq -n --arg amaru_rev "$amaru_rev" --arg configs_rev "$configs_rev" '{
    amaru_rev: $amaru_rev,
    amaru_committer_date_utc: "2026-01-01T00:00:00Z",
    configs_rev: $configs_rev,
    resolved_at_utc: "2026-01-01T00:00:00Z",
    query_url: "https://example.invalid/commits",
    snapshots: {
      mainnet: {sha256: "aa"},
      preprod: {sha256: "bb"},
      preview: {sha256: "cc"}
    }
  }' >"$path"
}

create_remote() {
  local label=$1
  local seed="$tmp_root/$label-seed"
  local remote="$tmp_root/$label.git"
  git init --quiet --initial-branch=main "$seed"
  git -C "$seed" config user.name boundary
  git -C "$seed" config user.email boundary@example.invalid
  write_lock "$seed/flake.lock" "$old_sha" "$old_configs_sha"
  write_resolution "$seed/nix/peer-snapshots/resolution.json" \
    "$old_sha" "$old_configs_sha"
  mkdir -p "$seed/scripts"
  cp "$fixture_root/boundary-resolver.sh" "$seed/scripts/resolve-peer-snapshots"
  chmod +x "$seed/scripts/resolve-peer-snapshots"
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
    adopt | lock-only)
      (cd "$work" && "$fake_nix" flake lock --override-input amaru \
        "github:pragma-org/amaru/$upstream_sha")
      ;;
    foreign)
      (cd "$work" && "$fake_nix" flake lock --override-input amaru \
        "github:pragma-org/amaru/$foreign_sha")
      ;;
    atomic)
      (cd "$work" && "$fake_nix" flake lock --override-input amaru \
        "github:pragma-org/amaru/$upstream_sha")
      (cd "$work" && "$fake_nix" flake lock --override-input \
        cardano-configurations \
        "github:cardano-foundation/cardano-configurations/$selected_configs_sha")
      write_resolution "$work/nix/peer-snapshots/resolution.json" \
        "$upstream_sha" "$selected_configs_sha"
      ;;
    record-only)
      write_resolution "$work/nix/peer-snapshots/resolution.json" \
        "$upstream_sha" "$selected_configs_sha"
      ;;
    extra-path)
      (cd "$work" && "$fake_nix" flake lock --override-input amaru \
        "github:pragma-org/amaru/$upstream_sha")
      (cd "$work" && "$fake_nix" flake lock --override-input \
        cardano-configurations \
        "github:cardano-foundation/cardano-configurations/$selected_configs_sha")
      write_resolution "$work/nix/peer-snapshots/resolution.json" \
        "$upstream_sha" "$selected_configs_sha"
      printf 'extra\n' >>"$work/README.md"
      ;;
    split)
      (cd "$work" && "$fake_nix" flake lock --override-input amaru \
        "github:pragma-org/amaru/$upstream_sha")
      git -C "$work" add flake.lock
      git -C "$work" commit --quiet -m 'split lock'
      (cd "$work" && "$fake_nix" flake lock --override-input \
        cardano-configurations \
        "github:cardano-foundation/cardano-configurations/$selected_configs_sha")
      write_resolution "$work/nix/peer-snapshots/resolution.json" \
        "$upstream_sha" "$selected_configs_sha"
      ;;
    *) fail "unknown seed kind: $kind" ;;
  esac
  git -C "$work" add .
  git -C "$work" commit --quiet -m "$kind proposal"
  git -C "$work" push --quiet origin "HEAD:refs/heads/$branch"
  git --git-dir="$remote" rev-parse "refs/heads/$branch"
}

seed_inconsistent_atomic() {
  local remote=$1 field=$2
  local work
  seed_proposal "$remote" atomic >/dev/null
  work=$(mktemp -d "$tmp_root/inconsistent-$field.XXXXXX")
  git clone --quiet "file://$remote" "$work"
  git -C "$work" config user.name boundary
  git -C "$work" config user.email boundary@example.invalid
  git -C "$work" checkout --quiet "$branch"
  case "$field" in
    lock-amaru)
      jq --arg sha "$foreign_sha" \
        '.nodes.amaru.locked.rev = $sha' "$work/flake.lock" >"$work/flake.lock.new"
      mv "$work/flake.lock.new" "$work/flake.lock"
      ;;
    lock-configs)
      jq --arg sha "$foreign_configs_sha" \
        '.nodes["cardano-configurations"].locked.rev = $sha' \
        "$work/flake.lock" >"$work/flake.lock.new"
      mv "$work/flake.lock.new" "$work/flake.lock"
      ;;
    record-amaru)
      jq --arg sha "$foreign_sha" '.amaru_rev = $sha' \
        "$work/nix/peer-snapshots/resolution.json" >"$work/resolution.new"
      mv "$work/resolution.new" "$work/nix/peer-snapshots/resolution.json"
      ;;
    record-configs)
      jq --arg sha "$foreign_configs_sha" '.configs_rev = $sha' \
        "$work/nix/peer-snapshots/resolution.json" >"$work/resolution.new"
      mv "$work/resolution.new" "$work/nix/peer-snapshots/resolution.json"
      ;;
    *) fail "unknown inconsistent field: $field" ;;
  esac
  git -C "$work" add -- flake.lock nix/peer-snapshots/resolution.json
  git -C "$work" commit --quiet --amend --no-edit
  git -C "$work" push --quiet --force origin "HEAD:refs/heads/$branch"
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
  resolver_log="$case_root/resolver.log"
  nix_log="$case_root/nix.log"
  mkdir -p "$state" "$bin"
  : >"$effects"
  : >"$comments"
  : >"$resolver_log"
  : >"$nix_log"
  unset DAILY_AMARU_BOUNDARY_RESOLVER_FAIL
  seed_boundary_path "$bin"
}

run_transport() {
  local label=$1 remote=$2
  local fail_mode=${3:-}
  prepare_case "$label"
  if [ -n "$fail_mode" ]; then
    export DAILY_AMARU_BOUNDARY_RESOLVER_FAIL=$fail_mode
  fi
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
    DAILY_AMARU_BOUNDARY_RESOLVER_LOG="$resolver_log" \
    DAILY_AMARU_BOUNDARY_NIX_LOG="$nix_log" \
    DAILY_AMARU_BOUNDARY_SELECTED_CONFIGS_REV="$selected_configs_sha" \
    run_boundary_command "$bin" "$transport" propose-bootstrap "$upstream_sha" \
    >"$stdout" 2>"$stderr" || transport_rc=$?
  unset DAILY_AMARU_BOUNDARY_RESOLVER_FAIL
}

assert_adopt() {
  local remote before after output
  remote=$(create_remote adopt)
  before=$(seed_proposal "$remote" atomic)
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
  changed=$(git --git-dir="$remote" diff --name-only main "$branch" | sort)
  [ "$changed" = "$atomic_paths" ] || fail "fresh proposal changed: $changed"
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
    DAILY_AMARU_BOUNDARY_RESOLVER_LOG="$resolver_log" \
    DAILY_AMARU_BOUNDARY_NIX_LOG="$nix_log" \
    DAILY_AMARU_BOUNDARY_SELECTED_CONFIGS_REV="$selected_configs_sha" \
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
  before=$(grep -Fxc "$ablation_call" "$0" || true)
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
  after=$(grep -c '^    : # MUTANT: census ablation re-run removed$' "$mutant" || true)
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
      expected=$(printf 'CI|%s|%s|success\n' \
        'Build Gate' "$workflow_head" \
        'Live Bootstrap Producer' "$workflow_head")
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
    DAILY_AMARU_BOUNDARY_RESOLVER_LOG="$resolver_log" \
    DAILY_AMARU_BOUNDARY_NIX_LOG="$nix_log" \
    DAILY_AMARU_BOUNDARY_SELECTED_CONFIGS_REV="$selected_configs_sha" \
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
  before=$(grep -Fxc "$assertion_line" "$0" || true)
  [ "$before" -eq 1 ] ||
    fail "verification-removal mutant expected one operation-path assertion, found $before"
  awk -v needle="$assertion_line" '
    $0 == needle { print "  : # MUTANT: operation-path verification removed"; next }
    { print }
  ' "$0" >"$mutant"
  chmod +x "$mutant"
  after=$(grep -c '^  : # MUTANT: operation-path verification removed$' "$mutant" || true)
  [ "$after" -eq 1 ] &&
    [ "$(grep -Fxc "$assertion_line" "$mutant" || true)" -eq 0 ] ||
    fail 'verification-removal mutation did not apply'
  if "$mutant" "$repo_root" marker >"$log" 2>&1; then
    fail 'verification-removal mutant passed'
  fi
  grep -Fq 'boundary operation path verified no stand-ins' "$log" ||
    fail "verification-removal mutant failed for the wrong reason: $(tr '\n' ' ' <"$log")"
}

assert_named_guard_failure() {
  local label=$1 mutant=$2 mutant_scenario=$3 fingerprint=$4
  local log="$tmp_root/guard-$label.log"
  chmod +x "$mutant"
  if "$mutant" "$repo_root" "$mutant_scenario" >"$log" 2>&1; then
    fail "guarded failure passed: $label"
  fi
  guard_forced_failures=$((guard_forced_failures + 1))
  if grep -Fq "FAIL: $fingerprint" "$log"; then
    guard_named_failures=$((guard_named_failures + 1))
  else
    fail "guarded failure died without its named diagnostic: $label: $(tr '\n' ' ' <"$log")"
  fi
}

guard_site_census() {
  awk '
    /^assert_boundary_(census|marker)_derivation\(\) \{$/ { inside = 1; next }
    inside && /^}$/ { inside = 0; next }
    inside && /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=\$\(grep -[^ ]*c[[:space:]]/ {
      sites++
    }
    END { print sites + 0 }
  ' "$1"
}

assert_guard_diagnostics() {
  local root="$tmp_root/guard-diagnostics" mutant log
  local census_call marker_call census_after census_missing marker_after marker_missing
  mkdir -p "$root"
  guard_sites=$(guard_site_census "$0")
  [ "$guard_sites" -gt 0 ] || fail 'guard-site census found no derivation guards'
  printf -v census_call '    PATH="$%s" assert_pollution_with_remotes %s' \
    host_bin "\\"
  printf -v marker_call '  assert_boundary_path "$%s"' expected_bin
  census_after="  after=\$(grep -c '^    : # MUTANT: census ablation re-run removed$' \"\$mutant\" || true)"
  census_missing="  after=\$(grep -c '^    : # MUTANT: missing census marker$' \"\$mutant\" || true)"
  marker_after="  after=\$(grep -c '^  : # MUTANT: operation-path verification removed$' \"\$mutant\" || true)"
  marker_missing="  after=\$(grep -c '^  : # MUTANT: missing verification marker$' \"\$mutant\" || true)"

  "$0" "$repo_root" guard-census-derivation >"$root/census-positive.log" 2>&1 ||
    fail 'census guard positive control failed'
  "$0" "$repo_root" guard-marker-derivation >"$root/marker-positive.log" 2>&1 ||
    fail 'marker guard positive control failed'

  mutant="$root/census-before-zero.sh"
  awk -v needle="$census_call" '$0 != needle { print }' "$0" >"$mutant"
  ! grep -Fqx "$census_call" "$mutant" || fail 'census-before-zero mutation did not apply'
  assert_named_guard_failure census-before "$mutant" guard-census-derivation \
    'census-ablation-removal mutant expected one re-run call, found 0'

  mutant="$root/census-after-zero.sh"
  awk -v needle="$census_after" -v replacement="$census_missing" '
    $0 == needle { print replacement; changed++; next }
    { print }
    END { if (changed != 1) exit 42 }
  ' "$0" >"$mutant"
  grep -Fqx "$census_missing" "$mutant" || fail 'census-after-zero mutation did not apply'
  assert_named_guard_failure census-after "$mutant" guard-census-derivation \
    'census-ablation-removal mutation did not apply'

  mutant="$root/marker-before-zero.sh"
  awk -v needle="$marker_call" '$0 != needle { print }' "$0" >"$mutant"
  ! grep -Fqx "$marker_call" "$mutant" || fail 'marker-before-zero mutation did not apply'
  assert_named_guard_failure marker-before "$mutant" guard-marker-derivation \
    'verification-removal mutant expected one operation-path assertion, found 0'

  mutant="$root/marker-after-zero.sh"
  awk -v needle="$marker_after" -v replacement="$marker_missing" '
    $0 == needle { print replacement; changed++; next }
    { print }
    END { if (changed != 1) exit 42 }
  ' "$0" >"$mutant"
  grep -Fqx "$marker_missing" "$mutant" || fail 'marker-after-zero mutation did not apply'
  assert_named_guard_failure marker-after "$mutant" guard-marker-derivation \
    'verification-removal mutation did not apply'

  mutant="$root/bare-guard-restored.sh"
  awk -v needle="$census_call" '
    $0 == "  before=$(grep -Fxc \"$ablation_call\" \"$0\" || true)" {
      print "  before=$(grep -Fxc \"$ablation_call\" \"$0\")"
      changed++
      next
    }
    $0 == needle { next }
    { print }
    END { if (changed != 1) exit 42 }
  ' "$0" >"$mutant"
  chmod +x "$mutant"
  # shellcheck disable=SC2016
  grep -Fqx '  before=$(grep -Fxc "$ablation_call" "$0")' "$mutant" ||
    fail 'bare-guard restoration mutant did not apply'
  log="$root/bare-guard-restored.log"
  if "$mutant" "$repo_root" guard-census-derivation >"$log" 2>&1; then
    fail 'bare-guard restoration mutant passed'
  fi
  if grep -q '^FAIL:' "$log"; then
    fail "bare-guard restoration mutant did not reproduce a silent death: $(tr '\n' ' ' <"$log")"
  fi
  guard_mutants_rejected=$((guard_mutants_rejected + 1))
  [ "$guard_forced_failures" -eq "$guard_sites" ] ||
    fail "guard census found $guard_sites sites but forced $guard_forced_failures"
  [ "$guard_named_failures" -eq "$guard_forced_failures" ] ||
    fail "guard proof forced $guard_forced_failures failures but named $guard_named_failures"
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

receipt_field() {
  local key=$1 value=''
  [ -f "$receipt" ] || return 0
  while IFS='=' read -r field value; do
    if [ "$field" = "$key" ]; then
      printf '%s' "$value"
      return 0
    fi
  done <"$receipt"
}

assert_atomic_fresh() {
  local remote output remote_head changed commits lock record
  local lock_amaru lock_configs record_amaru record_configs first_resolver
  remote=$(create_remote fresh-atomic)
  run_transport fresh-atomic "$remote"
  output=$(cat "$stdout")
  resolver_invocations=$(grep -c '^resolver ' "$resolver_log" || true)
  [ "$resolver_invocations" -ge 2 ] ||
    fail "resolver invocations=$resolver_invocations, want >=2 after Amaru override"
  [ "$transport_rc" -eq 0 ] ||
    fail "fresh atomic proposal failed: $(tr '\n' ' ' <"$stderr")"
  [[ "$output" =~ ^[0-9a-f]{40}$ ]] ||
    fail "fresh atomic proposal emitted malformed head: $output"
  remote_head=$(git --git-dir="$remote" rev-parse "refs/heads/$branch")
  [ "$output" = "$remote_head" ] || fail 'fresh atomic output differs from pushed head'
  first_resolver=$(grep '^resolver ' "$resolver_log" | head -n 1)
  [[ "$first_resolver" == *"amaru_rev=$upstream_sha"* ]] ||
    fail "first resolver invocation was not after the Amaru override: $first_resolver"
  [[ "$first_resolver" == *"cwd=$state/bootstrap"* ]] ||
    fail "resolver was not clone-local: $first_resolver"
  amaru_overrides=$(grep -c 'input=amaru ' "$nix_log" || true)
  configs_overrides=$(grep -c 'input=cardano-configurations ' "$nix_log" || true)
  [ "$amaru_overrides" -ge 1 ] || fail 'Amaru override was not invoked'
  [ "$configs_overrides" -ge 1 ] || fail 'configurations override was not invoked'
  changed=$(git --git-dir="$remote" diff --name-only main "$branch" | sort)
  [ "$changed" = "$atomic_paths" ] ||
    fail "fresh proposal changed: $changed"
  changed_paths=$(printf '%s\n' "$changed" | grep -c . || true)
  commits=$(git --git-dir="$remote" rev-list --count "main..$branch")
  [ "$commits" -eq 1 ] || fail "fresh proposal commits=$commits, want 1"
  proposal_commits=$commits
  lock=$(git --git-dir="$remote" show "$branch:flake.lock")
  record=$(git --git-dir="$remote" show "$branch:nix/peer-snapshots/resolution.json")
  lock_amaru=$(jq -er '.nodes.amaru.locked.rev' <<<"$lock")
  lock_configs=$(jq -er '.nodes["cardano-configurations"].locked.rev' <<<"$lock")
  record_amaru=$(jq -er '.amaru_rev' <<<"$record")
  record_configs=$(jq -er '.configs_rev' <<<"$record")
  [ "$lock_amaru" = "$upstream_sha" ] &&
    [ "$record_amaru" = "$upstream_sha" ] &&
    [ "$lock_configs" = "$selected_configs_sha" ] &&
    [ "$record_configs" = "$selected_configs_sha" ] ||
    fail "tuple mismatch lock_amaru=$lock_amaru record_amaru=$record_amaru lock_configs=$lock_configs record_configs=$record_configs"
  grep -Fq 'gh pr create' "$effects" || fail 'fresh atomic proposal did not create its PR'
}

assert_atomic_adopt() {
  local remote before after output
  remote=$(create_remote atomic-adopt)
  before=$(seed_proposal "$remote" atomic)
  run_transport atomic-adopt "$remote"
  output=$(cat "$stdout")
  after=$(git --git-dir="$remote" rev-parse "refs/heads/$branch")
  [ "$transport_rc" -eq 0 ] ||
    fail "coherent two-path branch was not adopted: $(tr '\n' ' ' <"$stderr")"
  [ "$output" = "$before" ] ||
    fail "atomic adopt emitted '$output', expected $before"
  [ "$after" = "$before" ] || fail 'atomic adopt changed the remote ref'
  ! grep -Fq 'gh pr create' "$effects" || fail 'atomic adopt attempted to create a PR'
  grep -Fq 'gh pr view' "$effects" || fail 'atomic adopt did not reuse the existing PR'
}

assert_pr86_foreign() {
  local remote before after
  remote=$(create_remote pr86)
  before=$(seed_proposal "$remote" lock-only)
  run_transport pr86 "$remote"
  after=$(git --git-dir="$remote" rev-parse "refs/heads/$branch")
  [ "$transport_rc" -ne 0 ] || fail 'lock-only PR #86 shape was adopted'
  [ ! -s "$stdout" ] || fail 'lock-only PR #86 shape emitted a value'
  grep -Fq 'foreign-proposal-branch' "$stderr" ||
    fail 'lock-only PR #86 shape lacked its named red'
  [ "$after" = "$before" ] || fail 'lock-only PR #86 shape changed the remote ref'
}

assert_foreign_kind() {
  local kind=$1 remote before after
  remote=$(create_remote "foreign-$kind")
  before=$(seed_proposal "$remote" "$kind")
  run_transport "foreign-$kind" "$remote"
  after=$(git --git-dir="$remote" rev-parse "refs/heads/$branch")
  [ "$transport_rc" -ne 0 ] || fail "$kind proposal was adopted"
  grep -Fq 'foreign-proposal-branch' "$stderr" ||
    fail "$kind proposal lacked its named red"
  [ "$after" = "$before" ] || fail "$kind proposal changed the remote ref"
}

assert_inconsistent_tuple_foreign() {
  local field=$1 remote before after
  remote=$(create_remote "inconsistent-$field")
  before=$(seed_inconsistent_atomic "$remote" "$field")
  run_transport "inconsistent-$field" "$remote"
  after=$(git --git-dir="$remote" rev-parse "refs/heads/$branch")
  [ "$transport_rc" -ne 0 ] || fail "inconsistent $field tuple was adopted"
  grep -Fq 'foreign-proposal-branch' "$stderr" ||
    fail "inconsistent $field tuple lacked its named red"
  [ "$after" = "$before" ] || fail "inconsistent $field tuple changed the remote ref"
}

run_atomic_controller() {
  local label=$1 bootstrap_remote=$2
  local fail_mode=${3:-}
  local upstream_remote
  upstream_remote=$(create_remote "$label-upstream")
  prepare_case "$label"
  if [ -n "$fail_mode" ]; then
    export DAILY_AMARU_BOUNDARY_RESOLVER_FAIL=$fail_mode
  fi
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
    DAILY_AMARU_BOUNDARY_RESOLVER_LOG="$resolver_log" \
    DAILY_AMARU_BOUNDARY_NIX_LOG="$nix_log" \
    DAILY_AMARU_BOUNDARY_SELECTED_CONFIGS_REV="$selected_configs_sha" \
    DAILY_AMARU_TRANSPORT="$transport" \
    run_boundary_command "$bin" "$controller" >"$stdout" 2>"$stderr" ||
    controller_rc=$?
  unset DAILY_AMARU_BOUNDARY_RESOLVER_FAIL
}

assert_named_resolver_failure() {
  local mode=$1 bootstrap_remote final_error stage
  bootstrap_remote=$(create_remote "resolver-fail-$mode")
  run_atomic_controller "resolver-fail-$mode" "$bootstrap_remote" "$mode"
  resolver_failures=$((resolver_failures + 1))
  final_error=$(receipt_field error)
  stage=$(receipt_field stage)
  if [ "$final_error" != peer-snapshot-resolution-failed ] ||
    [ "$stage" != bootstrap-proposal ]; then
    if git --git-dir="$bootstrap_remote" show-ref --verify --quiet \
      "refs/heads/$branch"; then
      fail "failing resolver was ignored; proposal was published error=${final_error:-missing}"
    fi
    fail "resolver failure receipt was not named: error=${final_error:-missing} stage=${stage:-missing}"
  fi
  named_receipts=$((named_receipts + 1))
  if git --git-dir="$bootstrap_remote" show-ref --verify --quiet \
    "refs/heads/$branch"; then
    pushes_after_failure=$((pushes_after_failure + 1))
    fail 'resolver failure pushed a proposal branch'
  fi
  if grep -Fq 'gh pr create' "$effects"; then
    prs_after_failure=$((prs_after_failure + 1))
    fail 'resolver failure created a PR'
  fi
  if grep -Eq 'workflow run|real-launch' "$effects" "$stderr"; then
    launches=$((launches + 1))
    fail 'resolver failure reached a launch effect'
  fi
}

assert_resolver_token() {
  local remote output
  remote=$(create_remote resolver-token)
  run_transport resolver-token "$remote" network
  output=$(cat "$stdout")
  [ "$transport_rc" -ne 0 ] || fail 'resolver failure returned success'
  [ "$output" = RESOLVER-FAILED ] ||
    fail "VALUE-CHANNEL leaked non-token bytes: $(od -An -tx1 "$stdout" | tr -d ' \n')"
  if git --git-dir="$remote" show-ref --verify --quiet "refs/heads/$branch"; then
    fail 'resolver failure pushed a proposal branch'
  fi
  ! grep -Fq 'gh pr create' "$effects" || fail 'resolver failure created a PR'
}

assert_skip_resolver_mutant() {
  local mutant="$tmp_root/skip-resolver.sh" before after
  before=$(grep -c 'resolve-peer-snapshots' "$transport" || true)
  [ "$before" -ge 2 ] || fail 'cloned resolver is not invoked'
  awk '
    $0 == "invoke_cloned_resolver() {" || $0 == "resolver_failed() {" {
      print
      print "  : # skip-resolver-mutant"
      print "  return 0"
      print "}"
      skipfn = 1
      next
    }
    skipfn && $0 == "}" { skipfn = 0; next }
    skipfn { next }
    { print }
  ' "$transport" >"$mutant"
  after=$(grep -c 'skip-resolver-mutant' "$mutant" || true)
  [ "$after" -eq 2 ] &&
    [ "$(grep -c 'resolve-peer-snapshots' "$mutant" || true)" -eq 0 ] ||
    fail 'skip-resolver mutation did not apply'
  chmod +x "$mutant"
  reject_scenario_mutant skip-resolver "$mutant" atomic-fresh \
    'resolver invocations=0, want >=2 after Amaru override'
  lock_only_mutants=$((lock_only_mutants + 1))
}

assert_token_drop_mutant() {
  local mutant="$tmp_root/token-drop.sh"
  grep -Fq "emit 'RESOLVER-FAILED'" "$transport" ||
    fail 'resolver failure token is not emitted on the value channel'
  sed "s/emit 'RESOLVER-FAILED'/true/g" "$transport" >"$mutant"
  ! grep -Fq "emit 'RESOLVER-FAILED'" "$mutant" ||
    fail 'token-drop mutation did not apply'
  grep -Fq "peer-snapshot-resolution-failed" "$mutant" ||
    fail 'token-drop mutation removed the failure path'
  chmod +x "$mutant"
  reject_scenario_mutant token-drop "$mutant" atomic-resolver-fail \
    'resolver failure receipt was not named'
}

assert_atomic_peer_snapshot() {
  local field kind
  launches=0
  assert_atomic_fresh
  assert_resolver_token
  assert_atomic_adopt
  assert_pr86_foreign
  for kind in record-only extra-path split; do
    assert_foreign_kind "$kind"
  done
  for field in lock-amaru lock-configs record-amaru record-configs; do
    assert_inconsistent_tuple_foreign "$field"
  done
  for kind in network nonzero malformed; do
    assert_named_resolver_failure "$kind"
  done
  assert_skip_resolver_mutant
  assert_token_drop_mutant
  [ "$named_receipts" -eq "$resolver_failures" ] ||
    fail "named_receipts=$named_receipts resolver_failures=$resolver_failures"
  [ "$pushes_after_failure" -eq 0 ] || fail 'resolver failure had push effects'
  [ "$prs_after_failure" -eq 0 ] || fail 'resolver failure had PR effects'
  [ "$launches" -eq 0 ] || fail "launches=$launches, want 0"
  printf 'PEER-SNAPSHOT-ATOMIC resolver_invocations=%s amaru_overrides=%s configs_overrides=%s changed_paths=%s commits=%s lock_only_mutants=%s resolver_failures=%s named_receipts=%s pushes_after_failure=%s prs_after_failure=%s launches=%s\n' \
    "$resolver_invocations" "$amaru_overrides" "$configs_overrides" \
    "$changed_paths" "$proposal_commits" "$lock_only_mutants" \
    "$resolver_failures" "$named_receipts" "$pushes_after_failure" \
    "$prs_after_failure" "$launches"
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
    assert_guard_diagnostics
    assert_atomic_peer_snapshot
    # shellcheck disable=SC1091
    . "$fixture_root/check-observation.sh"
    run_check_observation_proof
    run_check_observation_boundaries_proof
    printf 'VALUE-CHANNEL operations=%s executed=%s census=complete mutants_rejected=%s\n' \
      "$value_operation_count" "$value_executed_count" "$value_mutants_rejected"
    printf 'VALUE-CHANNEL-FIRED reproduced=malformed-candidate-sha real_git=1 real_transport=1\n'
    printf 'PROPOSAL-REATTEMPT adopt=1 foreign=1 fresh=1 mutants_rejected=4\n'
    print_boundary_path_marker
    printf 'BOUNDARY-PATH-DERIVED verification_removed=rejected seed_fabricated=rejected relative_root=rejected census_ablation_removed=rejected\n'
    printf 'GUARD-DIAGNOSTICS sites=%s forced=%s named=%s mutants_rejected=%s\n' \
      "$guard_sites" "$guard_forced_failures" "$guard_named_failures" \
      "$guard_mutants_rejected"
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
  guard-census-derivation)
    assert_boundary_census_derivation
    ;;
  guard-marker-derivation)
    assert_boundary_marker_derivation
    ;;
  atomic-fresh)
    assert_atomic_fresh
    ;;
  atomic-resolver-fail)
    assert_named_resolver_failure network
    ;;
  atomic-peer-snapshot)
    assert_atomic_peer_snapshot
    ;;
  check-observation)
    # shellcheck disable=SC1091
    . "$fixture_root/check-observation.sh"
    run_check_observation_proof
    ;;
  check-observation-boundaries)
    # shellcheck disable=SC1091
    . "$fixture_root/check-observation.sh"
    run_check_observation_boundaries_proof
    ;;
  *) fail "unknown scenario: $scenario" ;;
esac
