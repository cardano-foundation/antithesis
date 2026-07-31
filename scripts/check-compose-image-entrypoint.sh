#!/usr/bin/env bash
# check-compose-image-entrypoint.sh — verify a Compose service's image
# entrypoint/command contract at the real Docker container boundary.
#
# Usage:
#   ./scripts/check-compose-image-entrypoint.sh \
#     -f <compose-file> [-f <override> ...] \
#     --service <service> \
#     --expected-argv '<JSON string array>' \
#     [--image <repository>@sha256:<64-hex-digest>]
#
# Success: exactly one canonical JSON line on stdout, exit 0.
# Failure: diagnostics on stderr, exit 1.
set -euo pipefail

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf 'INFO: %s\n' "$*" >&2; }

# ── CLI parsing ──────────────────────────────────────────────────────
COMPOSE_FILES=()
SERVICE=""
EXPECTED_ARGV=""
IMAGE_OVERRIDE=""

while [ $# -gt 0 ]; do
  case "$1" in
    -f)
      [ $# -ge 2 ] || die "-f requires an argument"
      COMPOSE_FILES+=("$2"); shift 2 ;;
    --service)
      [ $# -ge 2 ] || die "--service requires an argument"
      SERVICE="$2"; shift 2 ;;
    --expected-argv)
      [ $# -ge 2 ] || die "--expected-argv requires an argument"
      EXPECTED_ARGV="$2"; shift 2 ;;
    --image)
      [ $# -ge 2 ] || die "--image requires an argument"
      IMAGE_OVERRIDE="$2"; shift 2 ;;
    *)
      die "unknown argument: $1" ;;
  esac
done

[ "${#COMPOSE_FILES[@]}" -ge 1 ] || die "at least one -f <compose-file> is required"
[ -n "$SERVICE" ] || die "--service is required"
[ -n "$EXPECTED_ARGV" ] || die "--expected-argv is required"

# Validate expected-argv is a JSON array of strings.
printf '%s' "$EXPECTED_ARGV" | jq -e 'type == "array" and all(.[]; type == "string")' >/dev/null 2>&1 \
  || die "--expected-argv must be a JSON array of strings"

# Validate --image override format before any Docker mutation:
# non-empty repository, then @sha256:<64 lowercase hex>.
if [ -n "$IMAGE_OVERRIDE" ]; then
  printf '%s' "$IMAGE_OVERRIDE" | grep -qE '^.+@sha256:[0-9a-f]{64}$' \
    || die "--image must be in repository@sha256:<64 lowercase hex> form"
fi

# Compose files may reference INTERNAL_NETWORK; default to false for
# isolated checks that do not join an external stack network.
export INTERNAL_NETWORK="${INTERNAL_NETWORK:-false}"

# Build the docker compose -f flags.
COMPOSE_ARGS=()
for f in "${COMPOSE_FILES[@]}"; do
  COMPOSE_ARGS+=(-f "$f")
done

# ── Service discovery ────────────────────────────────────────────────
info "rendering Compose config"
RENDERED_JSON="$(docker compose "${COMPOSE_ARGS[@]}" config --format json 2>/dev/null)" \
  || die "docker compose config failed"

TARGET_COUNT="$(printf '%s' "$RENDERED_JSON" | jq -r --arg s "$SERVICE" \
  '[.services | keys[] | select(. == $s)] | length')"

if [ "$TARGET_COUNT" -eq 0 ]; then
  printf 'ERROR: target_count=0 service=%s not found in rendered Compose\n' "$SERVICE" >&2
  exit 1
fi
info "target_count=${TARGET_COUNT} service=${SERVICE}"

# Extract rendered Compose fields for the service.
SVC_JSON="$(printf '%s' "$RENDERED_JSON" | jq -c --arg s "$SERVICE" '.services[$s]')"
DECLARED_IMAGE="$(printf '%s' "$SVC_JSON" | jq -r '.image // empty')"
[ -n "$DECLARED_IMAGE" ] || die "service ${SERVICE} has no image in rendered Compose"

COMPOSE_ENTRYPOINT="$(printf '%s' "$SVC_JSON" | jq -c '.entrypoint // null')"
COMPOSE_COMMAND="$(printf '%s' "$SVC_JSON" | jq -c '.command // null')"

# ── Image selection ──────────────────────────────────────────────────
if [ -n "$IMAGE_OVERRIDE" ]; then
  CHECKED_IMAGE="$IMAGE_OVERRIDE"
else
  CHECKED_IMAGE="$DECLARED_IMAGE"
fi
info "checked_image=${CHECKED_IMAGE}"

# ── Pull ─────────────────────────────────────────────────────────────
info "pulling ${CHECKED_IMAGE}"
docker pull "$CHECKED_IMAGE" >&2 || die "docker pull failed for ${CHECKED_IMAGE}"

