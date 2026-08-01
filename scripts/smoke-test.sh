#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-${ROOT_DIR}/.env.node}"
COMPOSE=(docker compose --project-directory "${ROOT_DIR}" -f "${ROOT_DIR}/docker-compose.yml" --env-file "${ENV_FILE}")

[[ -f "${ENV_FILE}" ]] || { echo "Missing ${ENV_FILE}"; exit 1; }

"${COMPOSE[@]}" exec -T ipfs ipfs id >/dev/null
"${COMPOSE[@]}" exec -T cluster ipfs-cluster-ctl id >/dev/null

payload="dark-ipfs-smoke-$(date -u +%Y%m%dT%H%M%SZ)-${RANDOM}"
cid="$(printf '%s' "${payload}" | "${COMPOSE[@]}" exec -T ipfs \
  ipfs --api /dns4/cluster/tcp/9095 add -q --cid-version=1 --pin=true - | tr -d '\r\n')"
[[ -n "${cid}" ]] || { echo "Cluster Proxy did not return a CID"; exit 1; }

for _ in $(seq 1 60); do
  if "${COMPOSE[@]}" exec -T cluster ipfs-cluster-ctl status "${cid}" 2>/dev/null | grep -qi pinned; then
    content="$("${COMPOSE[@]}" exec -T ipfs ipfs cat "${cid}" | tr -d '\r\n')"
    [[ "${content}" == "${payload}" ]] || { echo "Content mismatch"; exit 1; }
    echo "Node smoke test passed: ${cid}"
    exit 0
  fi
  sleep 2
done

echo "Pin did not reach this node before timeout: ${cid}"
exit 1
