#!/usr/bin/env bash
# Validate the Actions expression contexts of every workflow GitHub will
# evaluate in this repository.
#
# GitHub rejects a workflow whose expressions reference a context that is not
# available where they are written, and it does so before creating any job. The
# run then reports no failing job at all, so nothing else in CI can observe it.
# This command is the observation: it enumerates the complete tracked census,
# proves that census is not empty, and validates every file in it exactly once.
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

config=.github/actionlint.yaml

if ! command -v actionlint >/dev/null 2>&1; then
  printf 'WORKFLOW-VALIDATION-ERROR actionlint is not on PATH; run through nix develop\n' >&2
  exit 1
fi

mapfile -t workflows < <(
  git ls-files '.github/workflows/*.yaml' '.github/workflows/*.yml' | sort -u
)

# A census that silently became empty would pass every remaining check while
# validating nothing, which is exactly the shape of failure this command exists
# to make impossible.
if [ "${#workflows[@]}" -eq 0 ]; then
  printf 'WORKFLOW-VALIDATION-ERROR empty workflow census under .github/workflows\n' >&2
  exit 1
fi

for workflow in "${workflows[@]}"; do
  printf 'workflow-census %s\n' "$workflow"
done

# actionlint's embedded shellcheck and pyflakes integrations are switched off
# so this command owns exactly the Actions expression-context class and its
# result does not depend on which linters happen to be on PATH. Shell analysis
# is a separate, explicitly scoped step of the local gate (`just check-shell`).
actionlint \
  -shellcheck= \
  -pyflakes= \
  -config-file "$config" \
  "${workflows[@]}"

printf 'WORKFLOW-VALIDATION count=%d validator=actionlint config=%s status=pass\n' \
  "${#workflows[@]}" "$config"
