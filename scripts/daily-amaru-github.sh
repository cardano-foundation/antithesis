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

marker_census() {
  issue_bodies
}

validate_head() {
  [[ "$1" =~ ^[0-9a-f]{40}$ ]] || die "invalid workflow head: $1"
}

# Claim an append-only pre-launch marker. A successful census is captured
# before it is searched, so a failed `gh` cannot masquerade as no match.
claim_prelaunch_marker() {
  local kind=$1 value=$2 head=$3 census line marker legacy_marker
  local current_prefix previous_head='' recorded_head='' found=0

  if ! census=$(marker_census); then # census-fails-closed
    emit 'BLOCKED census-unreadable'
    return 1
  fi

  if [ "$kind" = day ]; then
    while IFS= read -r line; do
      if [[ "$line" =~ ^\<\!--\ daily-amaru\ day="$value"\ launch-consumed\ head=[0-9a-f]{40}\ --\>$ ]]; then
        emit 'BLOCKED launch-consumed'
        return 1 # launch-consumed-final
      fi
    done <<<"$census"
    legacy_marker="<!-- daily-amaru day=$value claim -->"
    current_prefix="<!-- daily-amaru day=$value claim head="
    marker="<!-- daily-amaru day=$value claim head=$head -->"
  else
    legacy_marker="<!-- daily-amaru attempted-sha=$value -->"
    current_prefix="<!-- daily-amaru attempted-sha=$value head="
    marker="<!-- daily-amaru attempted-sha=$value head=$head -->"
  fi

  while IFS= read -r line; do
    if [ "$line" = "$legacy_marker" ]; then
      found=1
      previous_head=legacy
      continue
    fi
    if [[ "$line" == "$current_prefix"*' -->' ]]; then
      recorded_head=${line#"$current_prefix"}
      recorded_head=${recorded_head%' -->'}
      [[ "$recorded_head" =~ ^[0-9a-f]{40}$ ]] || continue
      found=1
      previous_head=$recorded_head
      if [ "$recorded_head" = "$head" ]; then # unchanged-head-guard
        emit 'BLOCKED unchanged-head'
        return 1
      fi
    fi
  done <<<"$census"

  comment_issue "$marker"
  if [ "$found" -eq 0 ]; then
    emit 'CLAIMED'
  else
    emit "SUPERSEDED previous-head=$previous_head"
  fi
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
    url=$(find_pr "$target_repository" "$branch" "$identity")
  fi
  printf '%s\n' "$url"
}

find_pr() {
  local target_repository=$1
  local branch=$2
  local identity=$3

  with_identity "$identity" gh pr view "$branch" -R "$target_repository" \
    --json url --jq .url
}

classify_proposal_branch() {
  local directory=$1
  local branch=$2
  local upstream_sha=$3
  local input_node=$4
  local remote_ref="refs/remotes/origin/$branch"
  local merge_base changed_output lock
  local -a changed=()

  if ! git -C "$directory" show-ref --verify --quiet "$remote_ref"; then
    printf 'absent\n'
    return 0
  fi

  merge_base=$(git -C "$directory" merge-base origin/main "$remote_ref") || return 1
  changed_output=$(git -C "$directory" diff --name-only "$merge_base" "$remote_ref") ||
    return 1
  mapfile -t changed < <(printf '%s' "$changed_output")
  if [ "${#changed[@]}" -ne 1 ] || [ "${changed[0]}" != flake.lock ]; then
    printf 'foreign\n'
    return 0
  fi

  lock=$(git -C "$directory" show "$remote_ref:flake.lock") || return 1
  if jq -e --arg node "$input_node" --arg sha "$upstream_sha" '
      .nodes[$node].original.owner == "pragma-org" and
      .nodes[$node].original.repo == "amaru" and
      .nodes[$node].locked.rev == $sha
    ' <<<"$lock" >/dev/null; then
    printf 'adoptable\n'
  else
    printf 'foreign\n'
  fi
}

operation=${1:?transport operation is required}
shift

# Reserve the caller's stdout once, then make ordinary stdout diagnostic for
# the complete dispatch. Only emit can reach the operation-value channel.
exec {value_fd}>&1
exec 1>&2

emit() {
  printf '%s\n' "$@" >&"$value_fd"
}

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
        emit "MISSING-COMMAND $command"
        die "missing command: $command"
      fi
    done
    emit "OK: ${#requirements[@]} scheduled dependencies present: ${requirements[*]}"
    ;;

  claim-day)
    # repository-token-permissions: issues=write
    require_commands gh grep
    day=${1:?day is required}
    head=${2:?head is required}
    [[ "$day" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "invalid UTC day: $day"
    validate_head "$head"
    claim_prelaunch_marker day "$day" "$head"
    ;;

  resolve-upstream)
    require_commands git
    origin=${1:?origin is required}
    ref=${2:?ref is required}
    git ls-remote --heads "$origin" "$ref" |
      while IFS=$'\t' read -r sha observed_ref; do
        emit "$origin|$observed_ref|$sha"
      done
    ;;

  last-success-sha)
    # repository-token-permissions: issues=read
    require_commands gh sed tail
    last_success=$(issue_bodies |
      sed -nE 's/^<!-- daily-amaru last-success sha=([0-9a-f]{40}) -->$/\1/p' |
      tail -n 1)
    [ -z "$last_success" ] || emit "$last_success"
    ;;

  claim-sha-attempt)
    # repository-token-permissions: issues=write
    require_commands gh grep
    sha=${1:?upstream SHA is required}
    head=${2:?head is required}
    [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || die "invalid upstream SHA: $sha"
    validate_head "$head"
    claim_prelaunch_marker sha "$sha" "$head"
    ;;

  claim-launch)
    # repository-token-permissions: issues=write
    require_commands gh grep
    day=${1:?day is required}
    head=${2:?head is required}
    [[ "$day" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "invalid UTC day: $day"
    validate_head "$head"
    if ! census=$(marker_census); then # census-fails-closed
      emit 'BLOCKED census-unreadable'
      exit 1
    fi
    while IFS= read -r line; do
      if [[ "$line" =~ ^\<\!--\ daily-amaru\ day="$day"\ launch-consumed\ head=[0-9a-f]{40}\ --\>$ ]]; then
        emit 'BLOCKED launch-consumed'
        exit 1 # launch-consumed-final
      fi
    done <<<"$census"
    comment_issue "<!-- daily-amaru day=$day launch-consumed head=$head -->"
    emit 'CLAIMED'
    ;;

  propose-bootstrap)
    require_commands gh git jq nix
    upstream_sha=${1:?upstream SHA is required}
    day=${DAILY_AMARU_DAY:?DAILY_AMARU_DAY is required}
    directory=$state_dir/bootstrap
    branch="daily-amaru/bootstrap-$day-${upstream_sha:0:12}"

    [ ! -e "$directory" ] || die "bootstrap workspace already exists: $directory"
    with_identity "$bootstrap_identity" gh repo clone "$bootstrap_repository" "$directory" -- --filter=blob:none

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

    proposal_state=$(classify_proposal_branch \
      "$directory" "$branch" "$upstream_sha" "$input_node") ||
      die 'proposal branch classification failed'
    case "$proposal_state" in
      adoptable)
        bootstrap_head=$(git -C "$directory" rev-parse "refs/remotes/origin/$branch")
        pr_url=$(find_pr "$bootstrap_repository" "$branch" "$bootstrap_identity")
        printf '%s\n' "$pr_url" >"$state_dir/bootstrap-pr"
        emit "$bootstrap_head"
        ;;
      foreign)
        die 'foreign-proposal-branch'
        ;;
      absent)
        git -C "$directory" checkout -b "$branch" origin/main
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
        emit "$(git -C "$directory" rev-parse HEAD)"
        ;;
      *) die "invalid proposal branch classification: $proposal_state" ;;
    esac
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
    emit "$rows"
    ;;

  resolve-image)
    require_commands docker tr
    candidate=${1:?bootstrap candidate is required}
    image_tag="$producer_image:$candidate"
    digest=$(docker buildx imagetools inspect "$image_tag" \
      --format '{{json .Manifest.Digest}}' | tr -d '"')
    [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || die "invalid registry digest: $digest"
    emit "$image_tag@$digest"
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
    emit "$(git -C "$directory" rev-parse HEAD)"
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
    emit "$rows"
    ;;

  run-producer-check)
    require_commands git
    candidate=${1:?consumer candidate is required}
    directory=$state_dir/consumer
    [ "$(git -C "$directory" rev-parse HEAD)" = "$candidate" ] ||
      die 'consumer workspace is not at the exact candidate head'
    producer_evidence=$(
      cd "$directory"
      scripts/check-amaru-producer-image-refs.sh
    )
    printf '%s\n' "$producer_evidence" >&2
    emit "$producer_evidence"
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
    emit "$merged"
    ;;

  fake-launch)
    workflow=${1:?workflow is required}
    testnet=${2:?testnet is required}
    duration=${3:?duration is required}
    no_faults=${4:?fault setting is required}
    integrated=${5:?integrated SHA is required}
    emit "fake://$workflow/$testnet/$duration/$no_faults/$integrated"
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
    emit "https://github.com/$repository/actions/runs/$run_id"
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
