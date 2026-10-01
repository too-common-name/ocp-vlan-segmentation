{{/*
Chart labels
*/}}
{{- define "vlan-seg.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Interface name for a VLAN, based on bridgeType.
  ovs-bridge:          vlan100
  vlan-subinterfaces:  eno1.100
  linux-bridge:        br-secondary.100
Usage: {{ include "vlan-seg.ifname" (dict "root" $ "vlanId" 100) }}
*/}}
{{- define "vlan-seg.ifname" -}}
{{- if eq .root.Values.bridgeType "ovs-bridge" -}}
vlan{{ .vlanId }}
{{- else if eq .root.Values.bridgeType "vlan-subinterfaces" -}}
{{ .root.Values.physicalInterface }}.{{ .vlanId }}
{{- else if eq .root.Values.bridgeType "linux-bridge" -}}
{{ .root.Values.linuxBridge.name }}.{{ .vlanId }}
{{- end -}}
{{- end -}}
