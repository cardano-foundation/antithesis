#!/usr/bin/env bash
set -euo pipefail

scenario=${FAKE_SCENARIO:-prepared}
log_file=${FAKE_LOG:?FAKE_LOG is required}
state_dir=${HEAD_CANDIDATE_STATE_DIR:?HEAD_CANDIDATE_STATE_DIR is required}
receipt_file=${HEAD_CANDIDATE_RECEIPT:?HEAD_CANDIDATE_RECEIPT is required}

upstream_sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
other_sha=cccccccccccccccccccccccccccccccccccccccc
digest_hex=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
digest="sha256:${digest_hex}"
fixture_origin=https://github.com/IntersectMBO/cardano-node.git
fixture_ref=refs/heads/master
fixture_mismatch_repository=ghcr.io/example/cardano-node

mkdir -p "$state_dir"

log() {
  printf '%s' "$1" >>"$log_file"
  shift
  if [ "$#" -gt 0 ]; then
    printf ' %s' "$@" >>"$log_file"
  fi
  printf '\n' >>"$log_file"
}

candidate_ref_for() {
  local repository=$1
  local tag=$2
  printf '%s:%s@%s\n' "$repository" "$tag" "$digest"
}

default_topology_rows() {
  local candidate_ref=$1
  local service
  for service in p1 p2 p3 p4 relay1 relay2 relay3; do
    printf '%s|%s\n' "$service" "$candidate_ref"
  done
}

# Witness of render-topology output; do not reconstruct independently.
read_rendered_candidate() {
  local model=$1
  local value=''
  [ -f "$model" ] || {
    printf 'rendered model missing: %s\n' "$model" >&2
    exit 1
  }
  value=$(awk -F= '$1 == "candidate_ref" { sub(/^[^=]*=/, ""); print; exit }' \
    "$model")
  [ -n "$value" ] || {
    printf 'rendered model lacks candidate_ref: %s\n' "$model" >&2
    exit 1
  }
  printf '%s\n' "$value"
}

operation=${1:?transport operation is required}
shift

