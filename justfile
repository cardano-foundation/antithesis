
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
