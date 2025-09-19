# Blink Labs images are built from source on Debian Bookworm
FROM ghcr.io/blinklabs-io/cardano-node:latest AS cardano-node

USER root
# Install packages required in build stage

RUN apt update && \
    apt install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        tar \
        tree \
        python3 \
        python3-pip \
        jq

# Install uv (fast Python package manager)
RUN python3 -m pip install --break-system-packages uv
# Create cardano-node source directory
RUN install --directory --owner=root --group=root --mode=0755 /usr/local/src/cardano-node

# Clone testnet-generation-tool.git repository
WORKDIR /usr/local/src
RUN git clone --branch main https://github.com/cardano-foundation/testnet-generation-tool.git

# Download testnet-generation-tool dependencies
WORKDIR /usr/local/src/testnet-generation-tool
# dockerfile
RUN uv sync && mkdir -p cardano-node && ln -sf /usr/local/bin ./cardano-node/bin

COPY configurator.sh /
RUN chmod 0755 /configurator.sh

ENTRYPOINT ["/configurator.sh"]
