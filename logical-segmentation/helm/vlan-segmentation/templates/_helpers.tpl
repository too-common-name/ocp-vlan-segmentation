{{/*
Chart labels
*/}}
{{- define "vlan-seg.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Interface name for a VLAN — always vlan<id>, regardless of bridgeType.
This keeps MetalLB, L2Advertisement, and forwarding config identical
across both approaches (OVS bridge and VLAN subinterfaces).
Usage: {{ include "vlan-seg.ifname" (dict "root" $ "vlanId" 100) }}
*/}}
{{- define "vlan-seg.ifname" -}}
vlan{{ .vlanId }}
{{- end -}}
