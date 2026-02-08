#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_ARGS=(--project-directory "${ROOT_DIR}" -f "${ROOT_DIR}/docker-compose.yml")

if [[ ! -f "${ROOT_DIR}/.env" ]]; then
  cp "${ROOT_DIR}/.env.example" "${ROOT_DIR}/.env"
  echo "Created ${ROOT_DIR}/.env from .env.example"
fi

COMPOSE_ARGS+=(--env-file "${ROOT_DIR}/.env")

compose() {
  docker compose "${COMPOSE_ARGS[@]}" "$@"
}

wait_ready() {
  local service="$1"
  local cmd="$2"
  local timeout="${3:-120}"
  local elapsed=0

  while ! compose exec -T "${service}" sh -lc "${cmd}" >/dev/null 2>&1; do
    sleep 2
    elapsed=$((elapsed + 2))
    if [[ "${elapsed}" -ge "${timeout}" ]]; then
      echo "Timed out waiting for ${service}"
      return 1
    fi
  done
}

compose up -d

wait_ready ipfs0 "ipfs id"
wait_ready ipfs1 "ipfs id"
wait_ready ipfs2 "ipfs id"
wait_ready cluster0 "ipfs-cluster-ctl id"
wait_ready cluster1 "ipfs-cluster-ctl id"
wait_ready cluster2 "ipfs-cluster-ctl id"

echo "dark-ipfs cluster is ready."
