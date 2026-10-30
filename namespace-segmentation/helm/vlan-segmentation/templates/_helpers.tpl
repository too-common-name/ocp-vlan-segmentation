{{- define "vlan-seg.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/* Interface name — always vlan<id>, regardless of bridgeType */}}
{{- define "vlan-seg.ifname" -}}
vlan{{ .vlanId }}
{{- end -}}
