{{- define "gesttalt.fullname" -}}{{- default .Chart.Name .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}{{- end -}}
{{- define "gesttalt.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
{{- define "gesttalt.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
{{- define "gesttalt.image" -}}
{{- $tag := default .Chart.AppVersion .Values.image.tag -}}
{{- $image := printf "%s:%s" .Values.image.repository $tag -}}
{{- if .Values.image.digest -}}{{- printf "%s@%s" $image .Values.image.digest -}}{{- else -}}{{- $image -}}{{- end -}}
{{- end -}}
{{- define "gesttalt.postgresHost" -}}
{{- if eq .Values.postgres.mode "standalone" -}}
{{- printf "%s-postgres" (include "gesttalt.fullname" .) -}}
{{- else -}}
{{- printf "%s-rw" .Values.postgres.clusterName -}}
{{- end -}}
{{- end -}}
