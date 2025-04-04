SHELL := /bin/bash

.SILENT: build build-image build-config push push-image push-config up down query anti

description="${testnet} run"
duration=60
recipients="antithesis@cardanofoundation.org"
registry=us-central1-docker.pkg.dev/molten-verve-216720/cardano-repository
testnet=
url=https://cardano.antithesis.com/api/v1/launch/basic_test
username=cardano

help:
	@echo "Arguments:"
	@printf "  \033[34m%-30s\033[0m %s\n" description "Antithesis job description (description="Example")"
	@printf "  \033[34m%-30s\033[0m %s\n" duration "Antithesis job duration in minutes (duration=120)"
	@printf "  \033[34m%-30s\033[0m %s\n" recipients "Antithesis report recipients (recipients=john@example.com,peter@example.org)"
	@printf "  \033[34m%-30s\033[0m %s\n" registry "Antithesis registry URL (registry=https://registry.example.com/tenant)"
	@printf "  \033[34m%-30s\033[0m %s\n" testnet "testnet directory name (testnet=example_10.2.1)"
	@printf "  \033[34m%-30s\033[0m %s\n" url "Antithesis API job URL (url=https://cardano.antithesis.com/api/v1/launch/cardano)"
	@printf "  \033[34m%-30s\033[0m %s\n" username "Antithesis username (username=cardano)"
	@echo
	@echo "Commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[34m%-30s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "Examples:"
	@echo
	@echo "Local run (execute in this order)"
	@echo "  make build testnet=example_10.2.1"
	@echo "  make up testnet=example_10.2.1"
	@echo "  make query testnet=example_10.2.1"
	@echo "  make down testnet=example_10.2.1"
	@echo
	@echo "Antithesis run (execute in this order)"
	@echo "  make build testnet=example_10.2.1"
	@echo "  make push testnet=example_10.2.1"
	@echo "  make anti testnet=example_10.2.1 password='password1234'"
	@echo

build: build-image build-config TESTNET ## Build cardano-node and config container image

build-image: TESTNET ## Build cardano-node container image
	ln -snf testnets/${testnet}/testnet.yaml testnet.yaml ; cd testnets/${testnet} ; docker compose build

build-config: TESTNET ## Build config container image
	docker build -f Dockerfile.config -t ${registry}/${testnet}_config:latest testnets/${testnet}

push: push-image push-config TESTNET ## Push cardano-node and config container image

push-image: TESTNET ## Push cardano-node container image
	docker push $$(awk '/image: /{ print $$2 }' testnets/${testnet}/docker-compose.yaml)

push-config: TESTNET ## Push config container image
	docker push ${registry}/${testnet}_config:latest

up: TESTNET ## Start Run local Docker Compose
	cd testnets/${testnet} ; docker compose up --detach

down: TESTNET ## Stop local Docker Compose
	cd testnets/${testnet} ; docker compose down --volumes

query: TESTNET ## Query local Docker Compose tip
	pools="$$(awk '/poolCount: /{ print $$2 }' testnets/${testnet}/testnet.yaml)" ; \
	for i in $$(seq 1 $${pools}) ; do docker exec -ti p$${i} timeout 0.05 cardano-cli ping --magic 42 --host 127.0.0.1 --port 3001 --tip --quiet -c1; done ; true

anti: TESTNET ## Run Antithesis job
	curl --fail -u "${username}:${password}" -X POST ${url} -H "Content-Type: application/json" -d "$$(jq -n \
	--arg description   '${description}' \
	--arg duration      '${duration}' \
	--arg config_image  '${testnet}_config:latest' \
	--arg images        '${testnet}:latest' \
	--arg recipients    '${recipients}' \
	'{params: {"antithesis.description": $$description,"antithesis.duration": $$duration,"antithesis.config_image": $$config_image,"antithesis.images": $$images,"antithesis.report.recipients": $$recipients}}')"

TESTNET: ;
	@if [ -z "${testnet}" ]; then echo "* Please define the testnet argument:"; echo "testnet=<name>"; echo; exit 1; fi
