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

# The bootstrap surface belongs to `lambdasistemi/amaru-bootstrap`, not to this
# repository, and the two must never be confused: the names below are the ones
# that repository actually publishes. `CI` is `.github/workflows/ci.yml`, whose
# jobs are `Build Gate` (`build-gate`) and `Live Bootstrap Producer`
# (`live-bootstrap-producer`). A name absent from that repository yields no
# duration evidence and no candidate-exact rows, so the observation fails for a
# reason unrelated to the candidate -- which is what made every scheduled run
# between 2026-08-23 and 2026-09-01 red within seconds.
bootstrap_check_workflow=${DAILY_AMARU_BOOTSTRAP_CHECK_WORKFLOW:-CI}
bootstrap_required_checks=${DAILY_AMARU_BOOTSTRAP_CHECKS:-Build Gate,Live Bootstrap Producer}
poll_ceiling=${DAILY_AMARU_BOOTSTRAP_CHECK_POLL_SECONDS:-60}

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

# Did the attempt recorded by this exact marker complete successfully? The
# census already fetched for the markers answers from the receipts it carries:
# `stage=complete` is published by every exit-0 controller path and by nothing
# else — failures publish `outcome=FAILED` under their own stage — so the
# completed stage, not any single outcome name, is the success predicate. A
# fourth exit-0 outcome added tomorrow is covered by this census without
# touching it. Both the value and the head must match the marker exactly: a
# receipt from another attempt must never stand in for this one.
attempt_completed() {
  local kind=$1 value=$2 attempt_head=$3 census_text=$4
  local key_field key_prefix
  case "$kind" in
    day) key_field=day ;;
    sha) key_field=upstream_sha ;;
    *)
      printf 'daily-amaru-github: unknown pre-launch claim kind: %s\n' "$kind" >&2
      return 1
      ;;
  esac
  key_prefix="- $key_field="
  awk -v key_prefix="$key_prefix" -v key_value="$value" \
    -v attempt_head="$attempt_head" '
    function flush_receipt() {
      if (in_receipt && stage == "complete" &&
          workflow_head == attempt_head && key == key_value) {
        found = 1
      }
    }
    $0 == "<!-- daily-amaru receipt -->" {
      flush_receipt()
      in_receipt = 1
      stage = workflow_head = key = ""
      next
    }
    in_receipt && /^<!-- / {
      flush_receipt()
      in_receipt = 0
      next
    }
    in_receipt && /^- stage=/ {
      stage = substr($0, 9)
      next
    }
    in_receipt && /^- workflow_head=/ {
      workflow_head = substr($0, 17)
      next
    }
    in_receipt && index($0, key_prefix) == 1 {
      key = substr($0, length(key_prefix) + 1)
      next
    }
    END { flush_receipt(); exit found ? 0 : 1 }
  ' <<<"$census_text"
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
        if ! attempt_completed "$kind" "$value" "$head" "$census"; then
          # The census is the record this message always claimed to be
          # reading: with no completed receipt naming this exact attempt, the
          # standing outcome is the earlier failure, or an attempt that never
          # completed — and repeating it would only reproduce it. Runs
          # 33292550661 and 33357412134 were red for two days on the bare
          # token alone, which names neither input nor the earlier attempt
          # this one would have repeated.
          printf 'daily-amaru-github: declining to repeat an attempt: %s=%s was already claimed at controller head %s and neither has moved since; the outcome of that earlier attempt still stands\n' \
            "$kind" "$value" "$head" >&2
          emit 'BLOCKED unchanged-head'
          return 1
        fi
        # A completed receipt names this exact attempt: its outcome stands
        # and it is a success, so re-entering tonight is a deliberate no-op
        # on the record — never an unnamed failure. The night continues from
        # the SUPERSEDED verdict below; AWAITING re-enters the supervised
        # integration it is still entitled to, up to its own staleness alarm.
        printf 'daily-amaru-github: attempt %s=%s at controller head %s already completed successfully; continuing as a recorded no-op\n' \
          "$kind" "$value" "$head" >&2
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

