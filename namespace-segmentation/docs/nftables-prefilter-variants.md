# nftables Pre-Filter Variants

The MetalLB L2 scenario requires an nftables pre-filter to prevent cross-VLAN VIP access. The filter runs at `priority dstnat - 1` — before OVN-Kubernetes's DNAT — so packets are dropped while the original destination (the VIP) is still visible.

Two variants are available:

## Variant A — Strict subnet isolation (default)

The simplest and most restrictive option. On each VLAN interface, drop all traffic not destined to the interface's own subnet:

```nft
table inet vlan-isolation {
    chain prerouting {
        type filter hook prerouting priority dstnat - 1; policy accept;
        iifname "vlan100" ip daddr != 10.100.0.0/24 counter drop
        iifname "vlan200" ip daddr != 10.200.0.0/24 counter drop
    }
}
```

Each rule reads: "if a packet arrives on `vlan100` and its destination is anything outside `10.100.0.0/24`, drop it."

This blocks not only cross-VLAN VIP access, but **any** traffic that attempts to use the node as a router from the VLAN interface. In an industrial/OT context, this is often the desired behavior — a device on VLAN 100 should only reach destinations on its own subnet.

**This is the variant deployed by the Helm chart** when `vlanIsolation.enabled: true`.

## Variant B — Surgical cross-VLAN blocking

A more permissive option using an nftables set: only drop traffic destined to other known VLAN subnets, but allow traffic to any other destination:

```nft
table inet vlan-isolation {
    set vlan-subnets {
        type ipv4_addr
        flags interval
        comment "All VLAN subnets — used to detect cross-VLAN traffic"
        elements = { 10.100.0.0/24, 10.200.0.0/24 }
    }

    chain prerouting {
        type filter hook prerouting priority dstnat - 1; policy accept;
        iifname "vlan100" ip daddr @vlan-subnets ip daddr != 10.100.0.0/24 counter drop
        iifname "vlan200" ip daddr @vlan-subnets ip daddr != 10.200.0.0/24 counter drop
    }
}
```

Each rule reads: "if a packet arrives on `vlan100` and its destination is a VLAN subnet (`@vlan-subnets`) but NOT `10.100.0.0/24`, drop it."

Traffic to non-VLAN destinations (e.g., internet-routable addresses) is unaffected. This variant is appropriate when devices on a VLAN legitimately use the node as a gateway for other traffic.

Adding a new VLAN requires one entry in the `vlan-subnets` set and one rule in the chain.

## Choosing a variant

| | Variant A (strict) | Variant B (surgical) |
|---|---|---|
| **Blocks cross-VLAN VIPs** | Yes | Yes |
| **Blocks all non-local routing** | Yes | No |
| **Use case** | OT/industrial, strict isolation | Mixed environments, node as partial gateway |
| **Complexity** | Low | Medium (nftables sets) |
| **Deployed by Helm chart** | Yes | No (manual MachineConfig) |

For segmentation use cases, **Variant A is recommended**. If you need Variant B, replace the base64 content in the MachineConfig with your custom rules (`base64 -w0 < vlan-isolation.nft`).
