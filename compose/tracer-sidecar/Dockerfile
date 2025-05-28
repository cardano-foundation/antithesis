FROM haskell:9.6 AS build

WORKDIR /opt/tracer-sidecar

RUN cabal update

# Add just the .cabal file to capture dependencies
COPY ./tracer-sidecar.cabal /opt/tracer-sidecar/tracer-sidecar.cabal

# Docker will cache this command as a layer, freeing us up to
# modify source code without re-installing dependencies
# (unless the .cabal file changes!)
RUN cabal build --only-dependencies -j4

# Add and Install Application Code
COPY . /opt/tracer-sidecar
RUN cabal install

FROM docker.io/debian:stable-slim AS main

COPY --from=build /root/.local/bin/tracer-sidecar /usr/local/bin/tracer-sidecar

CMD ["/usr/local/tracer-sidecar", "/opt/cardano-tracer"]
