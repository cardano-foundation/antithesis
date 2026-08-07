#!/usr/bin/env bash
# shellcheck disable=SC2016 # Entry scripts expand only inside their child shells.
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
bash_command=$(command -v bash || true)
[ -n "$bash_command" ] && [ -x "$bash_command" ] ||
  fail 'required containment entry shell is unavailable: bash'

scratch_root=$(mktemp -d /tmp/daily-cardano-node-head-contain.XXXXXX) ||
  fail 'could not create containment scratch root'
trap 'rm -rf -- "$scratch_root"' EXIT

printf 'CONTAINMENT network=none scratch=%s repository=read-only\n' "$scratch_root"
# Close caller capabilities before bwrap starts. The inner launcher then closes
# bwrap's own setup descriptor and proves the suite receives only stdio.
close_fds_and_exec='
for fd_path in /proc/self/fd/*; do
  fd=${fd_path##*/}
  case "$fd" in
    0 | 1 | 2) ;;
    *[!0-9]*) ;;
    *) eval "exec ${fd}>&-" ;;
  esac
done
exec "$@"
'
verify_fds_and_exec='
for fd_path in /proc/$$/fd/*; do
  fd=${fd_path##*/}
  case "$fd" in
    0 | 1 | 2) ;;
    *[!0-9]*) ;;
    *) eval "exec ${fd}>&-" ;;
  esac
done
for fd_path in /proc/$$/fd/*; do
  fd=${fd_path##*/}
  case "$fd" in
    0 | 1 | 2) continue ;;
    *[!0-9]*) continue ;;
  esac
  [[ -e "$fd_path" ]] || continue
  printf "CONTAINMENT-FAIL: inherited descriptor survived entry: fd=%s\n" \
    "$fd" >&2
  exit 1
done
printf "CONTAINMENT namespaces=all entry-fds=0,1,2\n"
exec "$@"
'

"$bash_command" -c "$close_fds_and_exec" bash \
  "$bwrap_command" \
  --unshare-all \
  --die-with-parent \
  --new-session \
  --ro-bind / / \
  --dev /dev \
  --remount-ro /dev \
  --proc /proc \
  --remount-ro /proc \
  --bind "$scratch_root" "$scratch_root" \
  --clearenv \
  --setenv HOME "$scratch_root" \
  --setenv TMPDIR "$scratch_root" \
  --setenv XDG_CACHE_HOME "$scratch_root/cache" \
  --setenv PATH "$PATH" \
  --setenv LANG C \
  --setenv LC_ALL C \
  --chdir "$repo_root" \
  "$bash_command" -c "$verify_fds_and_exec" bash "$suite"
