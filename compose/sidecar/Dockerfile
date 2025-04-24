FROM docker.io/debian:stable-slim AS build

ARG CARDANO_CLI_VERSION="10.5.0.0"

# Set time zone
ENV TZ="UTC"
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo ${TZ} > /etc/timezone

# Install packages required in build stage
RUN apt update && \
    apt install -y --no-install-recommends \
        ca-certificates \
        curl

# Create cardano-cli source directory
RUN install --directory --owner=root --group=root --mode=0755 /usr/local/src/cardano-cli

# Download cardano-cli archive
RUN curl --proto '=https' --tlsv1.2 \
        --location https://github.com/IntersectMBO/cardano-cli/releases/download/cardano-cli-${CARDANO_CLI_VERSION}/cardano-cli-${CARDANO_CLI_VERSION}-x86_64-linux.tar.gz \
        --output /usr/local/src/cardano-cli/cardano-cli-${CARDANO_CLI_VERSION}-x86_64-linux.tar.gz

# Download cardano-cli checksum
RUN curl --proto '=https' --tlsv1.2 \
        --location https://github.com/IntersectMBO/cardano-cli/releases/download/cardano-cli-${CARDANO_CLI_VERSION}/cardano-cli-${CARDANO_CLI_VERSION}-sha256sums.txt \
        --output /usr/local/src/cardano-cli/cardano-cli-${CARDANO_CLI_VERSION}-sha256sums.txt

# Verify cardano-cli checksum
WORKDIR /usr/local/src/cardano-cli
RUN sha256sum --ignore-missing --check cardano-cli-${CARDANO_CLI_VERSION}-sha256sums.txt

# Unarchive cardano-cli tarball
RUN tar --extract --gzip --file=/usr/local/src/cardano-cli/cardano-cli-${CARDANO_CLI_VERSION}-x86_64-linux.tar.gz --directory=/usr/local/src/cardano-cli

# Make cardano-cli executable
RUN chmod 0755 /usr/local/src/cardano-cli/cardano-cli-x86_64-linux

# Create cardano-cli symlink
RUN ln -s /usr/local/src/cardano-cli/cardano-cli-x86_64-linux /usr/local/bin/cardano-cli

#---------------------------------------------------------------------

FROM docker.io/debian:stable-slim AS main

# Set time zone
ENV TZ="UTC"
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo ${TZ} > /etc/timezone

# Install packages required in main stage
RUN apt update && \
    apt install -y --no-install-recommends \
        curl \
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

# Copy binaries from build stage
COPY --from=build --chown=root:root /usr/local/bin/cardano-cli /usr/local/bin/cardano-cli

# Create cardano group and user
RUN groupadd --gid 10000 cardano && \
    useradd --comment 'cardano' --create-home --gid 10000 --password '!' --shell '/bin/bash' --uid 10000 cardano

# Create Antithesis directory
RUN install --directory --owner=cardano --group=cardano --mode=0750 /opt/antithesis/test/v1/convergence

# Copy Antithesis scripts
COPY composer/convergence/eventually_converged.sh /opt/antithesis/test/v1/convergence
COPY composer/convergence/serial_driver_sleep.sh /opt/antithesis/test/v1/convergence
RUN chmod 0755 /opt/antithesis/test/v1/*/*

# Copy sidecar.sh
COPY sidecar.sh /
RUN chmod 0755 /sidecar.sh

USER cardano
#STOPSIGNAL SIGINT

CMD ["/sidecar.sh"]
