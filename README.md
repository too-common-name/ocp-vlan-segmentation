# VLAN Network Segmentation on OpenShift

Companion repository for the article series **"VLAN Network Segmentation on OpenShift: NAD localnet vs MetalLB L2"**.

Three scenarios are provided, each as a self-contained Helm chart with deploy/verify/teardown automation:

| Scenario | Description | Approach |
|---|---|---|
| [**CUDN Segmentation**](cudn-segmentation/) | Pods get a secondary interface directly on the physical VLAN via ClusterUserDefinedNetwork (CUDN) with OVN localnet topology. No VIPs, no DNAT, no MetalLB. | NAD localnet (Part 1) |
| [**MetalLB L2 Segmentation**](namespace-segmentation/) | Services are exposed on the physical VLAN via MetalLB L2 VIPs. Full Kubernetes Service API with on-node nftables hardening for cross-VLAN isolation. | MetalLB L2 (Part 2) |
| [**HCP Segmentation**](hcp-segmentation/) | Hosted Control Planes (KubeVirt) with per-tenant VLAN isolation. Services inside hosted clusters are exposed via KCCM shadow services and MetalLB on the hosting cluster. | MetalLB L2 + HCP |

## Which scenario should I use?

- **CUDN Segmentation** — when the workload needs to *be* on the VLAN with a native IP. Best for fixed workloads, strict isolation, OT/industrial environments. Simplest security model: no DNAT, no forwarding, no cross-VLAN risk.
- **MetalLB L2 Segmentation** — when the workload needs to be *reachable from* the VLAN through a standard Kubernetes Service (VIPs, load balancing, any L4 protocol). Requires on-node nftables pre-filter for cross-VLAN isolation.
- **HCP Segmentation** — when each tenant runs in a separate hosted cluster (KubeVirt VMs) and needs service exposure on a dedicated physical VLAN.

## Prerequisites

| Component | Required for | Minimum version |
|---|---|---|
| **OpenShift Container Platform** | All scenarios | 4.18+ (NMState ≥ 2.2 for per-interface forwarding) |
| **NMState Operator** | All — OVS bridge provisioning via NNCP | Shipped with OCP |
| **MetalLB Operator** | MetalLB L2 and HCP scenarios | Shipped with OCP |
| **OVN-Kubernetes** | All — cluster network plugin (default) | Shipped with OCP |
| **OpenShift Virtualization** | HCP scenario only | Shipped with OCP |
| **Helm 3** | All — chart deployment | 3.x |
| **Physical NIC** | All — trunk port carrying tagged VLANs | 802.1Q-capable |

## Repository structure

```
ocp-vlan-segmentation/
├── cudn-segmentation/          # CUDN localnet scenario (Part 1)
│   ├── helm/cudn-segmentation/ # Helm chart
│   ├── images/                 # Architecture diagram
│   ├── Makefile                # deploy / teardown targets
│   └── README.md
├── namespace-segmentation/     # MetalLB L2 scenario (Part 2)
│   ├── helm/vlan-segmentation/ # Helm chart (OVS bridge + VLAN subinterfaces)
│   ├── docs/                   # Deep dives (forwarding modes, nftables variants)
│   ├── images/                 # Architecture diagram
│   ├── Makefile                # deploy-ovs / deploy-vlan / teardown targets
│   └── README.md
└── hcp-segmentation/           # HCP + KubeVirt scenario
    ├── helm/hcp-cluster/       # Per-cluster Helm chart
    ├── images/                 # Architecture diagram
    ├── Makefile                # deploy / teardown targets (per cluster)
    └── README.md
```

## Quick start

```bash
# Clone
git clone https://github.com/too-common-name/ocp-vlan-segmentation.git
cd ocp-vlan-segmentation

# CUDN localnet
cd cudn-segmentation
vim helm/cudn-segmentation/values.yaml   # Set physicalInterface, VLANs
make deploy

# MetalLB L2
cd namespace-segmentation
vim helm/vlan-segmentation/values.yaml   # Set physicalInterface, VLANs, nodes, IPs
make deploy-ovs
```

See each scenario's README for full configuration details, verification steps, and teardown instructions.

## Additional documentation

| Document | Description |
|---|---|
| [Forwarding and Gateway Mode](namespace-segmentation/docs/forwarding-and-gateway-mode.md) | Why per-interface forwarding via NMState is preferred over `ipForwarding: Global`, and why `routingViaHost: true` is not required for MetalLB L2 on secondary interfaces |
| [nftables Pre-Filter Variants](namespace-segmentation/docs/nftables-prefilter-variants.md) | Strict subnet isolation (default) vs surgical cross-VLAN blocking — two nftables approaches with trade-offs |

## Lab environment

All scenarios were developed and tested on:

- OpenShift Container Platform 4.22
- OVN-Kubernetes (default CNI)
- NMState 2.2
- 3-node bare-metal cluster with an external test client on dedicated VLANs