# The boundary a failing census was attempting must reach the caller, but
# `rows=$(collect_action_rows ...)` discards the callee's variables.
# Splitting the census from its entry point keeps the name in an ordinary
# local -- no out-of-band record that could itself fail, go stale, or be
# absent -- and the entry point appends it to the failure-path stdout the
# caller already captures. Successful stdout is unchanged.
observation_boundary() {
  observation_boundary_name=$1
}

observation_boundary_receipt() {
  sed -n 's/^observation-boundary \([a-z][a-z0-9-]*\)$/\1/p' <<<"$1" |
    tail -n 1
}

collect_action_rows_census() {
  local target_repository=$1
  local head=$2
  local identity=${3:-${GH_TOKEN:-}}
  local runs workflow suite run_head jobs run_tsv

  observation_boundary runs-api
  runs=$(with_identity "$identity" gh api \
    "repos/$target_repository/actions/runs?head_sha=$head&per_page=100") ||
    return 1
  # Process substitution would discard a jq parse failure as an empty census.
  observation_boundary runs-parse
  run_tsv=$(jq -r \
    '.workflow_runs[] | [.name, (.check_suite_id | tostring), .head_sha] | @tsv' \
    <<<"$runs") || return 1
  while IFS=$'\t' read -r workflow suite run_head; do
    [ -n "$suite" ] || continue
    observation_boundary check-runs-api
    jobs=$(with_identity "$identity" gh api \
      "repos/$target_repository/check-suites/$suite/check-runs?per_page=100") ||
      return 1
    observation_boundary check-runs-parse
    jq -r --arg workflow "$workflow" --arg head "$run_head" \
      '.check_runs[] | [$workflow, .name, (.head_sha // $head), (.conclusion // .status)] | join("|")' \
      <<<"$jobs" || return 1
  done <<<"$run_tsv"
}

collect_action_rows() {
  local observation_boundary_name=''
  collect_action_rows_census "$@" && return 0
  [ -n "$observation_boundary_name" ] ||
    die 'observation census failed before reaching any boundary'
  printf 'observation-boundary %s\n' "$observation_boundary_name"
  return 1
}

# D229-2 fails closed on unbounded evidence. A historical run that hung far
# longer than this job may live cannot describe a window this run could
# observe, so such a sample is discarded rather than clamped into the window:
# clamping would substitute exactly the "unrelated constant" D229-2 forbids.
# The surviving maximum is still observed evidence, never a default.
bootstrap_observation_ceiling() {
  local ceiling=${DAILY_AMARU_BOOTSTRAP_CHECK_MAX_SECONDS:-7200}
  [[ "$ceiling" =~ ^[1-9][0-9]*$ ]] ||
    die "bootstrap observation ceiling is unusable: $ceiling"
  printf '%s\n' "$ceiling"
}

