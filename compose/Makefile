SHELL:=/bin/bash

.SILENT: build build-image build-config push push-image push-config up down query validate

description:="${testnet} run"
duration:=1
recipients:=antithesis@cardanofoundation.org
registry:=
testnet:=
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
	@echo "    make build testnet=example_10.2.1 registry=us-central1-docker.pkg.dev/molten-verve-216720/cardano-repository/"
	@echo "    make push testnet=example_10.2.1 registry=us-central1-docker.pkg.dev/molten-verve-216720/cardano-repository/"
	@echo "    make anti testnet=example_10.2.1 password='password1234'"
	@echo

build: TESTNET build-image build-config build-sidecar build-tracer ## Build cardano-node, config, sidecar, and tracer images

build-image: TESTNET ## Build cardano-node container image
	ln -snf testnets/${testnet}/testnet.yaml .testnet.yaml ; cd testnets/${testnet} ; docker compose build

build-config: TESTNET ## Build config container image
	docker build --build-arg REGISTRY="${registry}" --build-arg "TESTNET=${testnet}" -f config/Dockerfile -t ${registry}${testnet}_config:latest testnets/${testnet}

build-sidecar: TESTNET ## Build sidecar container image
	docker build -f sidecar/Dockerfile -t ${registry}${testnet}_sidecar:latest sidecar/

build-tracer: TESTNET ## Build tracer container image
	docker build -f tracer/Dockerfile -t ${registry}${testnet}_tracer:latest tracer/

push: TESTNET push-image push-config push-sidecar ## Push cardano-node, config and sidecar container image

push-image: TESTNET ## Push cardano-node container image
	docker push ${registry}${testnet}:latest

push-config: TESTNET ## Push config container image
	docker push ${registry}${testnet}_config:latest

push-sidecar: TESTNET ## Push sidecar container image
	docker push ${registry}${testnet}_sidecar:latest

up: TESTNET ## Start Run local Docker Compose
	cd testnets/${testnet} ; docker compose up --detach

down: TESTNET ## Stop local Docker Compose
	cd testnets/${testnet} ; docker compose down --volumes

query: TESTNET ## Query tip of all pools
	pools="$$(awk '/poolCount: /{ print $$2 }' testnets/${testnet}/testnet.yaml)" ; \
	for i in $$(seq 1 $${pools}) ; do docker exec -ti p$${i} timeout 0.05 cardano-cli ping --magic 42 --host 127.0.0.1 --port 3001 --tip --quiet -c1; done ; true

validate: TESTNET ## Check for consensus among all pools
	docker exec -ti s1 /opt/antithesis/test/v1/convergence/eventually_converged.sh

anti: TESTNET ## Run Antithesis job
	curl --fail -u "${username}:${password}" -X POST ${url} -H "Content-Type: application/json" -d "$$(jq -n \
	--arg description   '${description}' \
	--arg duration      '${duration}' \
	--arg config_image  '${testnet}_config:latest' \
	--arg images        '${testnet}:latest;${testnet}_sidecar:latest' \
	--arg recipients    '${recipients}' \
	'{params: {"antithesis.description": $$description,"custom.duration": $$duration,"antithesis.config_image": $$config_image,"antithesis.images": $$images,"antithesis.report.recipients": $$recipients}}')"

TESTNET: ;
	@if [ -z "${testnet}" ]; then echo "* Please define the testnet argument:"; echo "testnet=example_10.2.1"; echo; exit 1; else export "testnet=${testnet}"; fi
