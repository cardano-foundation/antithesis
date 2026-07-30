# Testnets

## Available commands

```bash
just
```

```text
Available recipes:
    attack testnet='cardano_node_master'            # attack the network with adversarial chain sync clients
    check-convergence testnet='cardano_node_master' # check convergence of nodes in a testnet
    default                                         # just this help message
    down testnet='cardano_node_master'              # stop a testnet
    exec container testnet='cardano_node_master'    # exec into a container
    logs container testnet='cardano_node_master'    # view logs of a container
    ps testnet='cardano_node_master'                # list containers in a testnet
    restart testnet='cardano_node_master'           # restart a testnet
    up testnet='cardano_node_master'                # start a testnet
```

## Running locally

Run the testnet locally before submitting to Antithesis to verify containers start and the chain converges:

```bash
# Start
just up

# Verify all containers are running
just ps

# Watch chain progress
just logs tracer-sidecar

# Stop and clean up volumes
just down
```

The `justfile` wraps `docker compose` commands. All images must be available locally (built) or published to `ghcr.io`.

## Available testnets

- [cardano_node_master](cardano-node-master.md): Mixed-version testnet with 5 block producers and 4 relays, including Dingo 0.68.0, plus tracer observability, Asteria Plutus workload pressure, and tx-generator ADA-transfer pressure