bootstrap_observation_duration() {
  local target_repository=$1
  local identity=$2
  local duration runs ceiling

  duration=${DAILY_AMARU_BOOTSTRAP_CHECK_DURATION_SECONDS:-}
  if [[ "$duration" =~ ^[1-9][0-9]*$ ]]; then
    printf '%s\n' "$duration"
    return 0
  fi
  ceiling=$(bootstrap_observation_ceiling) || return 1
  runs=$(with_identity "$identity" gh api \
    "repos/$target_repository/actions/runs?per_page=30") || return 1
  duration=$(jq -r --arg workflow "$bootstrap_check_workflow" \
    --argjson ceiling "$ceiling" '
    [.workflow_runs[]
     | select(.name == $workflow)
     | select(.status == "completed")
     | select(.run_started_at != null and .updated_at != null)
     | ((.updated_at | fromdateiso8601) - (.run_started_at | fromdateiso8601))]
    | map(select(. > 0 and . <= $ceiling))
    | if length == 0 then empty else (max | floor | tostring) end
  ' <<<"$runs") || return 1
  [[ "$duration" =~ ^[1-9][0-9]*$ ]] || return 1
  printf '%s\n' "$duration"
}

# A required name that never appears is indistinguishable from a check that
# never ran, unless the census also says what the candidate did publish.
# Naming the observed surface turns a required/actual name mismatch into a
# one-night diagnosis instead of a timeout repeated nightly. `awk` only: `sort`
# is not a member of the scheduled command census.
observed_check_surface() {
  local candidate=$1
  local rows=$2
  local surface
  surface=$(awk -F'|' -v head="$candidate" '
    $3 == head && !seen[$1 "/" $2]++ {
      list = list separator $1 "/" $2
      separator = ","
    }
    END { print list }
  ' <<<"$rows")
  printf '%s\n' "${surface:-none}"
}

classify_bootstrap_check() {
  local name=$1
  local candidate=$2
  local rows=$3
  local success=0 failed=0 pending=0 total=0
  local check_name head state

  while IFS='|' read -r _ check_name head state; do
    [ "$check_name" = "$name" ] || continue
    [ "$head" = "$candidate" ] || continue
    total=$((total + 1))
    case "$state" in
      success) success=$((success + 1)) ;;
      queued | in_progress | waiting | pending | requested)
        pending=$((pending + 1))
        ;;
      *) failed=$((failed + 1)) ;;
    esac
  done <<<"$rows"

  if [ "$total" -eq 0 ]; then
    printf '%s\n' absent
    return 0
  fi
  if [ "$failed" -gt 0 ] || [ "$success" -gt 1 ]; then
    printf '%s\n' failed
    return 0
  fi
  if [ "$success" -eq 1 ] && [ "$pending" -eq 0 ] && [ "$total" -eq 1 ]; then
    printf '%s\n' success
    return 0
  fi
  if [ "$success" -eq 1 ]; then
    printf '%s\n' failed
    return 0
  fi
  printf '%s\n' pending
}

observe_bootstrap_checks() {
  local candidate=$1
  local identity=$2
  local checks duration start now deadline cadence remaining window
  local polls=0 rows status name
  local first_absent='' first_pending='' first_failed='' last_boundary=''
  local ever_valid=0 last_transport=0 all_success
  local -a required=()

  checks=$bootstrap_required_checks
  IFS=',' read -r -a required <<<"$checks"
  [ "${#required[@]}" -gt 0 ] || die 'bootstrap required checks are empty'
  now=$(date +%s) || die 'observation clock is unreadable'
  [[ "$now" =~ ^[0-9]+$ ]] || die 'observation clock is unusable'
  start=$now

  while true; do
    polls=$((polls + 1))
    last_transport=0
    first_absent=''
    first_pending=''
    first_failed=''
    all_success=1
    if rows=$(collect_action_rows "$bootstrap_repository" "$candidate" \
      "$identity"); then
      ever_valid=1
      for name in "${required[@]}"; do
        status=$(classify_bootstrap_check "$name" "$candidate" "$rows")
        case "$status" in
          success) ;;
          failed)
            first_failed=$name
            all_success=0
            break
            ;;
          absent | pending)
            all_success=0
            if [ "$status" = absent ]; then
              [ -n "$first_absent" ] || first_absent=$name
            else
              [ -n "$first_pending" ] || first_pending=$name
            fi
            ;;
          *)
            die "bootstrap check classifier returned unusable state $status"
            ;;
        esac
      done
      if [ -n "$first_failed" ]; then
        die "bootstrap check failed on $candidate: $first_failed polls=$polls"
      fi
      if [ "$all_success" -eq 1 ]; then
        printf 'bootstrap-check-observation polls=%s\n' "$polls" >&2
        emit "$rows"
        return 0
      fi
    else
      last_transport=1
      last_boundary=$(observation_boundary_receipt "$rows")
      [ -n "$last_boundary" ] ||
        die "bootstrap check observation boundary is unrecorded on $candidate polls=$polls"
    fi

    if [ -z "${deadline:-}" ]; then
      # The deadline is the absolute ceiling, never a statistic over past
      # runs. The nightly's own bump is the one run nobody pre-builds into
      # cachix, so completed-run durations structurally exclude the case they
      # would bound: nightly 33837021124 derived ~402s of history while the
      # build it watched ran 1269s and was still executing when this observer
      # declared it never-reported. History only chooses how often the census
      # is taken; only a conclusion, a genuine absence, or the ceiling ends
      # the wait. Absent history is not fatal: the cadence falls back to the
      # poll ceiling and the window to the absolute ceiling.
      window=$(bootstrap_observation_ceiling)
      duration=$(bootstrap_observation_duration "$bootstrap_repository" \
        "$identity") || duration=''
      deadline=$((start + window))
      if [[ "$duration" =~ ^[1-9][0-9]*$ ]]; then
        if [ "$duration" -le 1 ]; then
          cadence=1
        else
          cadence=$((duration / 2))
        fi
      else
        cadence=$poll_ceiling
      fi
      # Half of a long window is a poll rate that can miss a check reporting
      # and completing between two observations. Only how often the window is
      # looked at is bounded.
      if [ "$cadence" -gt "$poll_ceiling" ]; then
        cadence=$poll_ceiling
      fi
    fi

    now=$(date +%s) || die 'observation clock is unreadable'
    if [ "$now" -ge "$deadline" ]; then
      if [ "$last_transport" -eq 1 ] || [ "$ever_valid" -eq 0 ]; then
        die "bootstrap check transport-exhausted on $candidate polls=$polls boundary=${last_boundary:-unnamed}"
      fi
      if [ -n "$first_pending" ]; then
        die "bootstrap check still-running on $candidate: $first_pending polls=$polls observed=$(observed_check_surface "$candidate" "$rows") ceiling=$window: the required check is still executing past the absolute observation ceiling, so the ceiling itself is wrong and must be raised (DAILY_AMARU_BOOTSTRAP_CHECK_MAX_SECONDS) before the next nightly"
      fi
      die "bootstrap check never-reported on $candidate: ${first_absent:-${required[0]}} polls=$polls observed=$(observed_check_surface "$candidate" "$rows")"
    fi
    remaining=$((deadline - now))
    if [ "$remaining" -gt "$cadence" ]; then
      remaining=$cadence
    fi
    sleep "$remaining"
  done
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

