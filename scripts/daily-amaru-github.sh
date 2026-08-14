#!/usr/bin/env bash
set -euo pipefail

if [ -n "${DAILY_AMARU_EFFECT_LOG:-}" ]; then
  {
    printf 'transport'
    if [ "$#" -gt 0 ]; then
      printf ' %s' "$@"
    fi
    printf '\n'
  } >>"$DAILY_AMARU_EFFECT_LOG"
fi

repository=${DAILY_AMARU_REPOSITORY:-${GITHUB_REPOSITORY:-cardano-foundation/cardano-node-antithesis}}
receipt_issue=${DAILY_AMARU_RECEIPT_ISSUE:-210}
state_dir=${DAILY_AMARU_STATE_DIR:?DAILY_AMARU_STATE_DIR is required}
bootstrap_repository=${DAILY_AMARU_BOOTSTRAP_REPOSITORY:-lambdasistemi/amaru-bootstrap}
producer_image=ghcr.io/lambdasistemi/amaru-bootstrap-producer

# The App token authorizes lambdasistemi/amaru-bootstrap only; same-repository
# operations use the workflow's own token. The two are never interchangeable.
bootstrap_identity=${DAILY_AMARU_IDENTITY:-}
repository_identity=${GH_TOKEN:-}

# D213-04: every non-shell command a reachable production operation needs.
# `preflight` reports the first absent member by name.
scheduled_command_census=(
  gh git jq rg sed awk grep tail tr head seq sleep date docker nix
)
consumer_required_checks=(
  'Build and push component images for cardano-node testnet|publish-images'
  'Build and push component images for cardano-node testnet|Compose smoke test'
  'tracer-sidecar CI|Build'
  'tracer-sidecar CI|Run unit Tests'
  'tracer-sidecar CI|Check code quality'
  'Build documentation|build-docs'
  'PR preview|preview'
)