# ── Image inspection ─────────────────────────────────────────────────
IMAGE_INSPECT="$(docker inspect "$CHECKED_IMAGE")" || die "docker inspect failed for ${CHECKED_IMAGE}"

IMAGE_ID="$(printf '%s' "$IMAGE_INSPECT" | jq -r '.[0].Id')"
IMAGE_ENTRYPOINT="$(printf '%s' "$IMAGE_INSPECT" | jq -c '.[0].Config.Entrypoint // null')"
IMAGE_CMD="$(printf '%s' "$IMAGE_INSPECT" | jq -c '.[0].Config.Cmd // null')"

# Derive the repository portion for exact RepoDigests matching.
# For digest references, strip everything after @.
# For tag references, strip a tag colon only when the final path
# component contains one, preserving registry ports
# (localhost:5000/org/image:tag → localhost:5000/org/image).
if printf '%s' "$CHECKED_IMAGE" | grep -q '@'; then
  REPO="${CHECKED_IMAGE%%@*}"
else
  FINAL_COMPONENT="${CHECKED_IMAGE##*/}"
  if printf '%s' "$FINAL_COMPONENT" | grep -q ':'; then
    REPO="${CHECKED_IMAGE%:*}"
  else
    REPO="$CHECKED_IMAGE"
  fi
fi

# Select exactly one matching RepoDigest for this repository by exact
# repository equality around @, then verify the digest format.
MATCH_COUNT="$(printf '%s' "$IMAGE_INSPECT" | jq --arg repo "$REPO" \
  '[.[0].RepoDigests[]? | select(split("@")[0] == $repo)] | length')"
if [ "$MATCH_COUNT" -ne 1 ]; then
  die "expected exactly 1 RepoDigest for repository ${REPO}, found ${MATCH_COUNT}"
fi
RESOLVED_DIGEST="$(printf '%s' "$IMAGE_INSPECT" | jq -r --arg repo "$REPO" \
  '[.[0].RepoDigests[]? | select(split("@")[0] == $repo)][0]')"
printf '%s' "$RESOLVED_DIGEST" | grep -qE "@sha256:[0-9a-f]{64}$" \
  || die "resolved digest has unexpected format: ${RESOLVED_DIGEST}"

# When --image is supplied, require the observed digest to equal it.
if [ -n "$IMAGE_OVERRIDE" ]; then
  [ "$RESOLVED_DIGEST" = "$IMAGE_OVERRIDE" ] \
    || die "resolved digest ${RESOLVED_DIGEST} does not match supplied --image ${IMAGE_OVERRIDE}"
fi
info "resolved_digest=${RESOLVED_DIGEST}"
info "image_id=${IMAGE_ID}"

# ── Isolated container launch ────────────────────────────────────────
SUFFIX="$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')"
PROJECT="cna196-ep-${SUFFIX}"
CONTAINER_NAME="cna196-ep-${SUFFIX}"
NETWORK_NAME="cna196-ep-${SUFFIX}-net"

RUNTIME_OVERRIDE="$(mktemp /tmp/cna196-override-XXXXXX.json)"

# Shared cleanup: compose down with the full file stack, then residue
# checks.  Returns non-zero on incomplete cleanup.
CLEANUP_DONE=0
do_cleanup() {
  if [ "$CLEANUP_DONE" -eq 1 ]; then return 0; fi
  CLEANUP_DONE=1
  info "cleaning up project ${PROJECT}"
  local down_rc=0
  docker compose -p "$PROJECT" "${COMPOSE_ARGS[@]}" -f "$RUNTIME_OVERRIDE" \
    down --volumes --remove-orphans --timeout 10 >&2 || down_rc=$?
  rm -f "$RUNTIME_OVERRIDE"
  local rc=0
  if [ "$down_rc" -ne 0 ]; then
    printf 'ERROR: compose down exited %s\n' "$down_rc" >&2
    rc=1
  fi
  local leftover
  leftover="$(docker ps -a --filter "label=com.docker.compose.project=${PROJECT}" -q)"
  if [ -n "$leftover" ]; then
    printf 'ERROR: cleanup incomplete: containers remain: %s\n' "$leftover" >&2
    rc=1
  fi
  leftover="$(docker network ls --filter "label=com.docker.compose.project=${PROJECT}" -q)"
  if [ -n "$leftover" ]; then
    printf 'ERROR: cleanup incomplete: networks remain: %s\n' "$leftover" >&2
    rc=1
  fi
  leftover="$(docker volume ls --filter "label=com.docker.compose.project=${PROJECT}" -q)"
  if [ -n "$leftover" ]; then
    printf 'ERROR: cleanup incomplete: volumes remain: %s\n' "$leftover" >&2
    rc=1
  fi
  return "$rc"
}

# EXIT trap: run cleanup, preserve an existing failure status but
# upgrade cleanup residue to failure.
# shellcheck disable=SC2329
on_exit() {
  local exit_status=$?
  if ! do_cleanup; then
    exit 1
  fi
  exit "$exit_status"
}
trap on_exit EXIT

