ARG CARDANO_CLI_VERSION="10.8.0.0"
# Blink Labs images are built from source on Debian Bookworm
FROM ghcr.io/blinklabs-io/cardano-cli:${CARDANO_CLI_VERSION} AS cardano-cli

FROM docker.io/debian:stable-slim AS main

# Set time zone
ENV TZ="UTC"
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo ${TZ} > /etc/timezone

# Install packages required in main stage
RUN apt update && \
    apt install -y --no-install-recommends \
        dnsutils \
        iproute2 \
        iputils-ping \
        jq \
        less \
        lsof \
        netbase \
        netcat-openbsd \
        openssl \
        procps \
        tcpdump \
        telnet \
        vim

# Copy binaries from image
COPY --from=cardano-cli --chown=root:root /usr/local/bin/cardano-cli /usr/local/bin/cardano-cli
# Copy libsecp256k1 (also debian:bookwork-slim AKA stable-slim)
COPY --from=cardano-cli --chown=root:root /usr/local/lib/ /usr/lib/

# Create cardano group and user
RUN groupadd --gid 10000 cardano && \
    useradd --comment 'cardano' --create-home --gid 10000 --password '!' --shell '/bin/bash' --uid 10000 cardano

# Create Antithesis directory
RUN install --directory --owner=cardano --group=cardano --mode=0750 /opt/antithesis/test/v1

# Copy Antithesis scripts
COPY composer /opt/antithesis/test/v1/
RUN chmod 0755 /opt/antithesis/test/v1/*/*

# Copy sidecar.sh
COPY sidecar.sh /
RUN chmod 0755 /sidecar.sh

USER cardano
#STOPSIGNAL SIGINT

CMD ["/sidecar.sh"]
