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
{{- $image := printf "%s:%s" .Values.image.repository .Values.image.tag -}}
{{- if .Values.image.digest -}}{{- printf "%s@%s" $image .Values.image.digest -}}{{- else -}}{{- $image -}}{{- end -}}
{{- end -}}
{{- define "gesttalt.postgresHost" -}}{{ printf "%s-rw" .Values.postgres.clusterName }}{{- end -}}
