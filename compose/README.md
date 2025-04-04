# compose

## Index

- [Information](#information)
- [Installation](#installation)
- [Plan](#plan)
- [Build](#build)
- [Run](#run)
  - [Local](#local)
  - [Antithesis](#antithesis)
- [Troubleshoot](#troubleshoot)
- [Appendix](#appendix)

## Information

This document describes the process of setting up a Cardano testnet from scratch. `cardano-node` can be compiled from source or downloaded as pre-compiled binary. The testnet will run inside of **Docker Containers** and will be controlled by **Docker Compose**.

## Installation

Docker is the only requirement to build and run your own testnets. The following instructions are tested on Debian 12.

- Install dependencies via APT package manager

  ```
  sudo apt install --no-install-recommends \
      ca-certificates \
      curl \
      make
  ```

- Add Docker APT repository public key

  ```
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  ```

- Add Docker APT repository

  ```
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  ```

- Refresh APT cache

  ```
  sudo apt update
  ```

- Install Docker

  ```
  sudo apt install --no-install-recommends \
      docker-ce \
      docker-ce-cli \
      containerd.io \
      docker-buildx-plugin \
      docker-compose-plugin
  ```

- Add your user to the `docker` group

  ```
  sudo usermod --append --groups docker $(whoami)
  ```

- Pull and run the Docker test image

  ```
  docker run hello-world
  ```

You are now ready to build your own testnet container images from source or pre-compiled binary.

## Plan

- Clone the `antithesis.git` Git repository

  ```
  git clone git@github.com:cardano-foundation/antithesis.git
  ```

- Create a copy of the `example_10.2.1` folder to a directory with your own testnet name

  ```
  cd antithesis/
  cp -r example_10.2.1 <mytestnet>
  cd <mytestnet>/
  ```

- Edit the `README.md` file to describe your test case and the version used

  ```
  editor README.md
  ```

- Modify the `testnet.yaml` file and insert your configuration details

  ```
  editor testnet.yaml
  ```

- Modify the `docker-compose.yaml` file to reflect your testnet defined above

  ```
  editor docker-compose.yaml
  ```

> [!IMPORTANT]
> Please make sure:
>   - the number of pools match the `poolCount` defined in `testnet.yaml`
>   - the correct dockerfile is specified (`Dockerfile.compiled` or `Dockerfile.source`)
>   - the build arguments (`args`) are correct

## Build

- Change to the root directory of this Git repository

  ```
  cd ../
  ```

- Build the `cardano-node` and `config` container images

  ```
  make build testnet=example_10.2.1
  ```

> [!IMPORTANT]
> Any modifications to the `testnet.yaml` or `docker-compose.yaml` files require you to run the build command again.

## Run

### Local

- Start the testnet

  ```
  make up testnet=example_10.2.1
  ```

- Verify that all nodes of your testnet are running

  ```
  docker ps
  ```

- Query the tip of all nodes

  ```
  make query testnet=example_10.2.1
  ```

- Read the logs of container `p1`

  ```
  docker logs --follow p1
  ```

- Find errors in container `p1`

  ```
  docker logs p1 | grep -i error
  ```

- Enter the container `p1` as service user

  ```
  docker exec -ti p1 /bin/bash
  ```

- Enter the container `p1` as root

  ```
  docker exec --user root -ti p1 /bin/bash
  ```

- Stop the testnet

  ```
  make down testnet=example_10.2.1
  ```

### Antithesis

- Push the `cardano-node` and `config` container images

  ```
  make push testnet=example_10.2.1
  ```

- Trigger the default Antithesis job

  ```
  make anti testnet=example_10.2.1 password='password1234'
  ```

- Trigger a specific Antithesis job

  ```
  make anti testnet=example_10.2.1 password='password1234' url=https://cardano.antithesis.com/api/v1/launch/cardano
  ```

## Troubleshoot

- Query the start time in `byron-genesis.json` and `shelley-genesis.json`

  ```
  for i in {1..3} ; do docker exec -ti p${i} jq -er '.startTime' /opt/cardano-node/pools/${i}/configs/byron-genesis.json; done
  for i in {1..3} ; do docker exec -ti p${i} jq -er '.systemStart' /opt/cardano-node/pools/${i}/configs/shelley-genesis.json; done
  ```

- Query an option in `config.json`

  ```
  for i in {1..3} ; do docker exec -ti p${i} jq -er '.PeerSharing' /opt/cardano-node/pools/${i}/configs/config.json; done
  ```

> [!TIP]
> The commands above assume a testnet of 3 pools, increase the `{1..3}` if needed.

## Appendix

- [Antithesis Documentation](https://antithesis.com/docs/)
- [Docker Installation](https://docs.docker.com/engine/install/debian/)