atomic_path_census() {
  local expected_lock=0 expected_record=0 path
  [ "$#" -eq 2 ] || return 1
  for path in "$@"; do
    case "$path" in
      flake.lock) expected_lock=1 ;;
      nix/peer-snapshots/resolution.json) expected_record=1 ;;
      *) return 1 ;;
    esac
  done
  [ "$expected_lock" -eq 1 ] && [ "$expected_record" -eq 1 ]
}

lock_node_by_origin() {
  local lock=$1 owner=$2 repo=$3
  jq -r --arg owner "$owner" --arg repo "$repo" '
    [.nodes | to_entries[] |
     select(.value.original.owner == $owner and
            .value.original.repo == $repo) | .key] |
    if length == 1 then .[0] else empty end
  ' <<<"$lock"
}

classify_proposal_branch() {
  local directory=$1
  local branch=$2
  local upstream_sha=$3
  local input_node=$4
  local remote_ref="refs/remotes/origin/$branch"
  local merge_base changed_output lock record configs_node
  local lock_amaru lock_configs record_amaru record_configs
  local commit_count main_sha
  local -a changed=()

  if ! git -C "$directory" show-ref --verify --quiet "$remote_ref"; then
    printf 'absent\n'
    return 0
  fi

  merge_base=$(git -C "$directory" merge-base origin/main "$remote_ref") || return 1
  main_sha=$(git -C "$directory" rev-parse origin/main) || return 1
  commit_count=$(git -C "$directory" rev-list --count "$merge_base..$remote_ref") ||
    return 1
  changed_output=$(git -C "$directory" diff --name-only "$merge_base" "$remote_ref") ||
    return 1
  mapfile -t changed < <(printf '%s\n' "$changed_output")
  if [ "$merge_base" != "$main_sha" ] || [ "$commit_count" -ne 1 ] ||
    ! atomic_path_census "${changed[@]}"; then
    printf 'foreign\n'
    return 0
  fi

  lock=$(git -C "$directory" show "$remote_ref:flake.lock") || return 1
  if ! record=$(git -C "$directory" show "$remote_ref:nix/peer-snapshots/resolution.json"); then
    printf 'foreign\n'
    return 0
  fi
  configs_node=$(lock_node_by_origin "$lock" cardano-foundation cardano-configurations)
  lock_amaru=$(jq -er --arg node "$input_node" '.nodes[$node].locked.rev' \
    <<<"$lock") || {
    printf 'foreign\n'
    return 0
  }
  lock_configs=$(jq -er --arg node "$configs_node" '.nodes[$node].locked.rev' \
    <<<"$lock") || {
    printf 'foreign\n'
    return 0
  }
  record_amaru=$(jq -er '.amaru_rev' <<<"$record") || {
    printf 'foreign\n'
    return 0
  }
  record_configs=$(jq -er '.configs_rev' <<<"$record") || {
    printf 'foreign\n'
    return 0
  }
  if [[ "$lock_amaru" =~ ^[0-9a-f]{40}$ ]] &&
    [[ "$lock_configs" =~ ^[0-9a-f]{40}$ ]] &&
    [ "$lock_amaru" = "$upstream_sha" ] &&
    [ "$record_amaru" = "$upstream_sha" ] &&
    [ "$lock_configs" = "$record_configs" ]; then
    printf 'adoptable\n'
  else
    printf 'foreign\n'
  fi
}

