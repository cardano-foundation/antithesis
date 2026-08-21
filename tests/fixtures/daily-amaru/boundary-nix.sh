#!/usr/bin/env bash
set -euo pipefail

[ "$#" -eq 5 ] && [ "$1" = flake ] && [ "$2" = lock ] &&
  [ "$3" = --override-input ] || {
  printf 'boundary-nix: rejected arguments\n' >&2
  exit 64
}

input_name=$4
reference=$5
owner=''
repo=''
sha=''
if [[ "$reference" =~ ^github:pragma-org/amaru/([0-9a-f]{40})$ ]]; then
  owner=pragma-org
  repo=amaru
  sha=${BASH_REMATCH[1]}
elif [[ "$reference" =~ ^github:cardano-foundation/cardano-configurations/([0-9a-f]{40})$ ]]; then
  owner=cardano-foundation
  repo=cardano-configurations
  sha=${BASH_REMATCH[1]}
else
  printf 'boundary-nix: rejected reference: %s\n' "$reference" >&2
  exit 64
fi
tmp=flake.lock.boundary-new

jq --arg input "$input_name" --arg sha "$sha" \
  --arg owner "$owner" --arg repo "$repo" '
  (.nodes.root.inputs[$input] |
    if type == "array" then .[0] else . end) as $node |
  .nodes[$node].original.owner = $owner |
  .nodes[$node].original.repo = $repo |
  .nodes[$node].original.rev = $sha |
  .nodes[$node].locked.rev = $sha |
  .nodes[$node].locked.narHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" |
  .nodes[$node].locked.lastModified = 1787075200
' flake.lock >"$tmp"
mv "$tmp" flake.lock
if [ -n "${DAILY_AMARU_BOUNDARY_NIX_LOG:-}" ]; then
  printf 'nix-override input=%s rev=%s owner=%s repo=%s\n' \
    "$input_name" "$sha" "$owner" "$repo" >>"$DAILY_AMARU_BOUNDARY_NIX_LOG"
fi
printf 'warning: boundary-nix rewrote %s\n' "$input_name" >&2
