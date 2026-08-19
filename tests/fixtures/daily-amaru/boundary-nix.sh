#!/usr/bin/env bash
set -euo pipefail

[ "$#" -eq 5 ] && [ "$1" = flake ] && [ "$2" = lock ] &&
  [ "$3" = --override-input ] || {
  printf 'boundary-nix: rejected arguments\n' >&2
  exit 64
}

input_name=$4
reference=$5
[[ "$reference" =~ ^github:pragma-org/amaru/([0-9a-f]{40})$ ]] || {
  printf 'boundary-nix: rejected reference: %s\n' "$reference" >&2
  exit 64
}
sha=${BASH_REMATCH[1]}
tmp=flake.lock.boundary-new

jq --arg input "$input_name" --arg sha "$sha" '
  (.nodes.root.inputs[$input] |
    if type == "array" then .[0] else . end) as $node |
  .nodes[$node].original.owner = "pragma-org" |
  .nodes[$node].original.repo = "amaru" |
  .nodes[$node].locked.rev = $sha |
  .nodes[$node].locked.narHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" |
  .nodes[$node].locked.lastModified = 1787075200
' flake.lock >"$tmp"
mv "$tmp" flake.lock
printf 'warning: boundary-nix rewrote %s\n' "$input_name" >&2
