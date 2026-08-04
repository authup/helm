{{/*
client-admin-console environment as a YAML map. The published UI bundle only honors Nuxt
runtime-config names (NUXT_*); the API URL must be the BROWSER-reachable
server-core URL, never a cluster-internal service name.
The chart deliberately never sets NUXT_PUBLIC_COOKIE_DOMAIN: sharing a cookie
domain between client-admin-console and the hosted auth pages is unsupported by authup.
*/}}
{{- define "authup.adminConsole.configEnv" -}}
{{- $apiUrl := include "authup.adminConsole.apiUrl" . }}
{{- if $apiUrl }}
NUXT_PUBLIC_API_URL: {{ $apiUrl | quote }}
{{- end }}
{{- $publicUrl := include "authup.adminConsole.publicUrl" . }}
{{- if $publicUrl }}
NUXT_PUBLIC_PUBLIC_URL: {{ $publicUrl | quote }}
{{- end }}
{{- if .Values.adminConsole.internalApiUrl }}
NUXT_API_URL: {{ include "authup.tplvalues.render" (dict "value" .Values.adminConsole.internalApiUrl "context" $) | quote }}
{{- end }}
{{- range $key, $value := .Values.adminConsole.config }}
{{ $key }}: {{ include "authup.tplvalues.render" (dict "value" ($value | toString) "context" $) | quote }}
{{- end }}
{{- end -}}
