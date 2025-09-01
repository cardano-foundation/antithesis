SHELL:=/usr/bin/env bash

.SILENT: build build-image build-config push push-image push-config up down query validate

description:="${testnet} run"
duration:=1
recipients:=antithesis@cardanofoundation.org
registry:=ghcr.io/cardano-foundation/antithesis
testnet:=cardano_node_master
url:=https://cardano.antithesis.com/api/v1/launch/cardano
username:=cardano

# Required for builds on OSX ARM
export DOCKER_DEFAULT_PLATFORM?=linux/amd64

export registry

help:
	@echo
	@echo "Arguments:"
	@printf "  \033[34m%-30s\033[0m %s\n" registry "Container registry URL (Example: us-central1-docker.pkg.dev/molten-verve-216720/cardano-repository/)"
	@printf "  \033[34m%-30s\033[0m %s\n" testnet "Testnet directory name (Example: example_10.2.1)"
	@printf "  \033[34m%-30s\033[0m %s\n" description "Antithesis job description (Default: \"<testnet> run\")"
	@printf "  \033[34m%-30s\033[0m %s\n" duration "Antithesis job duration in hours (Default: 1)"
	@printf "  \033[34m%-30s\033[0m %s\n" recipients "Antithesis report recipients (Default: antithesis@cardanofoundation.org)"
	@printf "  \033[34m%-30s\033[0m %s\n" url "Antithesis API job URL (Default: https://cardano.antithesis.com/api/v1/launch/cardano)"
	@printf "  \033[34m%-30s\033[0m %s\n" username "Antithesis username (Default: cardano)"
	@printf "  \033[34m%-30s\033[0m %s\n" password "Antithesis password"
	@echo
	@echo "Commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[34m%-30s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "Examples:"
	@printf "  \033[34mLocal run (execute in this order)\033[0m\n"
	@echo "    make build testnet=example_10.2.1"
	@echo "    make up testnet=example_10.2.1"
	@echo "    make query testnet=example_10.2.1"
	@echo "    make validate testnet=example_10.2.1"
	@echo "    make down testnet=example_10.2.1"
	@echo
	@printf "  \033[34mAntithesis run (execute in this order)\033[0m\n"
	@echo "    make build testnet=example_10.2.1 "
	@echo "    make push testnet=example_10.2.1 "
	@echo "    make anti testnet=example_10.2.1 password='password1234'"
	@echo
	@printf "  \033[34mAntithesis debugging session\033[0m\n"
	@echo "    Grab the 'Moment' definition from a report, extract parameters session_id, input_hash, and vtime, then:"
	@echo "    make anti password='password1234' session_id=<some session_id> input_hash=<some hash> vtime=<decimal seconds>"
	@echo

build-shared:
	docker build \
	    --label "org.opencontainers.image.source=https://github.com/cardano-foundation/antithesis" \
		-f sidecar/Dockerfile \
		-t ${registry}/sidecar:latest sidecar
	docker build \
	    --label "org.opencontainers.image.source=https://github.com/cardano-foundation/antithesis" \
		-f tracer/Dockerfile.compiled \
		-t ${registry}/tracer:latest tracer
	docker build \
	    --label "org.opencontainers.image.source=https://github.com/cardano-foundation/antithesis" \
		-f tracer-sidecar/Dockerfile \
		-t ${registry}/tracer-sidecar:latest tracer-sidecar
	docker build \
	    --label "org.opencontainers.image.source=https://github.com/cardano-foundation/antithesis" \
		-f configurator/Dockerfile \
		-t ${registry}/configurator:latest configurator
	docker build \
	    --label "org.opencontainers.image.source=https://github.com/cardano-foundation/antithesis" \
		-f ../adversary/Dockerfile \
		-t ${registry}/adversary:latest ../adversary

push-shared:
	docker push ${registry}/sidecar:latest
	docker push ${registry}/tracer:latest
	docker push ${registry}/tracer-sidecar:latest
	docker push ${registry}/configurator:latest
	docker push ${registry}/adversary:latest

build-and-push-shared: build-shared
	$(MAKE) push-shared

build-config: TESTNET ## Build config container image
	docker build \
		--label "org.opencontainers.image.source=https://github.com/cardano-foundation/antithesis" \
		-f config/Dockerfile \
		-t ${registry}/config:latest testnets/${testnet}

publish-test-config-image: TESTNET build-config push-config ## Publish config container image

push: TESTNET push-config

push-config: TESTNET ## Push config container image
	docker push ${registry}/config:latest

up: TESTNET ## Start Run local Docker Compose
	export INTERNAL_NETWORK=true ; \
	cd testnets/${testnet} ; docker compose up --detach

down: TESTNET ## Stop local Docker Compose
	export INTERNAL_NETWORK=true ; \
	cd testnets/${testnet} ; docker compose down --volumes

query: TESTNET ## Query tip of all pools
	pools="$$(awk '/poolCount: /{ print $$2 }' testnets/${testnet}/testnet.yaml)" ; \
	for i in $$(seq 1 $${pools}) ; do docker exec -ti p$${i} timeout 0.05 cardano-cli ping --magic 42 --host 127.0.0.1 --port 3001 --tip --quiet -c1; done ; true

validate: TESTNET ## Check for consensus among all pools
	docker exec -ti sidecar /opt/antithesis/test/v1/convergence/eventually_converged.sh

anti: TESTNET ## Run Antithesis job
	curl --fail -u "${username}:${password}" -X POST ${url} -H "Content-Type: application/json" -d "$$(jq -n \
	--arg description   '${description}' \
	--arg duration      '${duration}' \
	--arg config_image  '${registry}/config:latest' \
	--arg images        'ghcr.io/intersectmbo/cardano-node:latest;${registry}/sidecar:latest;${registry}/tracer:latest;${registry}/tracer-sidecar:latest;${registry}/configurator:latest' \
	--arg recipients    '${recipients}' \
	'{params: {"antithesis.description": $$description,"custom.duration": $$duration,"antithesis.config_image": $$config_image \
		,"antithesis.images": $$images,"antithesis.report.recipients": $$recipients}}')"

anti-debug: ## Request debugger session
	curl --fail -u "${username}:${password}" \
       -X POST https://cardano.antithesis.com/api/v1/launch/debugging \
       bugging.vtime":"${vtime}", \
           "antithesis.report.recipients":"hal@cardanofoundation.org" \
       }}'

TESTNET: ;
	@if [ -z "${testnet}" ]; then echo "* Please define the testnet argument:"; echo "testnet=example_10.2.1"; echo; exit 1; else export "testnet=${testnet}"; fi
