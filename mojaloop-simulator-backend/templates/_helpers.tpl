{{/* vim: set filetype=mustache: */}}

{{/*
Common labels
*/}}
{{- define "sim-backend.common-labels" -}}
app.kubernetes.io/name: sim-backend
app.kubernetes.io/instance: {{ $.Release.Name }}
app.kubernetes.io/version: "{{ $.Chart.Version | trunc 63 }}"
app.kubernetes.io/managed-by: {{ $.Release.Service }}
helm.sh/chart: {{ printf "%s-%s" $.Chart.Name $.Chart.Version | replace "+" "_" | trunc 63 }}
{{- end -}}

{{/*
Return the name of the chart
*/}}
{{- define "sim-backend.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Return the full name of the release
*/}}
{{- define "sim-backend.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else }}
{{- printf "%s-%s" .Release.Name (include "sim-backend.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end }}
{{- end }}