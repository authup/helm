{{/*
URL derivation. server.publicUrl / ui.publicUrl always win; otherwise the URL is
derived from the component's ingress (scheme from tls/certManager, host, path).
Returns "" when nothing can be derived.
*/}}

{{- define "authup.ingress.derivedUrl" -}}
{{- if and .ingress.enabled .ingress.hostname -}}
{{- $scheme := ternary "https" "http" (or .ingress.tls .ingress.certManager) -}}
{{- $host := include "authup.tplvalues.render" (dict "value" .ingress.hostname "context" .context) -}}
{{- $path := .ingress.path | default "/" | trimSuffix "/" -}}
{{- printf "%s://%s%s" $scheme $host $path -}}
{{- end -}}
{{- end -}}

{{/*
Post-render scheme assertion: validations.yaml checks literal values, but a
tpl-rendered value only materializes here — assert it AFTER rendering so a
scheme-less result can never reach an env var or origin derivation.
*/}}
{{- define "authup.assertUrlScheme" -}}
{{- if and .url (not (regexMatch "^https?://" .url)) -}}
{{- fail (printf "authup: %s must render to a full URL including the http(s):// scheme (got %q)." .key .url) -}}
{{- end -}}
{{- .url -}}
{{- end -}}

{{- define "authup.server.publicUrl" -}}
{{- if .Values.server.publicUrl -}}
{{- include "authup.assertUrlScheme" (dict "key" "server.publicUrl" "url" (include "authup.tplvalues.render" (dict "value" .Values.server.publicUrl "context" $) | trimSuffix "/")) -}}
{{- else -}}
{{- include "authup.ingress.derivedUrl" (dict "ingress" .Values.server.ingress "context" $) -}}
{{- end -}}
{{- end -}}

{{- define "authup.ui.publicUrl" -}}
{{- if .Values.ui.publicUrl -}}
{{- include "authup.assertUrlScheme" (dict "key" "ui.publicUrl" "url" (include "authup.tplvalues.render" (dict "value" .Values.ui.publicUrl "context" $) | trimSuffix "/")) -}}
{{- else -}}
{{- include "authup.ingress.derivedUrl" (dict "ingress" .Values.ui.ingress "context" $) -}}
{{- end -}}
{{- end -}}

{{/*
Browser-facing server-core URL for the UI (NUXT_PUBLIC_API_URL).
*/}}
{{- define "authup.ui.apiUrl" -}}
{{- if .Values.ui.apiUrl -}}
{{- include "authup.assertUrlScheme" (dict "key" "ui.apiUrl" "url" (include "authup.tplvalues.render" (dict "value" .Values.ui.apiUrl "context" $) | trimSuffix "/")) -}}
{{- else -}}
{{- include "authup.server.publicUrl" . -}}
{{- end -}}
{{- end -}}

{{/*
Extract the origin (scheme://host[:port]) from a URL.
*/}}
{{- define "authup.urlOrigin" -}}
{{- if . -}}
{{- $u := urlParse . -}}
{{- if and $u.scheme $u.host -}}
{{- printf "%s://%s" $u.scheme $u.host -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
TRUSTED_ORIGINS: the user-supplied list/string, plus the UI origin unless
disabled or already covered by the server public URL's origin.
*/}}
{{- define "authup.server.trustedOrigins" -}}
{{- $origins := list -}}
{{- $configured := .Values.server.trustedOrigins -}}
{{- if kindIs "string" $configured -}}
{{- if $configured -}}
{{- range splitList "," (include "authup.tplvalues.render" (dict "value" $configured "context" $)) -}}
{{- $origins = append $origins (trim .) -}}
{{- end -}}
{{- end -}}
{{- else -}}
{{- range $configured -}}
{{- $origins = append $origins (trim (include "authup.tplvalues.render" (dict "value" . "context" $))) -}}
{{- end -}}
{{- end -}}
{{- if and .Values.ui.enabled .Values.server.trustedOriginsAppendUI -}}
{{- $uiOrigin := include "authup.urlOrigin" (include "authup.ui.publicUrl" .) -}}
{{- $serverOrigin := include "authup.urlOrigin" (include "authup.server.publicUrl" .) -}}
{{- if and $uiOrigin (ne $uiOrigin $serverOrigin) -}}
{{- $origins = append $origins $uiOrigin -}}
{{- end -}}
{{- end -}}
{{- $origins | uniq | join "," -}}
{{- end -}}
