{{/*
client-console environment as a YAML map. The published UI bundle only honors Nuxt
runtime-config names (NUXT_*); the API URL must be the BROWSER-reachable
server-core URL, never a cluster-internal service name.
The chart deliberately never sets NUXT_PUBLIC_COOKIE_DOMAIN: sharing a cookie
domain between client-console and the hosted auth pages is unsupported by authup.
*/}}
{{- define "authup.ui.configEnv" -}}
{{- $apiUrl := include "authup.ui.apiUrl" . }}
{{- if $apiUrl }}
NUXT_PUBLIC_API_URL: {{ $apiUrl | quote }}
{{- end }}
{{- $publicUrl := include "authup.ui.publicUrl" . }}
{{- if $publicUrl }}
NUXT_PUBLIC_PUBLIC_URL: {{ $publicUrl | quote }}
{{- end }}
{{- if .Values.ui.internalApiUrl }}
NUXT_API_URL: {{ include "authup.tplvalues.render" (dict "value" .Values.ui.internalApiUrl "context" $) | quote }}
{{- end }}
{{- range $key, $value := .Values.ui.config }}
{{ $key }}: {{ include "authup.tplvalues.render" (dict "value" ($value | toString) "context" $) | quote }}
{{- end }}
{{- end -}}
