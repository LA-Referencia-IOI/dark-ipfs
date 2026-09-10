#!/bin/sh
set -eu

CLUSTER_PATH="${CLUSTER_PATH:-/data/ipfs-cluster}"
export IPFS_CLUSTER_PATH="${CLUSTER_PATH}"
PEER_NAME="${CLUSTER_PEERNAME:-storage-node}"
BOOTSTRAP_HOSTS="${CLUSTER_BOOTSTRAP_HOSTS:-}"

log() {
  printf '[%s] %s\n' "${PEER_NAME}" "$1"
}

test -r "${CLUSTER_SECRET_FILE}" || {
  log "Cluster secret is not readable: ${CLUSTER_SECRET_FILE}"
  exit 1
}
CLUSTER_SECRET="$(tr -d '[:space:]' < "${CLUSTER_SECRET_FILE}")"
case "${CLUSTER_SECRET}" in
  *[!0-9a-fA-F]*|'')
    log "Cluster secret must contain exactly 64 hexadecimal characters"
    exit 1
    ;;
esac
if [ "${#CLUSTER_SECRET}" -ne 64 ]; then
  log "Cluster secret must contain exactly 64 hexadecimal characters"
  exit 1
fi
export CLUSTER_SECRET

if [ ! -f "${CLUSTER_PATH}/service.json" ]; then
  log "initializing persistent Cluster identity and CRDT state"
  ipfs-cluster-service init >/dev/null
fi

# `service.json` is persistent and environment variables are only consumed by
# the image during initialization. Keep the operational pin concurrency
# deterministic when an existing volume is reused.
PIN_CONCURRENCY="${CLUSTER_PINTRACKER_CONCURRENTPINS:-10}"
case "${PIN_CONCURRENCY}" in
  ''|*[!0-9]*) log "CLUSTER_PINTRACKER_CONCURRENTPINS must be numeric"; exit 1 ;;
esac
KUBO_ALIAS="${IPFS_DARK_NET_ALIAS:-ipfs}"
sed -E -i "s/(\"concurrent_pins\"[[:space:]]*:[[:space:]]*)[0-9]+/\1${PIN_CONCURRENCY}/" "${CLUSTER_PATH}/service.json"
# Kubo's freshly initialized config may use /ip4/127.0.0.1 rather than
# /dns4/...; normalize either form so Cluster never falls back to localhost.
sed -E -i "s#(\"node_multiaddress\"[[:space:]]*:[[:space:]]*\")[^\"]+/tcp/5001#\1/dns4/${KUBO_ALIAS}/tcp/5001#" "${CLUSTER_PATH}/service.json"
# Cluster initializes its HTTP listeners on loopback; replace those listener
# addresses so peers on the shared Docker/VPN network can reach REST, proxy,
# and pinning endpoints.
sed -E -i 's#/ip4/127\.0\.0\.1/tcp/(9094|9095|9096|9097)#/ip4/0.0.0.0/tcp/\1#g' "${CLUSTER_PATH}/service.json"
log "pin tracker concurrency=${PIN_CONCURRENCY}; kubo=/dns4/${IPFS_DARK_NET_ALIAS:-ipfs}/tcp/5001"

resolve_bootstraps() {
  addresses=""
  for host in ${BOOTSTRAP_HOSTS}; do
    protocol="ip4"
    case "${host}" in
      *[!0-9.]* ) protocol="dns4" ;;
    esac
    output="$(ipfs-cluster-ctl --host "/${protocol}/${host}/tcp/9094" --enc json id 2>/dev/null || true)"
    remote_id="$(
      printf '%s\n' "${output}" \
        | sed -n 's/^[[:space:]]*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        | sed -n '1p'
    )"
    if [ -n "${remote_id}" ]; then
      address="/${protocol}/${host}/tcp/9096/p2p/${remote_id}"
      if [ -n "${addresses}" ]; then
        addresses="${addresses},${address}"
      else
        addresses="${address}"
      fi
    fi
  done
  test -n "${addresses}" || return 1
  printf '%s' "${addresses}"
}

if [ -n "${BOOTSTRAP_HOSTS}" ]; then
  log "waiting for an existing Cluster peer over the VPN"
  BOOTSTRAP_ADDRESSES=""
  if [ "${CLUSTER_SEED:-false}" = "true" ]; then
    attempts=0
    until BOOTSTRAP_ADDRESSES="$(resolve_bootstraps)" || [ "${attempts}" -ge 5 ]; do
      attempts=$((attempts + 1))
      sleep 2
    done
  else
    until BOOTSTRAP_ADDRESSES="$(resolve_bootstraps)"; do
      sleep 2
    done
  fi
  if [ -n "${BOOTSTRAP_ADDRESSES}" ]; then
    log "joining the global cluster"
    exec ipfs-cluster-service daemon --bootstrap "${BOOTSTRAP_ADDRESSES}"
  fi
fi

log "starting the first peer for cluster ${CLUSTER_CRDT_CLUSTERNAME:-ipfs-cluster}"
exec ipfs-cluster-service daemon