# Write the runtime override: isolate the service, prevent collisions.
jq -n \
  --arg svc "$SERVICE" \
  --arg cname "$CONTAINER_NAME" \
  --arg img "$CHECKED_IMAGE" \
  --arg net "$NETWORK_NAME" \
  '{
    services: { ($svc): { container_name: $cname, image: $img, restart: "no", depends_on: {} } },
    networks: { default: { name: $net } }
  }' > "$RUNTIME_OVERRIDE"

info "starting isolated container project=${PROJECT} service=${SERVICE}"
docker compose -p "$PROJECT" "${COMPOSE_ARGS[@]}" -f "$RUNTIME_OVERRIDE" \
  up -d --no-deps "$SERVICE" >&2 || die "docker compose up failed"

# ── Bounded startup observation ──────────────────────────────────────
STARTUP_DEADLINE=$((SECONDS + 15))
STATE=""
while true; do
  STATE="$(docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo unknown)"
  if [ "$STATE" = "running" ]; then
    break
  fi
  if [ "$STATE" = "exited" ] || [ "$STATE" = "dead" ]; then
    LOGS="$(docker logs --tail 20 "$CONTAINER_NAME" 2>&1 || true)"
    die "container start/runtime mismatch: service=${SERVICE} state=${STATE} logs: ${LOGS}"
  fi
  if [ "$SECONDS" -ge "$STARTUP_DEADLINE" ]; then
    die "container did not start within 15s (state=${STATE})"
  fi
  sleep 1
done

# ── Image provenance check (C2) ──────────────────────────────────────
CONTAINER_IMAGE_ID="$(docker inspect -f '{{.Image}}' "$CONTAINER_NAME" 2>/dev/null || echo unknown)"
[ "$CONTAINER_IMAGE_ID" = "$IMAGE_ID" ] \
  || die "container image ${CONTAINER_IMAGE_ID} does not match inspected image ${IMAGE_ID}"

# ── Runtime argv comparison ──────────────────────────────────────────
RUNTIME_PATH="$(docker inspect -f '{{.Path}}' "$CONTAINER_NAME")"
RUNTIME_ARGS="$(docker inspect -f '{{json .Args}}' "$CONTAINER_NAME")"
RUNTIME_ARGV="$(jq -cn --arg p "$RUNTIME_PATH" --argjson a "$RUNTIME_ARGS" '[$p] + $a')"

ARGV_MATCH="$(jq -n --argjson actual "$RUNTIME_ARGV" --argjson expected "$EXPECTED_ARGV" \
  '$actual == $expected')"
if [ "$ARGV_MATCH" != "true" ]; then
  die "runtime argv mismatch: service=${SERVICE} actual=${RUNTIME_ARGV} expected=${EXPECTED_ARGV}"
fi
info "runtime_argv=${RUNTIME_ARGV} matches expected"

# ── Stabilization (C4) ───────────────────────────────────────────────
info "stabilization: waiting 3s"
sleep 3
STATE="$(docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo unknown)"
[ "$STATE" = "running" ] \
  || die "container not running after stabilization (state=${STATE})"

# ── Assemble success JSON (buffered, C3) ─────────────────────────────
SUCCESS_JSON="$(jq -cn \
  --arg schema "compose-image-entrypoint/v1" \
  --argjson target_count "$TARGET_COUNT" \
  --arg service "$SERVICE" \
  --arg declared_image "$DECLARED_IMAGE" \
  --arg checked_image "$CHECKED_IMAGE" \
  --arg resolved_digest "$RESOLVED_DIGEST" \
  --arg image_id "$IMAGE_ID" \
  --argjson image_entrypoint "$IMAGE_ENTRYPOINT" \
  --argjson image_cmd "$IMAGE_CMD" \
  --argjson compose_entrypoint "$COMPOSE_ENTRYPOINT" \
  --argjson compose_command "$COMPOSE_COMMAND" \
  --argjson runtime_argv "$RUNTIME_ARGV" \
  --arg state "$STATE" \
  '{
    schema: $schema,
    target_count: $target_count,
    service: $service,
    declared_image: $declared_image,
    checked_image: $checked_image,
    resolved_digest: $resolved_digest,
    image_id: $image_id,
    image_entrypoint: $image_entrypoint,
    image_cmd: $image_cmd,
    compose_entrypoint: $compose_entrypoint,
    compose_command: $compose_command,
    runtime_argv: $runtime_argv,
    state: $state
  }')"

# ── Cleanup before publishing (C3) ───────────────────────────────────
info "cleaning up before publishing result"
do_cleanup || die "cleanup failed before publish"
info "cleanup verified: zero containers, networks, volumes"

# ── Publish ──────────────────────────────────────────────────────────
printf '%s\n' "$SUCCESS_JSON"
exit 0
