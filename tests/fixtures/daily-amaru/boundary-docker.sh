#!/usr/bin/env bash
set -euo pipefail
[ "$#" -eq 6 ] && [ "$1" = buildx ] && [ "$2" = imagetools ] &&
  [ "$3" = inspect ] && [ "$5" = --format ] &&
  [ "$6" = '{{json .Manifest.Digest}}' ] || exit 64
printf 'boundary-docker diagnostic\n' >&2
printf '"sha256:%064d"\n' 0
