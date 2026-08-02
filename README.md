# dark-ipfs storage node

This repository runs exactly one production storage pair per server:

```text
Kubo + IPFS Cluster peer
```

Every server uses the same Compose file. Multiple servers and sites join one
global CRDT Cluster over the VPN. Store API is not part of this stack; it runs
once in each application site and uses both local storage servers.

For the explicit single-machine `developer` profile, the pair also joins the
external `dark-net` network under the aliases `dark-ipfs-local` and
`dark-ipfs-cluster-local`. This lets the co-located Store API use private Docker
networking while the administrative host ports remain bound to loopback. The
aliases do not replace VPN endpoints in sandbox or production deployments.

## Generated configuration

`dark-deployer` generates `.env.node` from `storage-topology.json`. It includes:

- the node and site names;
- the server's VPN address;
- bootstrap VPN addresses;
- the global Cluster name and replication factors;
- absolute paths to the Kubo swarm key and Cluster secret.

The secret files are mounted read-only. `.env.node`, persistent identities and
data volumes are never committed. The first peer in the topology seeds a new
Cluster; every other peer discovers a running peer's persistent identity through
its private API and joins it.

The entrypoint applies Kubo's `autoconf-off` profile on every start and disables
anonymous telemetry. Private swarms use only their explicitly configured
bootstrap peers and do not inherit discovery, routing, publishing or AutoTLS
endpoints from the public IPFS mainnet.

Required VPN connectivity:

| Port | Purpose |
| ---: | --- |
| `4001/tcp+udp` | Kubo swarm |
| `9096/tcp+udp` | Cluster swarm |
| `5001/tcp` | Kubo API, site-local consumers only |
| `9094/tcp` | Cluster REST, site-local consumers/operators only |
| `9095/tcp` | Cluster Proxy, site-local Store API only |

## Operations

```bash
make validate     # render and validate Compose configuration
make up           # start this Kubo/Cluster pair
make ps           # show container state
make logs         # follow logs
make identity     # print persistent Kubo and Cluster identities
make smoke-test   # add, pin and retrieve through this pair
make down         # stop containers and preserve volumes
```

There is deliberately no automated volume-reset command. Removing the named
Kubo or Cluster volumes destroys a node identity and its local copy of content.

Global audits and allocation repair run from `dark-deployer`:

```bash
python3 install.py storage audit
python3 install.py storage reconcile
```