root_input_for_node() {
  local lock_file=$1 node=$2
  jq -r --arg node "$node" '
    [.nodes.root.inputs | to_entries[] |
     select((if (.value | type) == "array" then .value[0] else .value end) == $node) |
     .key] | if length == 1 then .[0] else empty end
  ' "$lock_file"
}

resolver_failed() {
  emit 'RESOLVER-FAILED'
  die 'peer-snapshot-resolution-failed'
}

invoke_cloned_resolver() {
  local directory=$1
  [ -x "$directory/scripts/resolve-peer-snapshots" ] || return 1
  (cd "$directory" && ./scripts/resolve-peer-snapshots --write)
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

  awaiting-integration-age)
    # repository-token-permissions: issues=read
    require_commands gh awk date
    sha=${1:?upstream SHA is required}
    current_day=${2:?current day is required}
    [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || die "invalid upstream SHA: $sha"
    normalized_day=$(date -u --date="$current_day" +%F) || die 'invalid current day'
    [ "$normalized_day" = "$current_day" ] || die 'invalid current day'
    receipt_rows=''
    receipt_rows=$(issue_bodies | awk '
      function flush_receipt() {
        if (in_receipt && stage == "complete" && outcome == "AWAITING" &&
            run_outcome == "awaiting-integration" && day != "" && sha != "") {
          print day "|" sha
        }
      }
      $0 == "<!-- daily-amaru receipt -->" {
        flush_receipt()
        in_receipt = 1
        day = stage = outcome = run_outcome = sha = ""
        next
      }
      in_receipt && /^<!-- / {
        flush_receipt()
        in_receipt = 0
        next
      }
      in_receipt && /^- day=/ {
        day = $0
        sub(/^- day=/, "", day)
        next
      }
      in_receipt && /^- stage=/ {
        stage = $0
        sub(/^- stage=/, "", stage)
        next
      }
      in_receipt && /^- outcome=/ {
        outcome = $0
        sub(/^- outcome=/, "", outcome)
        next
      }
      in_receipt && /^- upstream_sha=/ {
        sha = $0
        sub(/^- upstream_sha=/, "", sha)
        next
      }
      in_receipt && /^- run_outcome=/ {
        run_outcome = $0
        sub(/^- run_outcome=/, "", run_outcome)
        next
      }
      END { flush_receipt() }
    ') || die 'awaiting receipt census failed'
    declare -A awaiting_days=()
    while IFS='|' read -r receipt_day receipt_sha; do
      [ "$receipt_sha" = "$sha" ] || continue
      [[ "$receipt_day" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || continue
      awaiting_days["$receipt_day"]=1
    done <<<"$receipt_rows"
    awaiting_age=1
    cursor=$current_day
    while :; do
      previous_day=$(date -u --date="$cursor -1 day" +%F) ||
        die 'could not derive previous receipt day'
      [[ -v "awaiting_days[$previous_day]" ]] || break
      awaiting_age=$((awaiting_age + 1))
      cursor=$previous_day
    done
    emit "$awaiting_age"
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
    lock_text=$(<"$directory/flake.lock")
    input_node=$(lock_node_by_origin "$lock_text" pragma-org amaru)
    [ -n "$input_node" ] || die 'expected exactly one stock pragma-org/amaru lock node'
    input_name=$(root_input_for_node "$directory/flake.lock" "$input_node")
    [ -n "$input_name" ] || die 'expected exactly one root input for the stock Amaru node'
    configs_node=$(lock_node_by_origin "$lock_text" cardano-foundation \
      cardano-configurations)
    [ -n "$configs_node" ] ||
      die 'expected exactly one cardano-configurations lock node'
    configs_input_name=$(root_input_for_node "$directory/flake.lock" "$configs_node")
    [ -n "$configs_input_name" ] ||
      die 'expected exactly one root input for cardano-configurations'

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
          nix flake lock --override-input "$input_name" \
            "github:pragma-org/amaru/$upstream_sha"
        )
        invoke_cloned_resolver "$directory" || true
        record=$directory/nix/peer-snapshots/resolution.json
        [ -f "$record" ] || resolver_failed
        record_amaru=$(jq -er '.amaru_rev' "$record") || resolver_failed
        record_configs=$(jq -er '.configs_rev' "$record") || resolver_failed
        [ "$record_amaru" = "$upstream_sha" ] || resolver_failed
        [[ "$record_configs" =~ ^[0-9a-f]{40}$ ]] || resolver_failed
        (
          cd "$directory"
          nix flake lock --override-input "$configs_input_name" \
            "github:cardano-foundation/cardano-configurations/$record_configs"
        )
        invoke_cloned_resolver "$directory" || resolver_failed
        record_amaru=$(jq -er '.amaru_rev' "$record") || resolver_failed
        record_configs=$(jq -er '.configs_rev' "$record") || resolver_failed
        jq -e --arg node "$input_node" --arg sha "$upstream_sha" '
          .nodes[$node].original.owner == "pragma-org" and
          .nodes[$node].original.repo == "amaru" and
          .nodes[$node].locked.rev == $sha
        ' "$directory/flake.lock" >/dev/null || resolver_failed
        jq -e --arg node "$configs_node" --arg sha "$record_configs" '
          .nodes[$node].locked.rev == $sha
        ' "$directory/flake.lock" >/dev/null || resolver_failed
        jq -e --arg amaru "$upstream_sha" --arg configs "$record_configs" '
          .amaru_rev == $amaru and .configs_rev == $configs
        ' "$record" >/dev/null || resolver_failed
        mapfile -t changed < <(git -C "$directory" diff --name-only)
        atomic_path_census "${changed[@]}" || resolver_failed
        git -C "$directory" add -- flake.lock nix/peer-snapshots/resolution.json
        mapfile -t changed < <(git -C "$directory" diff --cached --name-only)
        atomic_path_census "${changed[@]}" || resolver_failed
        git -C "$directory" -c user.name='daily-amaru' \
          -c user.email='daily-amaru@users.noreply.github.com' \
          commit -m "chore: bump stock Amaru to $upstream_sha"
        [ "$(git -C "$directory" rev-list --count origin/main..HEAD)" -eq 1 ] ||
          resolver_failed
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
    require_commands gh jq awk date sleep
    candidate=${1:?bootstrap candidate is required}
    [[ "$candidate" =~ ^[0-9a-f]{40}$ ]] ||
      die "invalid bootstrap candidate: $candidate"
    observe_bootstrap_checks "$candidate" "$bootstrap_identity"
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
    if [ "$state" != MERGED ]; then
      emit "AWAITING $pr_url"
      printf 'daily-amaru-github: consumer repin is awaiting guarded integration\n' >&2
      exit 75
    fi
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
