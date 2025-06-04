{{/*
Expand the name of the chart.
*/}}
{{- define "vault.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "vault.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "vault.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "vault.labels" -}}
helm.sh/chart: {{ include "vault.chart" . }}
{{ include "vault.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "vault.selectorLabels" -}}
app.kubernetes.io/name: {{ include "vault.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "vault.serviceAccountName" -}}
{{- if .Values.vault.serviceAccount.create }}
{{- default (include "vault.fullname" .) .Values.vault.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.vault.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the proper Vault image name
*/}}
{{- define "vault.image" -}}
{{- $registryName := .Values.vault.image.registry -}}
{{- $repositoryName := .Values.vault.image.repository -}}
{{- $tag := .Values.vault.image.tag | toString -}}
{{- if .Values.global.imageRegistry }}
    {{- printf "%s/%s:%s" .Values.global.imageRegistry $repositoryName $tag -}}
{{- else -}}
    {{- printf "%s/%s:%s" $registryName $repositoryName $tag -}}
{{- end -}}
{{- end }}

{{/*
Return the proper Storage Class
*/}}
{{- define "vault.storageClass" -}}
{{- if .Values.global.storageClass -}}
    {{- .Values.global.storageClass -}}
{{- else if .Values.vault.persistence.storageClass -}}
    {{- .Values.vault.persistence.storageClass -}}
{{- end -}}
{{- end }}

{{/*
Validate replica count
*/}}
{{- define "vault.validateReplicas" -}}
{{- if or (lt (.Values.vault.replicaCount | int) 1) (gt (.Values.vault.replicaCount | int) 3) -}}
{{- fail "vault.replicaCount must be between 1 and 3" -}}
{{- end -}}
{{- end }}

{{/*
Get Vault configuration
*/}}
{{- define "vault.configuration" -}}
{{- if .Values.vault.configuration -}}
{{- .Values.vault.configuration -}}
{{- else -}}
ui = true
api_addr = "http://0.0.0.0:8200"
cluster_addr = "http://0.0.0.0:8201"

storage "file" {
  path = "/vault/data"
}

listener "tcp" {
  address = "0.0.0.0:8200"
  tls_disable = true
}
{{- end -}}
{{- end }}