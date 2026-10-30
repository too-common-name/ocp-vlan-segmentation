# IP Forwarding and Gateway Mode for MetalLB L2

This document covers the recommended forwarding configuration for MetalLB L2 on secondary VLAN interfaces, and explains why common recommendations (`ipForwarding: Global`, `routingViaHost: true`) are either unnecessary or harmful.

## Why IP forwarding is needed

After nftables rewrites the VIP destination to a ClusterIP (DNAT), the packet must cross from the VLAN interface (`vlan100`) to `br-ex` — this is IP forwarding. The kernel only does it if forwarding is enabled on the ingress interface.

## Per-interface forwarding (recommended)

Use NMState's native `ipv4.forwarding: true` in the per-node NNCP:

```yaml
interfaces:
  - name: vlan100
    type: ovs-interface
    state: up
    ipv4:
      address:
        - ip: 10.100.0.10
          prefix-length: 24
      dhcp: false
      enabled: true
      forwarding: true
```

NMState writes the per-interface flag (`/proc/sys/net/ipv4/conf/vlan100/forwarding`) and keeps it in sync with the desired state. The Linux kernel checks this flag on the ingress device — if it's enabled, the packet can be forwarded even when the global `ip_forward` is 0.

OVN-Kubernetes already sets `forwarding=1` on `br-ex` and `ovn-k8s-mp0` (the interfaces it manages), so the only addition needed is on the secondary VLAN interfaces.

**Requires NMState ≥ 2.2** (shipped with OpenShift 4.18+).

On older NMState versions (< 2.2), the same result can be achieved with a **MachineConfig** that writes a sysctl file or a systemd unit to enable forwarding at boot — but this triggers a node reboot and is harder to maintain.

## Why NOT to use `ipForwarding: Global`

The OpenShift documentation and various KB articles recommend enabling forwarding via the cluster network operator with `ipForwarding: Global`.

**Avoid this setting.** As confirmed by the OVN-Kubernetes maintainers, `ipForwarding: Global` not only enables `ip_forward=1` globally, but also **removes certain default-deny nftables rules**, weakening the node's security posture. It turns every node into a full IP router across all interfaces — far more permissive than needed.

Per-interface forwarding via NMState achieves the same result with no security side effects.

## Why `routingViaHost` is NOT required

Many sources (documentation, KB articles, internal guidance) recommend setting `routingViaHost: true` in the cluster network operator. This controls the OVN gateway mode:

- **Shared gateway** (default, `routingViaHost: false`): external traffic is handled entirely inside OVS — packets flow through `br-ex` and are forwarded by OVN's logical pipeline without ever entering the host's kernel routing stack. More efficient, but the host's nftables rules do not see external traffic.
- **Local gateway** (`routingViaHost: true`): external traffic exits OVS into the host's kernel network stack, is processed by the host's routing table and nftables rules, and then re-enters OVS. Gives the host full visibility at the cost of an extra hop.

We tested this explicitly on OCP 4.22 and found that `routingViaHost` **is not required for MetalLB L2 on secondary interfaces**.

The reason: traffic on secondary VLAN interfaces always enters the host's kernel network stack directly (these interfaces are **not** part of `br-ex`). The gateway mode only controls how traffic on `br-ex` is processed — it is irrelevant for the secondary interface path.

We verified this by switching to shared mode, restarting the OVN-K pods, and confirming the nftables DNAT entries (`external-ips-v4` map) were recreated.

> **Note:** `routingViaHost: true` may still be required for MetalLB in **BGP (L3) mode**, where traffic arrives via `br-ex` from external routers.

## Test matrix

Tested on OCP 4.22.15:

| Configuration | VIP on secondary interface |
|---|---|
| `ipForwarding: Global` + `routingViaHost: true` | Works |
| `ipForwarding: Global` + `routingViaHost: false` | Works |
| `ipForwarding: Restricted` + no per-iface forwarding | **Fails** |
| `ipForwarding: Restricted` + per-iface forwarding | Works |

## Recommendation

The minimal, most secure configuration:

- `ipForwarding: Restricted` (default — do not change)
- Per-interface forwarding via NMState (`ipv4.forwarding: true` in the NNCP)
- No changes to gateway mode needed for L2
