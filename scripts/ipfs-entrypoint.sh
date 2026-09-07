#!/bin/sh
set -eu

export IPFS_PATH="${IPFS_PATH:-/data/ipfs}"
export LIBP2P_FORCE_PNET=1
NODE_NAME="${NODE_NAME:-storage-node}"
BOOTSTRAP_HOSTS="${IPFS_BOOTSTRAP_HOSTS:-}"

log() {
  printf '[%s] %s\n' "${NODE_NAME}" "$1"
}

if [ -n "${IPFS_SWARM_KEY_FILE:-}" ]; then
  test -r "${IPFS_SWARM_KEY_FILE}" || {
    log "swarm key is not readable: ${IPFS_SWARM_KEY_FILE}"
    exit 1
  }
  cp "${IPFS_SWARM_KEY_FILE}" "${IPFS_PATH}/swarm.key"
  chmod 600 "${IPFS_PATH}/swarm.key"
fi

if [ ! -f "${IPFS_PATH}/config" ]; then
  log "initializing persistent Kubo identity"
  ipfs init --profile=server >/dev/null
fi

# Private swarms must not inherit public-mainnet discovery endpoints. Kubo
# v0.41+ refuses to start with its default AutoConf URL when swarm.key is
# present. The official profile also clears delegated public routers,
# publishers and DNS resolvers, and disables AutoTLS for the private network.
ipfs config profile apply autoconf-off >/dev/null
ipfs config Routing.Type dht
ipfs config --json AutoTLS.Enabled false
ipfs config --json Swarm.Transports.Network.Websocket false
ipfs config Addresses.API /ip4/0.0.0.0/tcp/5001
ipfs config Addresses.Gateway /ip4/127.0.0.1/tcp/8080
if [ -n "${IPFS_ANNOUNCE_MULTIADDRESS:-}" ]; then
  ipfs config --json Addresses.AppendAnnounce "[\"${IPFS_ANNOUNCE_MULTIADDRESS}\"]"
else
  # An empty string is not a valid multiaddr and makes Kubo fail during node
  # construction. Keep the list empty for environments that do not announce.
  ipfs config --json Addresses.AppendAnnounce "[]"
fi
ipfs config --json Swarm.AddrFilters "[]"
ipfs bootstrap rm --all >/dev/null || true

resolve_bootstraps() {
  found=0
  for host in ${BOOTSTRAP_HOSTS}; do
    protocol="ip4"
    case "${host}" in
      *[!0-9.]* ) protocol="dns4" ;;
    esac
    remote_id="$(ipfs --api "/${protocol}/${host}/tcp/5001" id -f='<id>' 2>/dev/null || true)"
    if [ -n "${remote_id}" ]; then
      address="/${protocol}/${host}/tcp/4001/p2p/${remote_id}"
      ipfs bootstrap add "${address}" >/dev/null || true
      log "configured bootstrap ${address}"
      found=1
    fi
  done
  return "$((1 - found))"
}

if [ -n "${BOOTSTRAP_HOSTS}" ]; then
  log "waiting for an existing Kubo peer over the VPN"
  if [ "${CLUSTER_SEED:-false}" = "true" ]; then
    attempts=0
    until resolve_bootstraps || [ "${attempts}" -ge 5 ]; do
      attempts=$((attempts + 1))
      sleep 2
    done
    if [ -z "$(ipfs bootstrap list 2>/dev/null || true)" ]; then
      log "no existing peer found; seeding a new private swarm"
    fi
  else
    until resolve_bootstraps; do
      sleep 2
    done
  fi
fi

exec ipfs daemon --migrate=true --agent-version-suffix=dark-ipfs
