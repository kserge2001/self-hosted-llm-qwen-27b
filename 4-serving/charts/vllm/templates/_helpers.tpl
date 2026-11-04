{{/* Resource names are the release name: release "vllm" gives Service "vllm". */}}
{{- define "vllm.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Selector labels include the release, so the stable Service never sends traffic to canary pods. */}}
{{- define "vllm.selectorLabels" -}}
app.kubernetes.io/name: vllm
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "vllm.labels" -}}
{{ include "vllm.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
astra/role: {{ ternary "canary" "stable" .Values.canary }}
{{- end -}}
