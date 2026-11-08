{{- define "selfheal.name" -}}selfheal{{- end -}}
{{- define "selfheal.labels" -}}
app.kubernetes.io/name: {{ include "selfheal.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
{{- define "selfheal.selector" -}}
app.kubernetes.io/name: {{ include "selfheal.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
