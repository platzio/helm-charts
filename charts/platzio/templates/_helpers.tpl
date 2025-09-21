{{/*
Expand the name of the chart.
*/}}
{{- define "chart.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "chart.fullname" -}}
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
{{- define "chart.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "chart.labels" -}}
helm.sh/chart: {{ include "chart.chart" . }}
{{ include "chart.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "chart.selectorLabels" -}}
app.kubernetes.io/name: {{ include "chart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "database.envVars" }}
- name: PGHOST
  valueFrom:
    secretKeyRef:
      name: {{ .Values.database.secretName }}
      key: PGHOST
- name: PGPORT
  valueFrom:
    secretKeyRef:
      name: {{ .Values.database.secretName }}
      key: PGPORT
- name: PGUSER
  valueFrom:
    secretKeyRef:
      name: {{ .Values.database.secretName }}
      key: PGUSER
- name: PGPASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.database.secretName }}
      key: PGPASSWORD
- name: PGDATABASE
  valueFrom:
    secretKeyRef:
      name: {{ .Values.database.secretName }}
      key: PGDATABASE
{{- end }}

{{- define "platz.ownUrlSchema" -}}
    {{- if .enabled }}
        {{- if empty .tls }}
        {{- printf "http" }}
        {{- else if empty (first .tls).hosts }}
        {{- printf "http" }}
        {{- else }}
        {{- printf "https" }}
        {{- end }}
    {{- end }}
{{- end }}

{{- define "platz.ownUrl" -}}
    {{- if .Values.ownUrlOverride }}
        {{- .Values.ownUrlOverride }}
    {{- else }}
        {{- with .Values.ingress }}
            {{- if .enabled }}
                {{- $scheme := include "platz.ownUrlSchema" . -}}
                {{- $host := (first .rules).host -}}
                {{- printf "%s://%s" $scheme $host }}
            {{- end }}
        {{- end }}
    {{- end }}
{{- end }}

{{- define "platz.issuerName" -}}
{{- $fullname := include "chart.fullname" . }}
{{- if .Values.certManager.issuer.name }}
{{- .Values.certManager.issuer.name }}
{{- else }}
{{- printf "%s-issuer" $fullname }}
{{- end }}
{{- end }}
