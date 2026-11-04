{{/* Resource names are the release name: release "vllm" gives Service "vllm". */}}
{{- define "vllm.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Selector labels include the release, so the stable Service never sends traffic to canary pods. */}}
{{- define "vllm.selectorLabels" -}}
app.kubernetes.io/name: vllm
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* Where the weights are: s3://<models bucket>/<model name>/<revision>/ (written by the Job in model/). */}}
{{- define "vllm.modelUri" -}}
{{- printf "s3://%s/%s/%s/" (required "modelsBucket is required" .Values.modelsBucket) (required "model.name is required" .Values.model.name) (required "model.revision is required" .Values.model.revision) -}}
{{- end -}}

{{- define "vllm.labels" -}}
{{ include "vllm.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
astra/role: {{ ternary "canary" "stable" .Values.canary }}
{{- end -}}
