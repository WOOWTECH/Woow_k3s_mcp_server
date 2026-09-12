{{/*
Helper templates for the mcp-server chart.
The proxy and admin objects keep the fixed names used by the original
k8s-manifests (mcp-k8s-proxy*, k3s-mcp-admin*) since they are namespaced and
this chart owns its own namespace - no collision risk there. Cluster-scoped
admin RBAC objects are release-derived on purpose: the legacy mcp-system
install already owns ClusterRole/ClusterRoleBinding "k3s-mcp-admin-role" /
"k3s-mcp-admin-binding", and a second fixed-name copy would collide.
*/}}

{{- define "mcp-server.ns" -}}
{{ default .Release.Namespace .Values.namespace.name }}
{{- end -}}

{{- define "mcp-server.partOf" -}}
app.kubernetes.io/part-of: woow-mcp-server
{{- end -}}

{{- define "mcp-server.keepAnnotations" -}}
{{- if .Values.keepOnUninstall -}}
annotations:
  helm.sh/resource-policy: keep
{{- end -}}
{{- end -}}

{{/* storageClassName for a component: its own override or the global default. */}}
{{- define "mcp-server.storageClass" -}}
{{- $ctx := index . 0 -}}
{{- $override := index . 1 -}}
{{ default $ctx.Values.storageClassName $override }}
{{- end -}}

{{/* Release-derived name for the admin console's cluster-scoped RBAC objects. */}}
{{- define "mcp-server.adminClusterRoleName" -}}
{{ .Release.Name }}-k3s-mcp-admin-role
{{- end -}}

{{- define "mcp-server.adminClusterRoleBindingName" -}}
{{ .Release.Name }}-k3s-mcp-admin-binding
{{- end -}}

{{/* Name of the Service the upstream kubernetes-mcp-server subchart renders
(its fullname template: chart name appended to the release name since the
release name never contains "kubernetes-mcp-server"). */}}
{{- define "mcp-server.mcpServiceName" -}}
{{ .Release.Name }}-kubernetes-mcp-server
{{- end -}}
