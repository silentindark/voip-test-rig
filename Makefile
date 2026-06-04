# voip-test-rig — local lifecycle helpers.
# Run `make` (or `make help`) to list targets.

# Load .env if present (for `make agent`, and to mirror compose's own .env read).
ifneq (,$(wildcard .env))
include .env
export
endif

SF_IOTCORE_HOST ?= mqtt.dev.sipfront.net

.DEFAULT_GOAL := help
.PHONY: help certs regen-certs build run up stop down logs ps restart agent clean

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n",$$1,$$2}'

certs/out/server.crt:
	bash certs/gen-certs.sh

certs: certs/out/server.crt ## Generate the CA + server cert (only if missing)

regen-certs: ## Force-regenerate the CA + server cert (new CA -> browser re-accept)
	rm -rf certs/out
	bash certs/gen-certs.sh

build: certs ## Build all rig images
	docker compose build

run: certs ## Generate certs, build, start the rig, and wait until it's ready
	docker compose up -d --build
	bash scripts/wait-for-rig.sh
	@echo "Rig is up. Web client: https://localhost:8081/  (trust certs/out/ca.crt)"

up: run ## Alias for `run`

stop: ## Stop and remove the rig containers, networks and volumes
	docker compose down -v

down: stop ## Alias for `stop`, plus remove any local Sipfront agents
	-docker rm -f $$(docker ps -aq --filter 'name=sf-agent-') 2>/dev/null || true

restart: down run ## Recreate the rig from scratch

logs: ## Follow logs from all rig services
	docker compose logs -f

ps: ## Show rig container status
	docker compose ps

AGENTS ?= 2
agent: ## Launch AGENTS Sipfront agents on the external net (needs SF_POOL_ID/SECRET in .env)
	bash scripts/launch-agents.sh $(AGENTS)
	@echo "Logs: docker logs -f sf-agent-1"

clean: down ## Stop everything and delete generated certs
	rm -rf certs/out