die() {
  printf 'daily-amaru-github: %s\n' "$*" >&2
  exit 1
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

# Per-operation, so publishing a failure receipt never depends on the command
# whose absence it reports.
require_commands() {
  local command
  for command in "$@"; do
    need_command "$command"
  done
}

mkdir -p "$state_dir"

issue_bodies() {
  gh api --paginate "repos/$repository/issues/$receipt_issue/comments?per_page=100" \
    --jq '.[].body'
}

comment_issue() {
  gh issue comment "$receipt_issue" -R "$repository" --body "$1" >/dev/null
}

with_identity() {
  local identity=$1
  shift
  [ -n "$identity" ] || die 'identity is empty'
  GH_TOKEN=$identity "$@"
}

collect_action_rows() {
  local target_repository=$1
  local head=$2
  local identity=${3:-${GH_TOKEN:-}}
  local runs workflow suite run_head jobs

  runs=$(with_identity "$identity" gh api \
    "repos/$target_repository/actions/runs?head_sha=$head&per_page=100")
  while IFS=$'\t' read -r workflow suite run_head; do
    [ -n "$suite" ] || continue
    jobs=$(with_identity "$identity" gh api \
      "repos/$target_repository/check-suites/$suite/check-runs?per_page=100")
    jq -r --arg workflow "$workflow" --arg head "$run_head" '
      .check_runs[] |
      [$workflow, .name, (.head_sha // $head), (.conclusion // .status)] |
      join("|")
    ' <<<"$jobs"
  done < <(jq -r '.workflow_runs[] | [.name, (.check_suite_id | tostring), .head_sha] | @tsv' <<<"$runs")
}

push_branch() {
  local directory=$1
  local branch=$2
  local identity=$3
  with_identity "$identity" git -C "$directory" \
    -c credential.helper='!gh auth git-credential' \
    push origin "HEAD:refs/heads/$branch"
}

create_or_find_pr() {
  local target_repository=$1
  local branch=$2
  local title=$3
  local body=$4
  local identity=$5
  local url

  if ! url=$(with_identity "$identity" gh pr create -R "$target_repository" \
    --base main --head "$branch" --title "$title" --body "$body" 2>/dev/null); then
    url=$(with_identity "$identity" gh pr view "$branch" -R "$target_repository" \
      --json url --jq .url)
  fi
  printf '%s\n' "$url"
}

operation=${1:?transport operation is required}
shift

case "$operation" in
  preflight)
    requirements=()
    if [ "$#" -gt 0 ]; then
      requirements=("$@")
    else
      requirements=("${scheduled_command_census[@]}")
    fi
    for command in "${requirements[@]}"; do
      if ! command -v "$command" >/dev/null 2>&1; then
        printf 'MISSING-COMMAND %s\n' "$command"
        die "missing command: $command"
      fi
    done
    printf 'OK: %s scheduled dependencies present: %s\n' \
      "${#requirements[@]}" "${requirements[*]}"
    ;;

  claim-day)
    # repository-token-permissions: issues=write
    require_commands gh grep
    day=${1:?day is required}
    marker="<!-- daily-amaru day=$day claim -->"
    if issue_bodies | grep -Fqx -- "$marker"; then
      die "UTC day already claimed: $day"
    fi
    comment_issue "$marker"
    ;;

  resolve-upstream)
    require_commands git
    origin=${1:?origin is required}
    ref=${2:?ref is required}
    git ls-remote --heads "$origin" "$ref" |
      while IFS=$'\t' read -r sha observed_ref; do
        printf '%s|%s|%s\n' "$origin" "$observed_ref" "$sha"
      done
    ;;

  last-success-sha)
    # repository-token-permissions: issues=read
    require_commands gh sed tail
    issue_bodies |
      sed -nE 's/^<!-- daily-amaru last-success sha=([0-9a-f]{40}) -->$/\1/p' |
      tail -n 1
    ;;

  claim-sha-attempt)
    # repository-token-permissions: issues=write
    require_commands gh grep
    sha=${1:?upstream SHA is required}
    marker="<!-- daily-amaru attempted-sha=$sha -->"
    if issue_bodies | grep -Fqx -- "$marker"; then
      die "upstream SHA already attempted: $sha"
    fi
    comment_issue "$marker"
    ;;

  propose-bootstrap)
    require_commands gh git jq nix
    upstream_sha=${1:?upstream SHA is required}
    day=${DAILY_AMARU_DAY:?DAILY_AMARU_DAY is required}
    directory=$state_dir/bootstrap
    branch="daily-amaru/bootstrap-$day-${upstream_sha:0:12}"

    [ ! -e "$directory" ] || die "bootstrap workspace already exists: $directory"
    with_identity "$bootstrap_identity" gh repo clone "$bootstrap_repository" "$directory" -- --filter=blob:none
    git -C "$directory" checkout -b "$branch" origin/main

    # TODO(amaru-bootstrap#75): replace this crude stock-pin proposal with
    # the validated producer handoff once that contract lands.
    input_node=$(jq -r '
      [.nodes | to_entries[] |
       select(.value.original.owner == "pragma-org" and
              .value.original.repo == "amaru") | .key] |
      if length == 1 then .[0] else empty end
    ' "$directory/flake.lock")
    [ -n "$input_node" ] || die 'expected exactly one stock pragma-org/amaru lock node'
    input_name=$(jq -r --arg node "$input_node" '
      [.nodes.root.inputs | to_entries[] |
       select((if (.value | type) == "array" then .value[0] else .value end) == $node) |
       .key] | if length == 1 then .[0] else empty end
    ' "$directory/flake.lock")
    [ -n "$input_name" ] || die 'expected exactly one root input for the stock Amaru node'

    (
      cd "$directory"
      nix flake lock --override-input "$input_name" "github:pragma-org/amaru/$upstream_sha"
    )
    mapfile -t changed < <(git -C "$directory" diff --name-only)
    [ "${#changed[@]}" -eq 1 ] && [ "${changed[0]}" = flake.lock ] ||
      die 'stock-pin proposal changed a path other than flake.lock'
    jq -e --arg node "$input_node" --arg sha "$upstream_sha" '
      .nodes[$node].original.owner == "pragma-org" and
      .nodes[$node].original.repo == "amaru" and
      .nodes[$node].locked.rev == $sha
    ' "$directory/flake.lock" >/dev/null || die 'stock Amaru lock validation failed'

    git -C "$directory" add flake.lock
    git -C "$directory" -c user.name='daily-amaru' \
      -c user.email='daily-amaru@users.noreply.github.com' \
      commit -m "chore: bump stock Amaru to $upstream_sha"
    push_branch "$directory" "$branch" "$bootstrap_identity"
    pr_url=$(create_or_find_pr "$bootstrap_repository" "$branch" \
      "chore: bump stock Amaru to ${upstream_sha:0:12}" \
      "Daily Amaru controller proposal for exact upstream $upstream_sha." \
      "$bootstrap_identity")
    printf '%s\n' "$pr_url" >"$state_dir/bootstrap-pr"
    git -C "$directory" rev-parse HEAD
    ;;

  require-bootstrap-checks)
    require_commands gh jq awk
    candidate=${1:?bootstrap candidate is required}
    checks=${DAILY_AMARU_BOOTSTRAP_CHECKS:-Build,Run unit Tests,Check code quality,publish-images}
    rows=$(collect_action_rows "$bootstrap_repository" "$candidate" "$bootstrap_identity")
    IFS=',' read -r -a required <<<"$checks"
    for name in "${required[@]}"; do
      count=$(awk -F'|' -v n="$name" -v h="$candidate" \
        '$2 == n && $3 == h && $4 == "success" { count++ } END { print count + 0 }' \
        <<<"$rows")
      [ "$count" -eq 1 ] || die "bootstrap check is not uniquely successful on $candidate: $name"
    done
    printf '%s\n' "$rows"
    ;;

  resolve-image)
    require_commands docker tr
    candidate=${1:?bootstrap candidate is required}
    image_tag="$producer_image:$candidate"
    digest=$(docker buildx imagetools inspect "$image_tag" \
      --format '{{json .Manifest.Digest}}' | tr -d '"')
    [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || die "invalid registry digest: $digest"
    printf '%s@%s\n' "$image_tag" "$digest"
    ;;

  prepare-consumer-repin)
    # repository-token-permissions: contents=write pull-requests=write
    require_commands gh git rg sed
    image_ref=${1:?image reference is required}
    day=${DAILY_AMARU_DAY:?DAILY_AMARU_DAY is required}
    directory=$state_dir/consumer
    branch="daily-amaru/consumer-$day"

    [ ! -e "$directory" ] || die "consumer workspace already exists: $directory"
    with_identity "$repository_identity" gh repo clone "$repository" "$directory" -- --filter=blob:none
    git -C "$directory" checkout -b "$branch" origin/main
    mapfile -t producer_files < <(
      rg -l "image:.*$producer_image" "$directory/testnets" -g '*.yaml' -g '*.yml'
    )
    [ "${#producer_files[@]}" -gt 0 ] || die 'zero consumer producer-image references found'
    for file in "${producer_files[@]}"; do
      sed -E -i \
        "s#(image:[[:space:]]*)${producer_image}:[^[:space:]]+#\\1${image_ref}#" \
        "$file"
    done
    checker_output=$(
      cd "$directory"
      scripts/check-amaru-producer-image-refs.sh
    )
    printf '%s\n' "$checker_output" >&2
    git -C "$directory" add -- "${producer_files[@]#"$directory/"}"
    git -C "$directory" -c user.name='daily-amaru' \
      -c user.email='daily-amaru@users.noreply.github.com' \
      commit -m "chore: repin Amaru producer to exact digest"
    push_branch "$directory" "$branch" "$repository_identity"
    pr_url=$(create_or_find_pr "$repository" "$branch" \
      'chore: repin Amaru producer to exact digest' \
      "Daily Amaru controller repin to $image_ref. Integration is lane-supervised." \
      "$repository_identity")
    printf '%s\n' "$pr_url" >"$state_dir/consumer-pr"
    git -C "$directory" rev-parse HEAD
    ;;

  require-consumer-checks)
    # repository-token-permissions: actions=read checks=read
    require_commands gh jq awk
    candidate=${1:?consumer candidate is required}
    # TODO(cardano-node-antithesis#208): replace this explicit current-head
    # census with the complete exact-revision interface preflight.
    rows=$(collect_action_rows "$repository" "$candidate" "$repository_identity")
    for required in "${consumer_required_checks[@]}"; do
      workflow=${required%%|*}
      name=${required#*|}
      count=$(awk -F'|' -v w="$workflow" -v n="$name" -v h="$candidate" \
        '$1 == w && $2 == n && $3 == h && $4 == "success" { count++ }
         END { print count + 0 }' <<<"$rows")
      [ "$count" -eq 1 ] ||
        die "consumer check is not uniquely successful on $candidate: $workflow / $name"
    done
    printf '%s\n' "$rows"
    ;;

  run-producer-check)
    require_commands git
    candidate=${1:?consumer candidate is required}
    directory=$state_dir/consumer
    [ "$(git -C "$directory" rev-parse HEAD)" = "$candidate" ] ||
      die 'consumer workspace is not at the exact candidate head'
    (
      cd "$directory"
      scripts/check-amaru-producer-image-refs.sh
    )
    ;;

  await-supervised-integration)
    # repository-token-permissions: contents=read pull-requests=read
    require_commands gh jq
    candidate=${1:?consumer candidate is required}
    # TODO(cardano-node-antithesis#207): replace lane-supervised integration
    # and launch correlation after the guarded unattended platform exists.
    read -r pr_url <"$state_dir/consumer-pr"
    pr_json=$(with_identity "$repository_identity" gh pr view "$pr_url" -R "$repository" \
      --json state,headRefOid,mergeCommit)
    state=$(jq -r .state <<<"$pr_json")
    head=$(jq -r .headRefOid <<<"$pr_json")
    merged=$(jq -r '.mergeCommit.oid // empty' <<<"$pr_json")
    [ "$state" = MERGED ] || die 'consumer repin is awaiting guarded integration'
    [ "$head" = "$candidate" ] || die 'integrated PR head differs from the verified candidate'
    [[ "$merged" =~ ^[0-9a-f]{40}$ ]] || die 'missing merge commit SHA'
    main_head=$(with_identity "$repository_identity" gh api "repos/$repository/git/ref/heads/main" \
      --jq .object.sha)
    [ "$main_head" = "$merged" ] || die 'merged consumer commit is not exact current main'
    printf '%s\n' "$merged"
    ;;

  fake-launch)
    workflow=${1:?workflow is required}
    testnet=${2:?testnet is required}
    duration=${3:?duration is required}
    no_faults=${4:?fault setting is required}
    integrated=${5:?integrated SHA is required}
    printf 'fake://%s/%s/%s/%s/%s\n' \
      "$workflow" "$testnet" "$duration" "$no_faults" "$integrated"
    ;;

  real-launch)
    # repository-token-permissions: actions=write contents=read
    require_commands gh date seq sleep head
    workflow=${1:?workflow is required}
    testnet=${2:?testnet is required}
    duration=${3:?duration is required}
    no_faults=${4:?fault setting is required}
    integrated=${5:?integrated SHA is required}
    [ "$workflow" = cardano-node.yaml ] && [ "$testnet" = cardano_amaru ] &&
      [ "$duration" = duration=1 ] && [ "$no_faults" = no-faults=false ] ||
      die 'real launch shape differs from the frozen contract'
    main_head=$(with_identity "$repository_identity" gh api "repos/$repository/git/ref/heads/main" \
      --jq .object.sha)
    [ "$main_head" = "$integrated" ] || die 'real launch target is not exact main'
    started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    with_identity "$repository_identity" gh workflow run cardano-node.yaml -R "$repository" \
      --ref "$integrated" -f test=cardano_amaru -f duration=1 -f no-faults=false
    run_id=''
    for _ in $(seq 1 30); do
      run_id=$(with_identity "$repository_identity" gh run list -R "$repository" \
        --workflow cardano-node.yaml --commit "$integrated" --event workflow_dispatch \
        --limit 10 --json databaseId,createdAt \
        --jq ".[] | select(.createdAt >= \"$started\") | .databaseId" | head -n 1)
      [ -z "$run_id" ] || break
      sleep 2
    done
    [ -n "$run_id" ] || die 'launched workflow run was not observable'
    with_identity "$repository_identity" gh run watch "$run_id" -R "$repository" --exit-status
    printf 'https://github.com/%s/actions/runs/%s\n' "$repository" "$run_id"
    ;;

  receipt)
    # repository-token-permissions: issues=write
    # Minimum dependency surface on purpose.
    require_commands gh
    # TODO(cardano-node-antithesis#206): replace issue-comment receipts with
    # complete per-property accounting and an independent missing-day alarm.
    body='<!-- daily-amaru receipt -->'
    upstream_sha=''
    outcome=''
    for field in "$@"; do
      body+=$'\n'
      body+="- $field"
      case "$field" in
        upstream_sha=*) upstream_sha=${field#*=} ;;
        outcome=*) outcome=${field#*=} ;;
      esac
    done
    comment_issue "$body"
    if [ "$outcome" = CHANGED ]; then
      [[ "$upstream_sha" =~ ^[0-9a-f]{40}$ ]] || die 'final receipt lacks upstream SHA'
      comment_issue "<!-- daily-amaru last-success sha=$upstream_sha -->"
    fi
    ;;

  *)
    die "unknown transport operation: $operation"
    ;;
esac
