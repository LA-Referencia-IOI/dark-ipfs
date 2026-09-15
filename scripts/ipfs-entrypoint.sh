#!/bin/sh
set -eu

export IPFS_PATH="${IPFS_PATH:-/data/ipfs}"
export LIBP2P_FORCE_PNET=1
NODE_NAME="${NODE_NAME:-storage-node}"
BOOTSTRAP_ENDPOINTS="${IPFS_BOOTSTRAP_ENDPOINTS:-${IPFS_BOOTSTRAP_API_MULTIADDRESSES:-${IPFS_BOOTSTRAP_MULTIADDRESSES:-}}}"
BOOTSTRAP_P2P_PORT="${IPFS_BOOTSTRAP_P2P_PORT:-4001}"

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
# Keep the profile as a convenience on releases that provide it, but declare
# every relevant field below: development builds carrying the Bitswap startup
# fix may not include the profile.
ipfs config profile apply autoconf-off >/dev/null 2>&1 || \
  log "autoconf-off profile unavailable; applying explicit private-swarm settings"
ipfs config --json AutoConf.Enabled false
ipfs config --json DNS.Resolvers null
ipfs config --json Routing.DelegatedRouters null
ipfs config --json Ipns.DelegatedPublishers null
ipfs config Routing.Type dht
ipfs config --json AutoTLS.Enabled false
ipfs config --json Swarm.Transports.Network.Websocket false
ipfs config Addresses.API /ip4/0.0.0.0/tcp/5001
ipfs config Addresses.Gateway /ip4/127.0.0.1/tcp/8080
if [ -n "${IPFS_ANNOUNCE_MULTIADDRESSES:-}" ]; then
  # The renderer provides a JSON array so a node can announce both its site
  # LAN and its inter-site VPN address.  Kubo validates multiaddrs itself.
  ipfs config --json Addresses.AppendAnnounce "${IPFS_ANNOUNCE_MULTIADDRESSES}"
elif [ -n "${IPFS_ANNOUNCE_MULTIADDRESS:-}" ]; then
  # Compatibility with bundles rendered before the multisite contract.
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
  for endpoint in ${BOOTSTRAP_ENDPOINTS}; do
    api_address="${endpoint%@*}"
    endpoint_port="${endpoint##*@}"
    [ "${endpoint_port}" = "${endpoint}" ] && endpoint_port="${BOOTSTRAP_P2P_PORT}"
    case "${api_address}" in
      /ip4/*/tcp/*)
        host_address="$(printf '%s\n' "${api_address}" | sed -n 's#^/ip4/\([^/]*\)/tcp/.*#\1#p')"
        peer_id="$(ipfs --api "${api_address}" id -f='<id>' 2>/dev/null || true)"
        if [ -n "${host_address}" ] && [ -n "${peer_id}" ]; then
          address="/ip4/${host_address}/tcp/${endpoint_port}/p2p/${peer_id}"
          ipfs bootstrap add "${address}" >/dev/null || true
          log "configured bootstrap ${address}"
          found=1
        fi
        ;;
      *)
        addresses="$(ipfs --api "${api_address}" id -f='<addrs>' 2>/dev/null || true)"
        for address in ${addresses}; do
          ipfs bootstrap add "${address}" >/dev/null || true
          log "configured bootstrap ${address}"
          found=1
        done
        ;;
    esac
  done
  return "$((1 - found))"
}

if [ -n "${BOOTSTRAP_ENDPOINTS}" ]; then
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
