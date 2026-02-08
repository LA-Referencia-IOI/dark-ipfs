SHELL := /bin/bash
ROOT_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
COMPOSE := docker compose --project-directory $(ROOT_DIR) -f $(ROOT_DIR)/docker-compose.yml

ifneq ("$(wildcard $(ROOT_DIR)/.env)","")
COMPOSE += --env-file $(ROOT_DIR)/.env
endif

.PHONY: init up down ps logs smoke-test reset

init:
	@if [ ! -f "$(ROOT_DIR)/.env" ]; then cp "$(ROOT_DIR)/.env.example" "$(ROOT_DIR)/.env"; fi
	@echo "Environment file ready: $(ROOT_DIR)/.env"

up: init
	@$(ROOT_DIR)/scripts/bootstrap.sh

down:
	@$(COMPOSE) down

ps:
	@$(COMPOSE) ps

logs:
	@$(COMPOSE) logs -f --tail=200

smoke-test:
	@$(ROOT_DIR)/scripts/smoke-test.sh

reset:
	@$(COMPOSE) down -v --remove-orphans
