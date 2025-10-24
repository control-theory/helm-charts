{{/*
Expand the name of the chart.
*/}}
{{- define "aigent.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "aigent.fullname" -}}
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
{{- define "aigent.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "aigent.labels" -}}
helm.sh/chart: {{ include "aigent.chart" . }}
{{ include "aigent.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "aigent.selectorLabels" -}}
app.kubernetes.io/name: {{ include "aigent.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "aigent.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "aigent.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Validate required fields
*/}}
{{- define "aigent.validateRequiredFields" -}}
{{- if not .Values.environment -}}
{{- fail "environment is required (e.g., 'dev', 'stage', 'prod')" -}}
{{- end -}}
{{- if not .Values.cluster -}}
{{- fail "cluster is required (e.g., 'demo-cluster')" -}}
{{- end -}}
{{- end }}
