FROM ghcr.io/blinklabs-io/haskell:9.6.6-3.12.1.0-1 AS build

ARG JOBS=8

# Set time zone
ENV TZ="UTC"
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo ${TZ} > /etc/timezone

# Update path environment variables
ENV LD_LIBRARY_PATH="/usr/local/lib:$LD_LIBRARY_PATH" \
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH"

# Clone cardano-node.git repository
WORKDIR /usr/local/src
COPY . .
RUN --mount=type=cache,target=/root/.local/state/cabal/store \
    --mount=type=cache,target=/root/.cache/cabal \
    --mount=type=cache,target=./dist-newstyle \
    cabal update && \
    cabal build all && \
    cp -p dist-newstyle/build/$(uname -m)-linux/ghc-${GHC_VERSION}/adversary-0.1.0.0/x/adversary/build/adversary/adversary /usr/local/bin/

#---------------------------------------------------------------------

FROM docker.io/debian:stable-slim AS main

# Set time zone
ENV TZ="UTC"
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo ${TZ} > /etc/timezone

# lmdb library
RUN apt update && apt install -y --no-install-recommends liblmdb-dev

# Copy libsodium library
COPY --from=build --chown=root:root /usr/local/lib/libsodium.so /usr/local/lib
RUN ln -snf /usr/local/lib/libsodium.so /usr/local/lib/libsodium.so.23 && \
    ln -snf /usr/local/lib/libsodium.so /usr/local/lib/libsodium.so.23.3.0
RUN ldconfig

# Copy secp256k1 library
COPY --from=build --chown=root:root /usr/local/lib/libsecp256k1.so /usr/local/lib
RUN ln -snf /usr/local/lib/libsecp256k1.so /usr/local/lib/libsecp256k1.so.1 && \
    ln -snf /usr/local/lib/libsecp256k1.so /usr/local/lib/libsecp256k1.so.1.0.1
RUN ldconfig

# Copy binaries from build stage
COPY --from=build --chown=root:root /usr/local/bin/adversary /usr/local/bin/adversary

# Create cardano group and user
RUN groupadd --gid 10000 cardano && \
    useradd --comment 'cardano' --create-home --gid 10000 --password '!' --shell '/bin/bash' --uid 10000 cardano

# Copy Antithesis scripts
COPY composer /opt/antithesis/test/v1/
RUN chmod 0755 /opt/antithesis/test/v1/*/*

COPY sleep.sh .
RUN chmod 0755 ./sleep.sh

ENTRYPOINT ["./sleep.sh"]
