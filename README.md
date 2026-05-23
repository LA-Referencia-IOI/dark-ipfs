# dark-ipfs

A Docker-based local IPFS Cluster test environment for the dARK project. Provides a complete 3-node IPFS network with IPFS Cluster orchestration for testing distributed content pinning and metadata storage.

## Overview

This module spins up a self-contained IPFS Cluster suitable for local development and integration testing. It simulates a production-like distributed storage environment where content is automatically replicated across multiple nodes.

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         dark-ipfs-backbone                      │
│                                                                 │
│  ┌──────────┐      ┌──────────┐      ┌──────────┐              │
│  │  ipfs0   │◄────►│  ipfs1   │◄────►│  ipfs2   │   Kubo Nodes │
│  │ (primary)│      │          │      │          │              │
│  └────▲─────┘      └────▲─────┘      └────▲─────┘              │
│       │                 │                 │                    │
│  ┌────┴─────┐      ┌────┴─────┐      ┌────┴─────┐              │
│  │ cluster0 │◄────►│ cluster1 │◄────►│ cluster2 │  Cluster     │
│  │(primary) │      │          │      │          │  Peers       │
│  └──────────┘      └──────────┘      └──────────┘              │
└─────────────────────────────────────────────────────────────────┘
         │
         ├── dark-ipfs-store-node: ipfs0 + cluster0 + Store API
         ├── dark-ipfs-remote-node-1: ipfs1 + cluster1
         └── dark-ipfs-remote-node-2: ipfs2 + cluster2
         │
         ▼
    Host Endpoints:
    - IPFS API:     localhost:5001
    - IPFS Gateway: localhost:38080
    - Cluster API:  localhost:9094
    - Cluster Proxy:localhost:9095
```

### Topology Details

| Component | Description |
|-----------|-------------|
| `ipfs0`, `ipfs1`, `ipfs2` | [Kubo](https://github.com/ipfs/kubo) IPFS nodes forming the underlying storage layer |
| `cluster0`, `cluster1`, `cluster2` | [IPFS Cluster](https://ipfscluster.io/) peers managing automated pinning orchestration |

The network layout intentionally separates the Store API view from the full cluster:

- `dark-ipfs-store-node` contains only `ipfs0` and `cluster0`. `dark-store-api` joins this network and uses `http://ipfs0:5001`, `http://cluster0:9094`, and `http://cluster0:9095`.
- `dark-ipfs-backbone` connects all IPFS and Cluster peers so Cluster can replicate content.
- `dark-ipfs-remote-node-1` and `dark-ipfs-remote-node-2` simulate remote storage nodes from the Store API point of view.

**Startup Order:**
1. `ipfs0` starts first and becomes the bootstrap node
2. `ipfs1` and `ipfs2` start after `ipfs0` is healthy and connect to it
3. `cluster0` starts after `ipfs0` is healthy
4. `cluster1` and `cluster2` start after their respective IPFS nodes AND `cluster0` are healthy

### Replication Policy

| Setting | Default | Description |
|---------|---------|-------------|
| `CLUSTER_REPLICATION_MIN` | 2 | Minimum number of nodes that must pin content |
| `CLUSTER_REPLICATION_MAX` | 2 | Maximum number of nodes to replicate to |

Content pinned through the cluster is automatically replicated to at least 2 nodes, ensuring fault tolerance.

## Requirements

- **Docker** (20.10 or later recommended)
- **Docker Compose plugin** (v2)

## Quick Start

```bash
# Navigate to the module directory
cd /Users/lmatas/source/dark-deployer/components/blockchain/dark-ipfs

# Create environment file from template
cp .env.example .env

# Start the cluster (waits for all services to be healthy)
make up

# Run validation tests
make smoke-test
```

## Configuration

### Environment Variables

Edit `.env` to customize the cluster:

| Variable | Default | Description |
|----------|---------|-------------|
| `KUBO_IMAGE_TAG` | `v0.41.0` | Kubo Docker image tag |
| `IPFS_CLUSTER_IMAGE_TAG` | `v1.1.6` | IPFS Cluster Docker image tag |
| `CLUSTER_SECRET` | (generated) | 32-byte hex secret for cluster authentication |
| `CLUSTER_REPLICATION_MIN` | `2` | Minimum replication factor |
| `CLUSTER_REPLICATION_MAX` | `2` | Maximum replication factor |
| `IPFS0_API_PORT` | `5001` | Host port for IPFS API |
| `IPFS0_GATEWAY_BIND` | `127.0.0.1` | Host interface for the IPFS Gateway |
| `IPFS0_GATEWAY_PORT` | `38080` | Host port for IPFS Gateway |
| `IPFS0_SWARM_PORT` | `4001` | Host port for IPFS Swarm (P2P) |
| `CLUSTER_API_PORT` | `9094` | Host port for Cluster REST API |
| `CLUSTER_PROXY_PORT` | `9095` | Host port for Cluster IPFS Proxy |

