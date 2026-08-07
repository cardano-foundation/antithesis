#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
suite="$repo_root/tests/test-daily-cardano-node-head.sh"

fail() {
  printf 'CONTAINMENT-FAIL: %s\n' "$*" >&2
  exit 1
}

bwrap_command=$(command -v bwrap || true)
[ -n "$bwrap_command" ] && [ -x "$bwrap_command" ] ||
  fail 'required containment mechanism is unavailable: bwrap'

scratch_root=$(mktemp -d /tmp/daily-cardano-node-head-contain.XXXXXX) ||
  fail 'could not create containment scratch root'
trap 'rm -rf -- "$scratch_root"' EXIT

printf 'CONTAINMENT network=none scratch=%s repository=read-only\n' "$scratch_root"
"$bwrap_command" \
  --unshare-net \
  --die-with-parent \
  --new-session \
  --ro-bind / / \
  --dev /dev \
  --remount-ro /dev \
  --bind "$scratch_root" "$scratch_root" \
  --clearenv \
  --setenv HOME "$scratch_root" \
  --setenv TMPDIR "$scratch_root" \
  --setenv XDG_CACHE_HOME "$scratch_root/cache" \
  --setenv PATH "$PATH" \
  --setenv LANG C \
  --setenv LC_ALL C \
  --chdir "$repo_root" \
  "$suite"