case "$operation" in
  resolve-upstream)
    requested_origin=${1:?origin is required}
    requested_ref=${2:?ref is required}
    log resolve-upstream "$requested_origin" "$requested_ref"
    case "$scenario" in
      resolve-failure)
        printf 'resolve failed\n' >&2
        exit 1
        ;;
      zero-observation) ;;
      ambiguous-observation)
        printf '%s|%s|%s\n' "$fixture_origin" "$fixture_ref" "$upstream_sha"
        printf '%s|%s|%s\n' "$fixture_origin" "$fixture_ref" "$other_sha"
        ;;
      malformed-observation)
        printf '%s|%s|not-a-full-sha\n' "$fixture_origin" "$fixture_ref"
        ;;
      trailing-field-observation)
        printf '%s|%s|%s|\n' "$fixture_origin" "$fixture_ref" "$upstream_sha"
        ;;
      wrong-origin)
        printf '%s|%s|%s\n' \
          https://github.com/fork/cardano-node.git "$fixture_ref" "$upstream_sha"
        ;;
      wrong-ref)
        printf '%s|%s|%s\n' "$fixture_origin" refs/heads/develop "$upstream_sha"
        ;;
      *)
        printf '%s|%s|%s\n' "$fixture_origin" "$fixture_ref" "$upstream_sha"
        ;;
    esac
    ;;

  publish-candidate)
    sha=${1:?upstream SHA is required}
    repository=${2:?repository is required}
    log publish-candidate "$sha" "$repository"
    case "$scenario" in
      publish-failure)
        printf 'publish failed\n' >&2
        exit 1
        ;;
      malformed-candidate-form)
        printf 'not-a-candidate-ref\n'
        ;;
      repository-whitespace)
        candidate_ref_for 'ghcr.io/cardano foundation/cardano-node' "$sha"
        ;;
      multiline-candidate-form)
        half_a="${repository}:${sha:0:20}"
        half_b="${sha:20}@${digest}"
        printf '%s\n' "$half_a"
        printf '%s\n' "$half_b"
        ;;
      tag-sha-mismatch)
        candidate_ref_for "$repository" "$other_sha"
        ;;
      *)
        candidate_ref_for "$repository" "$sha"
        ;;
    esac
    ;;

  prove-revision)
    candidate_ref=${1:?candidate ref is required}
    log prove-revision "$candidate_ref"
    case "$scenario" in
      revision-absent)
        printf 'revision unavailable\n' >&2
        exit 1
        ;;
      revision-mismatch)
        printf '%s\n' "$other_sha"
        ;;
      multiline-revision)
        printf '%s\n' "${upstream_sha:0:20}"
        printf '%s\n' "${upstream_sha:20}"
        ;;
      unparsable-revision)
        printf 'not-a-revision\n'
        ;;
      *)
        printf '%s\n' "$upstream_sha"
        ;;
    esac
    ;;

  render-topology)
    candidate_ref=${1:?candidate ref is required}
    log render-topology "$candidate_ref"
    if [ "$scenario" = render-failure ]; then
      printf 'render failed\n' >&2
      exit 1
    fi
    model=$state_dir/rendered-model
    if [ "$scenario" = model-outside-state-dir ]; then
      model=${state_dir%/*}/outside-rendered-model
    fi
    rendered_candidate_ref=$candidate_ref
    if [ "$scenario" = rendered-model-candidate-mismatch ]; then
      rendered_candidate_ref=$(candidate_ref_for \
        "$fixture_mismatch_repository" "$other_sha")
    fi
    printf 'candidate_ref=%s\n' "$rendered_candidate_ref" >"$model"
    if [ "$scenario" = multiline-model-path ]; then
      printf '%s\n%s\n' "$model" "$state_dir/second-rendered-model"
    else
      printf '%s\n' "$model"
    fi
    ;;

  describe-topology)
    rendered_model=${1:?rendered model is required}
    log describe-topology "$rendered_model"
    if [ "$scenario" = describe-failure ]; then
      printf 'topology description failed\n' >&2
      exit 1
    fi
    candidate_ref=$(read_rendered_candidate "$rendered_model")
    case "$scenario" in
      zero-topology-census) ;;
      missing-node-service)
        for service in p1 p2 p3 p4 relay1 relay2; do
          printf '%s|%s\n' "$service" "$candidate_ref"
        done
        ;;
      stale-topology-override)
        default_topology_rows "$candidate_ref"
        printf 'sidecar|ghcr.io/intersectmbo/cardano-node:%s@sha256:%s\n' \
          "$other_sha" "$digest_hex"
        ;;
      trailing-field-topology)
        for service in p1 p2 p3 p4 relay1 relay2 relay3; do
          printf '%s|%s|\n' "$service" "$candidate_ref"
        done
        ;;
      empty-topology-service)
        printf '|%s\n' "$candidate_ref"
        default_topology_rows "$candidate_ref"
        ;;
      empty-topology-image)
        printf 'p1|\n'
        for service in p2 p3 p4 relay1 relay2 relay3; do
          printf '%s|%s\n' "$service" "$candidate_ref"
        done
        ;;
      whitespace-topology-image)
        printf 'p1|%s extra\n' "$candidate_ref"
        for service in p2 p3 p4 relay1 relay2 relay3; do
          printf '%s|%s\n' "$service" "$candidate_ref"
        done
        ;;
      duplicate-node-service)
        default_topology_rows "$candidate_ref"
        printf 'p1|%s\n' "$candidate_ref"
        ;;
      *)
        default_topology_rows "$candidate_ref"
        ;;
    esac
    ;;

  validate-compose)
    rendered_model=${1:?rendered model is required}
    log validate-compose "$rendered_model"
    read_rendered_candidate "$rendered_model" >/dev/null
    if [ "$scenario" = compose-failure ]; then
      printf 'compose validation failed\n' >&2
      exit 1
    fi
    ;;

  fake-submit)
    rendered_model=${1:?rendered model is required}
    candidate_ref=${2:?candidate ref is required}
    sha=${3:?upstream SHA is required}
    log fake-submit "$rendered_model" "$candidate_ref" "$sha"
    submitted_candidate=$(read_rendered_candidate "$rendered_model")
    [ "$submitted_candidate" = "$candidate_ref" ] || {
      printf 'submission model candidate mismatch\n' >&2
      exit 1
    }
    if [ "$scenario" = submission-failure ]; then
      printf 'submission failed\n' >&2
      exit 1
    fi
    case "$scenario" in
      multiline-submission)
        printf 'fake://%s\nfake://duplicate\n' "$sha"
        ;;
      malformed-submission)
        printf 'real://%s\n' "$sha"
        ;;
      *) printf 'fake://%s\n' "$sha" ;;
    esac
    ;;

  receipt)
    log receipt "$@"
    {
      printf '%s\n' "$@"
      printf '\n'
    } >>"$receipt_file"
    ;;

  *)
    printf 'unknown transport operation: %s\n' "$operation" >&2
    exit 64
    ;;
esac
