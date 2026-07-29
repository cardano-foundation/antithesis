#!/usr/bin/env bash

# Enforce the Amaru bootstrap producer image contract across Compose files.
# Every discovered reference must be digest-pinned and all must be identical.
#
# Usage: scripts/check-amaru-producer-image-refs.sh [compose-root]
#   compose-root  directory to search recursively (default: testnets)
set -euo pipefail

REPO='ghcr.io/lambdasistemi/amaru-bootstrap-producer'
ROOT="${1:-testnets}"

if [ ! -d "$ROOT" ]; then
  echo "FAIL: compose root '$ROOT' is not a directory" >&2
  exit 1
fi

# Discover every image field referencing the producer repo in Compose files.
refs=$(find "$ROOT" -type f \( -name '*.yaml' -o -name '*.yml' \) \
  -exec grep -h "image:.*${REPO}" {} + 2>/dev/null \
  | sed 's/.*image:[[:space:]]*//' \
  | sort) || true

count=$(printf '%s\n' "$refs" | grep -c . 2>/dev/null) || count=0

if [ "$count" -eq 0 ]; then
  echo "FAIL: zero producer-image references found below '$ROOT'" >&2
  echo "An empty census cannot establish the contract." >&2
  exit 1
fi

# Validate every discovered value: repository:tag@sha256:<64 hex>.
bad_form=0
while IFS= read -r ref; do
  [ -z "$ref" ] && continue
  if ! printf '%s\n' "$ref" \
    | grep -Eq "^${REPO}:[^@[:space:]]+@sha256:[0-9a-f]{64}$"; then
    echo "FAIL: reference lacks tagged digest-pinned form: $ref" >&2
    bad_form=1
  fi
done <<< "$refs"

if [ "$bad_form" -ne 0 ]; then
  echo "Every producer image must be ${REPO}:<tag>@sha256:<64 hex>." >&2
  exit 1
fi

# All validated references must be byte-for-byte identical.
unique=$(printf '%s\n' "$refs" | grep . | sort -u)
unique_count=$(printf '%s\n' "$unique" | grep -c .)

if [ "$unique_count" -ne 1 ]; then
  echo "FAIL: $unique_count distinct producer-image references found;" >&2
  echo "all must be identical." >&2
  printf '%s\n' "$unique" | while IFS= read -r u; do
    echo "  $u" >&2
  done
  exit 1
fi

echo "OK: $count producer-image reference(s), all pinned to $unique"
