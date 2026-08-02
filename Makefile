SHELL := /bin/bash
ROOT_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
ENV_FILE ?= $(ROOT_DIR)/.env.node
COMPOSE := docker compose --project-directory $(ROOT_DIR) -f $(ROOT_DIR)/docker-compose.yml --env-file $(ENV_FILE)

.PHONY: validate up down ps logs identity smoke-test reset

validate:
	@test -f "$(ENV_FILE)" || (echo "Missing $(ENV_FILE); generate it with dark-deployer." && exit 1)
	@$(COMPOSE) config --quiet

up: validate
	@$(COMPOSE) up -d

down: validate
	@$(COMPOSE) down

ps: validate
	@$(COMPOSE) ps

logs: validate
	@$(COMPOSE) logs -f --tail=200

identity: validate
	@$(COMPOSE) exec -T ipfs ipfs id -f='Kubo: <id>\n'
	@$(COMPOSE) exec -T cluster ipfs-cluster-ctl id

smoke-test: validate
	@$(ROOT_DIR)/scripts/smoke-test.sh

reset: validate
	@echo "Refusing to delete persistent storage automatically."
	@echo "Use 'docker compose ... down -v' only after backing up and confirming the exact node."
	@exit 1
