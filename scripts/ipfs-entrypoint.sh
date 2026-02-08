#!/bin/sh
set -eu

export IPFS_PATH="${IPFS_PATH:-/data/ipfs}"
NODE_NAME="${NODE_NAME:-ipfs}"
BOOTSTRAP_NODE="${BOOTSTRAP_NODE:-}"

log() {
  printf '[%s] %s\n' "${NODE_NAME}" "$1"
}

if [ ! -f "${IPFS_PATH}/config" ]; then
  log "initializing repo"
  ipfs init --profile=server >/dev/null
  ipfs config Addresses.API /ip4/0.0.0.0/tcp/5001
  ipfs config Addresses.Gateway /ip4/0.0.0.0/tcp/8080
  ipfs config --json Addresses.AppendAnnounce "[\"/dns4/${NODE_NAME}/tcp/4001\"]"
  ipfs config --json Swarm.AddrFilters "[]"
  ipfs bootstrap rm --all >/dev/null || true
fi

if [ -n "${BOOTSTRAP_NODE}" ] && [ ! -f "${IPFS_PATH}/.bootstrap-configured" ]; then
  log "resolving bootstrap id from ${BOOTSTRAP_NODE}"
  BOOTSTRAP_ID=""
  while [ -z "${BOOTSTRAP_ID}" ]; do
    BOOTSTRAP_ID="$(ipfs --api "/dns4/${BOOTSTRAP_NODE}/tcp/5001" id -f='<id>' 2>/dev/null || true)"
    [ -n "${BOOTSTRAP_ID}" ] || sleep 2
  done
  BOOTSTRAP_ADDR="/dns4/${BOOTSTRAP_NODE}/tcp/4001/p2p/${BOOTSTRAP_ID}"
  log "adding bootstrap ${BOOTSTRAP_ADDR}"
  ipfs bootstrap add "${BOOTSTRAP_ADDR}" >/dev/null || true
  touch "${IPFS_PATH}/.bootstrap-configured"
fi

if [ -n "${BOOTSTRAP_NODE}" ]; then
  BOOTSTRAP_ADDR="$(ipfs bootstrap list | head -n1 || true)"
  ipfs daemon --migrate=true --agent-version-suffix=dark-ipfs-test &
  DAEMON_PID=$!

  for _ in $(seq 1 30); do
    if ipfs --api /ip4/127.0.0.1/tcp/5001 id >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  if [ -n "${BOOTSTRAP_ADDR}" ]; then
    for _ in $(seq 1 30); do
      if ipfs --api /ip4/127.0.0.1/tcp/5001 swarm connect "${BOOTSTRAP_ADDR}" >/dev/null 2>&1; then
        log "connected to bootstrap ${BOOTSTRAP_ADDR}"
        break
      fi
      sleep 2
    done
  fi

  wait "${DAEMON_PID}"
else
  exec ipfs daemon --migrate=true --agent-version-suffix=dark-ipfs-test
fi
