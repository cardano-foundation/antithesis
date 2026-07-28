#!/usr/bin/env bash
# Mechanical gate for amaru fatal-log ingestion and scoring (#193).
# The tracer-sidecar test suite is the RED -> GREEN harness for the ingestion
# path and property; compose validation protects the deployment wiring.
set -euo pipefail

git diff --check

# tracer-sidecar property tests (hspec + golden). Prefer the hermetic Nix build
# and then execute the produced test binary from the component directory, which
# the golden test uses as its working directory. Fall back to cabal otherwise.
if command -v nix >/dev/null 2>&1 && [ -f components/tracer-sidecar/flake.nix ]; then
  (
    cd components/tracer-sidecar
    test_out=$(nix build --quiet --no-link --print-out-paths '.#tracer-sidecar-tests')
    "$test_out/bin/test"
  )
else
  ( cd components/tracer-sidecar && cabal test --test-show-details=streaming )
fi

# The cardano_amaru deployment must remain valid as log routing evolves.
INTERNAL_NETWORK=false docker compose \
  -f testnets/cardano_amaru/docker-compose.yaml config >/dev/null

echo "gate: OK"
