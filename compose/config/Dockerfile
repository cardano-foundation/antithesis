FROM docker.io/debian:stable-slim AS build

ARG TESTNET="${TESTNET:-}"
ARG REGISTRY="${REGISTRY:-}"

# Set time zone
ENV TZ="UTC"
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo ${TZ} > /etc/timezone

ADD docker-compose.yaml /docker-compose.yaml

RUN sed -i "s@\${registry}@${REGISTRY}@g" /docker-compose.yaml
RUN sed -i "s@\${testnet}@${TESTNET}@g" /docker-compose.yaml
