#!/usr/bin/env bash
set -euo pipefail

log_file=${DAILY_AMARU_BOUNDARY_GH_LOG:?DAILY_AMARU_BOUNDARY_GH_LOG is required}
comments_file=${DAILY_AMARU_BOUNDARY_COMMENTS:?DAILY_AMARU_BOUNDARY_COMMENTS is required}
head_sha=${DAILY_AMARU_BOUNDARY_HEAD_SHA:-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}
integrated_sha=${DAILY_AMARU_BOUNDARY_INTEGRATED_SHA:-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb}
pr_state=${DAILY_AMARU_BOUNDARY_PR_STATE:-MERGED}
pr_head_sha=${DAILY_AMARU_BOUNDARY_PR_HEAD_SHA:-$head_sha}
main_sha=${DAILY_AMARU_BOUNDARY_MAIN_SHA:-$integrated_sha}

{
  printf 'gh'
  printf ' %q' "$@"
  printf '\n'
} >>"$log_file"
printf 'boundary-gh diagnostic: %s\n' "$*" >&2

case "${1:-} ${2:-}" in
  'repo clone')
    [ "$#" -eq 6 ] && [ "$5" = -- ] && [ "$6" = --filter=blob:none ] || exit 64
    repository=$3
    directory=$4
    case "$repository" in
      "${DAILY_AMARU_BOOTSTRAP_REPOSITORY:-lambdasistemi/amaru-bootstrap}")
        remote=${DAILY_AMARU_BOUNDARY_BOOTSTRAP_REMOTE:?bootstrap remote is required}
        ;;
      "${DAILY_AMARU_REPOSITORY:-cardano-foundation/cardano-node-antithesis}")
        remote=${DAILY_AMARU_BOUNDARY_REPOSITORY_REMOTE:?repository remote is required}
        ;;
      *) exit 64 ;;
    esac
    git clone --quiet --filter=blob:none "file://$remote" "$directory"
    printf 'boundary-gh clone diagnostic\n'
    ;;

  'pr create')
    shift 2
    repository=''
    branch=''
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -R) repository=${2:?}; shift 2 ;;
        --base | --title | --body) shift 2 ;;
        --head) branch=${2:?}; shift 2 ;;
        *) exit 64 ;;
      esac
    done
    [ -n "$repository" ] && [ -n "$branch" ] || exit 64
    printf 'https://example.invalid/%s/pull/fresh\n' "$repository"
    ;;

  'pr view')
    if [ "$#" -eq 9 ] && [ "$4" = -R ] && [ "$6" = --json ] &&
      [ "$7" = url ] && [ "$8" = --jq ] && [ "$9" = .url ]; then
      printf 'https://example.invalid/%s/pull/existing\n' "$5"
    elif [ "$#" -eq 7 ] && [ "$4" = -R ] && [ "$6" = --json ] &&
      [ "$7" = state,headRefOid,mergeCommit ]; then
      if [ "$pr_state" = MERGED ]; then
        printf '{"state":"%s","headRefOid":"%s","mergeCommit":{"oid":"%s"}}\n' \
          "$pr_state" "$pr_head_sha" "$integrated_sha"
      else
        printf '{"state":"%s","headRefOid":"%s","mergeCommit":null}\n' \
          "$pr_state" "$pr_head_sha"
      fi
    else
      exit 64
    fi
    ;;

  'issue comment')
    [ "$#" -eq 7 ] && [[ "$3" =~ ^[0-9]+$ ]] && [ "$4" = -R ] &&
      [ "$6" = --body ] || exit 64
    shift 3
    body=''
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -R) shift 2 ;;
        --body) body=${2:?}; shift 2 ;;
        *) exit 64 ;;
      esac
    done
    [ -n "$body" ] || exit 64
    printf '%s\n' "$body" >>"$comments_file"
    printf 'boundary-gh comment diagnostic\n'
    ;;

  'api '*)
    if [ "$#" -eq 5 ] && [ "$2" = --paginate ] &&
      [[ "$3" == repos/*/issues/*/comments\?per_page=100 ]] &&
      [ "$4" = --jq ] && [ "$5" = '.[].body' ]; then
      cat "$comments_file"
    elif [ "$#" -eq 2 ] && [[ "$2" == repos/*/actions/runs\?head_sha=*\&per_page=100 ]]; then
      target=${2#repos/}; target=${target%%/actions/*}
      if [ "$target" = "${DAILY_AMARU_BOOTSTRAP_REPOSITORY:-lambdasistemi/amaru-bootstrap}" ]; then
        printf '{"workflow_runs":[{"name":"CI","check_suite_id":10,"head_sha":"%s"}]}\n' "$head_sha"
      else
        printf '{"workflow_runs":[{"name":"Build and push component images for cardano-node testnet","check_suite_id":1,"head_sha":"%s"},{"name":"tracer-sidecar CI","check_suite_id":2,"head_sha":"%s"},{"name":"Build documentation","check_suite_id":3,"head_sha":"%s"},{"name":"PR preview","check_suite_id":4,"head_sha":"%s"}]}\n' "$head_sha" "$head_sha" "$head_sha" "$head_sha"
      fi
    elif [ "$#" -eq 2 ] && [[ "$2" == repos/*/check-suites/10/check-runs\?per_page=100 ]]; then
      printf '{"check_runs":[{"name":"Build Gate","head_sha":"%s","conclusion":"success"},{"name":"Live Bootstrap Producer","head_sha":"%s","conclusion":"success"}]}\n' "$head_sha" "$head_sha"
    elif [ "$#" -eq 2 ] && [[ "$2" == repos/*/check-suites/[1-4]/check-runs\?per_page=100 ]]; then
      suite=${2#*/check-suites/}; suite=${suite%%/*}
      case "$suite" in
        1) names=('publish-images' 'Compose smoke test') ;;
        2) names=('Build' 'Run unit Tests' 'Check code quality') ;;
        3) names=('build-docs') ;;
        4) names=('preview') ;;
      esac
      printf '{"check_runs":['
      separator=''
      for name in "${names[@]}"; do
        printf '%s{"name":"%s","head_sha":"%s","conclusion":"success"}' "$separator" "$name" "$head_sha"
        separator=,
      done
      printf ']}\n'
    elif [ "$#" -eq 4 ] && [[ "$2" == repos/*/git/ref/heads/main ]] &&
      [ "$3" = --jq ] && [ "$4" = .object.sha ]; then
      printf '%s\n' "$main_sha"
    else
      exit 64
    fi
    ;;

  'workflow run')
    [ "$#" -eq 13 ] && [ "$3" = cardano-node.yaml ] && [ "$4" = -R ] &&
      [ "$6" = --ref ] && [ "$8" = -f ] && [ "$9" = test=cardano_amaru ] &&
      [ "${10}" = -f ] && [ "${11}" = duration=1 ] && [ "${12}" = -f ] &&
      [ "${13}" = no-faults=false ] || exit 64
    printf 'boundary-gh workflow diagnostic\n'
    ;;

  'run list')
    [ "$#" -eq 16 ] && [ "$3" = -R ] && [ "$5" = --workflow ] &&
      [ "$6" = cardano-node.yaml ] && [ "$7" = --commit ] &&
      [ "$9" = --event ] && [ "${10}" = workflow_dispatch ] &&
      [ "${11}" = --limit ] && [ "${12}" = 10 ] && [ "${13}" = --json ] &&
      [ "${14}" = databaseId,createdAt ] && [ "${15}" = --jq ] || exit 64
    printf '4242\n'
    ;;

  'run watch')
    [ "$#" -eq 6 ] && [ "$3" = 4242 ] && [ "$4" = -R ] &&
      [ "$6" = --exit-status ] || exit 64
    printf 'boundary-gh watch diagnostic\n'
    ;;

  *) exit 64 ;;
esac
