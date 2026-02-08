#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_ARGS=(--project-directory "${ROOT_DIR}" -f "${ROOT_DIR}/docker-compose.yml")

if [[ ! -f "${ROOT_DIR}/.env" ]]; then
  echo "Missing ${ROOT_DIR}/.env. Run ./scripts/bootstrap.sh first."
  exit 1
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

pinned_count() {
  local cid="$1"
  local count=0
  local node
  for node in ipfs0 ipfs1 ipfs2; do
    if compose exec -T "${node}" ipfs --timeout=10s pin ls --type=recursive "${cid}" >/dev/null 2>&1; then
      count=$((count + 1))
    fi
  done
  echo "${count}"
}

wait_replication() {
  local cid="$1"
  local min_count="$2"
  local timeout="${3:-120}"
  local elapsed=0

  while true; do
    local current
    current="$(pinned_count "${cid}")"
    if [[ "${current}" -ge "${min_count}" ]]; then
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
    if [[ "${elapsed}" -ge "${timeout}" ]]; then
      echo "Replication timeout for CID ${cid}, current pinned=${current}"
      return 1
    fi
  done
}

wait_ready ipfs0 "ipfs id"
wait_ready ipfs1 "ipfs id"
wait_ready ipfs2 "ipfs id"
wait_ready cluster0 "ipfs-cluster-ctl id"
wait_ready cluster1 "ipfs-cluster-ctl id"
wait_ready cluster2 "ipfs-cluster-ctl id"

PAYLOAD="dark-ipfs-smoke-$(date -u +%Y%m%dT%H%M%SZ)-$RANDOM"
CID=""
for node in ipfs0 ipfs1 ipfs2; do
  NODE_CID="$(printf '%s' "${PAYLOAD}" | compose exec -T "${node}" sh -lc "ipfs add -q --cid-version=1 --pin=false -")"
  NODE_CID="$(echo "${NODE_CID}" | tr -d '\r\n')"
  if [[ -z "${CID}" ]]; then
    CID="${NODE_CID}"
  elif [[ "${CID}" != "${NODE_CID}" ]]; then
    echo "CID mismatch across nodes (${CID} vs ${NODE_CID})"
    exit 1
  fi
done
MIN_REPLICATION="${CLUSTER_REPLICATION_MIN:-2}"

if [[ -z "${CID}" ]]; then
  echo "Failed to produce CID."
  exit 1
fi

compose exec -T cluster0 ipfs-cluster-ctl pin add \
  --replication-min 2 \
  --replication-max 3 \
  --no-status \
  "${CID}" >/dev/null

wait_replication "${CID}" "${MIN_REPLICATION}"

for node in ipfs0 ipfs1 ipfs2; do
  CONTENT="$(compose exec -T "${node}" ipfs --timeout=15s cat "/ipfs/${CID}" | tr -d '\r\n')"
  if [[ "${CONTENT}" != "${PAYLOAD}" ]]; then
    echo "Content mismatch on ${node}"
    exit 1
  fi
done

compose restart ipfs1 >/dev/null
wait_ready ipfs1 "ipfs id"

CONTENT_AFTER="$(compose exec -T ipfs1 ipfs --timeout=15s cat "/ipfs/${CID}" | tr -d '\r\n')"
if [[ "${CONTENT_AFTER}" != "${PAYLOAD}" ]]; then
  echo "Content mismatch on ipfs1 after restart"
  exit 1
fi

echo "Smoke test passed."
echo "CID=${CID}"
