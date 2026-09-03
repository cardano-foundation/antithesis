#!/usr/bin/env bash
# shellcheck disable=SC2016 # Entry scripts expand only inside their child shells.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
container_repo=/repo
container_scratch=/scratch
container_runtime=/runtime
suite="$container_repo/tests/test-daily-cardano-node-head.sh"

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
find_command=$(command -v find || true)
[ -n "$find_command" ] && [ -x "$find_command" ] ||
  fail 'required containment inode scanner is unavailable: find'
nix_store_command=$(command -v nix-store || true)
[ -n "$nix_store_command" ] && [ -x "$nix_store_command" ] ||
  fail 'required containment closure resolver is unavailable: nix-store'

scratch_root=$(mktemp -d /tmp/daily-cardano-node-head-contain.XXXXXX) ||
  fail 'could not create containment scratch root'
runtime_root=$(mktemp -d /tmp/daily-cardano-node-head-runtime.XXXXXX) || {
  rm -rf -- "$scratch_root"
  fail 'could not create containment runtime root'
}
trap 'rm -rf -- "$scratch_root" "$runtime_root"' EXIT

mkdir -p "$scratch_root/home" "$scratch_root/cache" "$runtime_root/bin"

# Resolve an explicit command set to immutable Nix store paths. The sandbox
# receives this directory rather than host profile/run trees, keeping the
# constructed filesystem view limited to what the suite actually executes.
runtime_commands=(
  awk bash cat chmod dirname env grep mkdir mktemp rm sed socat sort tr
)
runtime_command_store_roots=()
for command_name in "${runtime_commands[@]}"; do
  command_path=$(command -v "$command_name" || true)
  [ -n "$command_path" ] && [ -x "$command_path" ] ||
    fail "required containment runtime command is unavailable: $command_name"
  command_path=$(readlink -f "$command_path") ||
    fail "could not resolve containment runtime command: $command_name"
  case "$command_path" in
    /nix/store/*) ;;
    *) fail "containment runtime command is outside /nix/store: $command_path" ;;
  esac
  store_suffix=${command_path#/nix/store/}
  runtime_command_store_roots+=("/nix/store/${store_suffix%%/*}")
  ln -s "$command_path" "$runtime_root/bin/$command_name"
done

closure_result="$scratch_root/runtime-store-closure"
if ! "$nix_store_command" --query --requisites \
  "${runtime_command_store_roots[@]}" >"$closure_result"; then
  fail 'could not resolve containment runtime store closure'
fi
mapfile -t runtime_store_paths <"$closure_result"
[ "${#runtime_store_paths[@]}" -gt 0 ] ||
  fail 'containment runtime store closure is empty'

# A read-only bind still permits operations on socket and FIFO inodes. Scan
# every host path that will be bound into the region and reject the closed set
# of special inode types before bwrap can make any of them reachable by name.
scan_bound_path() {
  local label=$1
  local bound_path=$2
  local scan_result="$scratch_root/inode-scan.log"
  local forbidden_inode=''

  [ -d "$bound_path" ] ||
    fail "containment bound path is not a directory: $label=$bound_path"
  if ! "$find_command" "$bound_path" \
    ! -type f ! -type d ! -type l -print -quit >"$scan_result"; then
    fail "could not scan containment bound path: $label=$bound_path"
  fi
  if [ -s "$scan_result" ]; then
    IFS= read -r forbidden_inode <"$scan_result" || true
    fail "containment bound path has forbidden inode: $label=$forbidden_inode"
  fi
}

scan_bound_path repository "$repo_root"
runtime_store_bind_args=()
for store_path in "${runtime_store_paths[@]}"; do
  case "$store_path" in
    /nix/store/*) ;;
    *) fail "runtime closure path is outside /nix/store: $store_path" ;;
  esac
  scan_bound_path runtime-store "$store_path"
  runtime_store_bind_args+=(
    --dir "$store_path"
    --ro-bind "$store_path" "$store_path"
  )
done
scan_bound_path runtime "$runtime_root"
scan_bound_path scratch "$scratch_root"
printf 'CONTAINMENT bound-path=repository inode-types=regular,directory,symlink\n'
printf 'CONTAINMENT bound-path=runtime-store-closure paths=%s inode-types=regular,directory,symlink\n' \
  "${#runtime_store_paths[@]}"
printf 'CONTAINMENT bound-path=runtime inode-types=regular,directory,symlink\n'
printf 'CONTAINMENT bound-path=scratch inode-types=regular,directory,symlink\n'

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
  --dir /nix \
  --dir /nix/store \
  "${runtime_store_bind_args[@]}" \
  --dir "$container_repo" \
  --ro-bind "$repo_root" "$container_repo" \
  --dir "$container_runtime" \
  --ro-bind "$runtime_root" "$container_runtime" \
  --dir "$container_scratch" \
  --bind "$scratch_root" "$container_scratch" \
  --dir /usr \
  --dir /usr/bin \
  --symlink "$container_runtime/bin/env" /usr/bin/env \
  --dev /dev \
  --remount-ro /dev \
  --proc /proc \
  --remount-ro /proc \
  --remount-ro / \
  --clearenv \
  --setenv HOME "$container_scratch/home" \
  --setenv TMPDIR "$container_scratch" \
  --setenv XDG_CACHE_HOME "$container_scratch/cache" \
  --setenv PATH "$container_runtime/bin" \
  --setenv LANG C \
  --setenv LC_ALL C \
  --chdir "$container_repo" \
  "$container_runtime/bin/bash" -c "$verify_fds_and_exec" bash "$suite"
