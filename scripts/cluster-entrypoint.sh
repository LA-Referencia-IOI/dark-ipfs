#!/bin/sh
set -eu

CLUSTER_PATH="${CLUSTER_PATH:-/data/ipfs-cluster}"
PEER_NAME="${CLUSTER_PEERNAME:-cluster-peer}"
BOOTSTRAP_PEER_HOST="${BOOTSTRAP_PEER_HOST:-}"

log() {
  printf '[%s] %s\n' "${PEER_NAME}" "$1"
}

if [ ! -f "${CLUSTER_PATH}/service.json" ]; then
  log "initializing peer state"
  ipfs-cluster-service init >/dev/null
fi

resolve_bootstrap_id() {
  target_host="$1"
  output="$(ipfs-cluster-ctl --host "/dns4/${target_host}/tcp/9094" id --enc json 2>/dev/null || true)"
  id_from_json="$(printf '%s' "${output}" | tr -d '\n' | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  if [ -n "${id_from_json}" ]; then
    printf '%s' "${id_from_json}"
    return 0
  fi

  output="$(ipfs-cluster-ctl --host "/dns4/${target_host}/tcp/9094" id 2>/dev/null || true)"
  id_from_text="$(printf '%s' "${output}" | awk 'NF>0 {print $1; exit}' | tr -d '|')"
  if [ -n "${id_from_text}" ]; then
    printf '%s' "${id_from_text}"
    return 0
  fi

  return 1
}

if [ -n "${BOOTSTRAP_PEER_HOST}" ] && [ ! -f "${CLUSTER_PATH}/.bootstrapped" ]; then
  log "waiting bootstrap peer ${BOOTSTRAP_PEER_HOST}"
  BOOTSTRAP_ID=""
  while [ -z "${BOOTSTRAP_ID}" ]; do
    BOOTSTRAP_ID="$(resolve_bootstrap_id "${BOOTSTRAP_PEER_HOST}" || true)"
    [ -n "${BOOTSTRAP_ID}" ] || sleep 2
  done
  BOOTSTRAP_ADDR="/dns4/${BOOTSTRAP_PEER_HOST}/tcp/9096/p2p/${BOOTSTRAP_ID}"
  log "bootstrapping with ${BOOTSTRAP_ADDR}"
  touch "${CLUSTER_PATH}/.bootstrapped"
  exec ipfs-cluster-service daemon --bootstrap "${BOOTSTRAP_ADDR}"
fi

exec ipfs-cluster-service daemon