### Generating a New Cluster Secret

For security, generate a unique secret for each environment:

```bash
# Generate a 32-byte hex secret
openssl rand -hex 32
```

Update `CLUSTER_SECRET` in `.env` with the generated value.

## Makefile Commands

| Command | Description |
|---------|-------------|
| `make init` | Create `.env` from `.env.example` if it doesn't exist |
| `make up` | Start all services and wait for them to be healthy |
| `make down` | Stop all services (preserves data volumes) |
| `make ps` | Show running containers and their status |
| `make logs` | Follow logs from all services (tail 200 lines) |
| `make smoke-test` | Run validation tests (pinning, replication, resilience) |
| `make reset` | Stop all services AND delete all data volumes |

## Host-Exposed Endpoints

Only `ipfs0` and `cluster0` expose ports to the host:

| Endpoint | URL | Description |
|----------|-----|-------------|
| IPFS API | `http://localhost:5001` | IPFS HTTP API for adding/getting content |
| IPFS Gateway | `http://localhost:38080` | HTTP gateway for fetching content by CID |
| Cluster REST API | `http://localhost:9094` | IPFS Cluster management API |
| Cluster IPFS Proxy | `http://localhost:9095` | IPFS API proxy with automatic pinning |

### Usage Examples

```bash
# Add content to IPFS (returns CID)
echo "Hello dARK" | curl -X POST -F "file=@-" "http://localhost:5001/api/v0/add?cid-version=1" | jq -r '.Hash'

# Pin content via Cluster (auto-replicates)
curl -X POST "http://localhost:9094/pins/bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi"

# Get content via Gateway
curl "http://localhost:38080/ipfs/bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi"

# Check cluster peers
curl "http://localhost:9094/peers" | jq
```

## Scripts

### `scripts/bootstrap.sh`
Orchestrates the startup sequence:
1. Ensures `.env` exists
2. Starts all containers with `docker compose up -d`
3. Waits for each IPFS node to respond to `ipfs id`
4. Waits for each cluster peer to respond to `ipfs-cluster-ctl id`

### `scripts/ipfs-entrypoint.sh`
Custom IPFS node initialization:
- Initializes IPFS repo with server profile on first run
- Configures API/Gateway to listen on all interfaces
- Resolves and connects to bootstrap node (for `ipfs1`, `ipfs2`)

### `scripts/cluster-entrypoint.sh`
Custom cluster peer initialization:
- Initializes cluster state on first run
- For secondary peers: resolves `cluster0`'s peer ID and bootstraps to it
- Uses CRDT consensus with trusted peers

### `scripts/smoke-test.sh`
Validates cluster functionality:
1. Verifies all 6 services are healthy
2. Creates identical content on all 3 IPFS nodes (CID consistency check)
3. Pins content via `cluster0` with replication policy
4. Waits for content to replicate to minimum required nodes
5. Verifies content is readable from all 3 nodes
6. Restarts `ipfs1` and verifies content is still accessible (resilience test)

## Data Persistence

Docker volumes store all persistent data:

| Volume | Purpose |
|--------|---------|
| `ipfs0-data`, `ipfs1-data`, `ipfs2-data` | IPFS datastore and configuration |
| `ipfs0-export`, `ipfs1-export`, `ipfs2-export` | IPFS export directories |
| `cluster0-data`, `cluster1-data`, `cluster2-data` | Cluster state and pinset |

**To reset everything:**
```bash
make reset  # Stops containers AND deletes all volumes
```

## Troubleshooting

### Services not starting
```bash
# Check container status
make ps

# View logs for errors
make logs
```

### Cluster peers not connecting
```bash
# Check cluster0 peer ID
docker exec dark-ipfs-cluster0 ipfs-cluster-ctl id

# Check cluster1/2 logs for bootstrap errors
docker logs dark-ipfs-cluster1
```

### Content not replicating
```bash
# Check pin status
curl "http://localhost:9094/pins" | jq

# Check allocations
curl "http://localhost:9094/allocations" | jq
```

## Notes

- **Local testing only** — This module is designed for development and integration testing, not production.
- **Automatic peering** — `cluster1` and `cluster2` automatically discover and join `cluster0` on startup.
- **CRDT consensus** — The cluster uses CRDT (Conflict-free Replicated Data Type) consensus, suitable for dynamic peer sets.
- **Resilience** — The smoke test validates that content survives node restarts.

## License

This module is part of the dARK project and is licensed under AGPLv3.
