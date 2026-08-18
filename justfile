
##### Justfile for managing Cardano testnets #####

set export

INTERNAL_NETWORK := 'true'

# just this help message
default:
    just --list

### Testnet Management Commands ###

# start a testnet
up testnet='cardano_node_master':
    #!/usr/bin/env bash
    docker compose --progress quiet \
        -f testnets/{{testnet}}/docker-compose.yaml up -d

# stop a testnet
down testnet='cardano_node_master':
    #!/usr/bin/env bash
    docker compose --progress quiet \
        -f testnets/{{testnet}}/docker-compose.yaml down \
        --volumes --remove-orphans

# restart a testnet
restart testnet='cardano_node_master':
    just down testnet={{ testnet }}
    just up testnet={{ testnet }}

# exec into a container
exec container testnet='cardano_node_master':
    #!/usr/bin/env bash
    docker compose \
        -f testnets/{{testnet}}/docker-compose.yaml exec -it {{ container }} bash

# view logs of a container
logs container testnet='cardano_node_master':
    #!/usr/bin/env bash
    docker compose \
        -f testnets/{{testnet}}/docker-compose.yaml logs -f {{ container }}

# list containers in a testnet
ps testnet='cardano_node_master':
    #!/usr/bin/env bash
    docker compose \
        -f testnets/{{testnet}}/docker-compose.yaml ps \
        --format "table {{{{.Name}}\t{{{{.Image}}\t{{{{.Status}}"

# view resource usage stats of a testnet
stats testnet='cardano_node_master':
    #!/usr/bin/env bash
    docker stats \
        $(docker compose -f testnets/{{testnet}}/docker-compose.yaml ps -q)

# check convergence of nodes in a testnet
check-convergence testnet='cardano_node_master':
    #!/usr/bin/env bash
    docker compose \
        -f testnets/{{testnet}}/docker-compose.yaml exec -T sidecar \
          eventually-converged

# attack the network with adversarial chain sync clients
attack testnet='cardano_node_master':
    #!/usr/bin/env bash
    docker compose \
        -f testnets/{{testnet}}/docker-compose.yaml exec -T sidecar \
          flaky-chain-sync

# smoke test: start testnet, verify nodes produce blocks, tear down
smoke-test testnet='cardano_node_master' timeout='120':
    ./scripts/smoke-test.sh {{ testnet }} {{ timeout }}

### Build and Format Commands ###

# format code
format:
    #!/usr/bin/env bash
    set -euo pipefail
    nixfmt *.nix

# check nix formatting without rewriting sources
format-check:
    #!/usr/bin/env bash
    set -euo pipefail
    nixfmt --check *.nix

### Verification Commands ###

# validate the Actions expression contexts of every tracked workflow
check-workflows:
    ./scripts/check-github-actions.sh

# shellcheck the maintained shell surface
check-shell:
    #!/usr/bin/env bash
    set -euo pipefail
    # `old-broken/` and `tools/` carry pre-existing diagnostics and are not
    # part of this surface; the census is printed so it cannot shrink unnoticed.
    mapfile -t sources < <(git ls-files 'scripts/*.sh' 'tests/*.sh' | sort -u)
    if [ "${#sources[@]}" -eq 0 ]; then
        echo 'SHELL-ANALYSIS-ERROR empty shell census' >&2
        exit 1
    fi
    printf 'shell-census %s\n' "${sources[@]}"
    shellcheck -x "${sources[@]}"
    printf 'SHELL-ANALYSIS count=%d status=pass\n' "${#sources[@]}"

# focused proof for the repository-wide workflow validation
test-workflow-validation:
    ./tests/test-workflow-validation.sh

# focused proof for the Daily Amaru controller
test-daily-amaru:
    ./tests/test-daily-amaru.sh

# complete local CI: no Docker, no network, no credentials
ci: check-workflows check-shell format-check test-workflow-validation test-daily-amaru