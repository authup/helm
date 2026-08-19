{{/*
URL derivation. server.publicUrl / adminConsole.publicUrl always win; otherwise the URL is
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

{{- define "authup.adminConsole.publicUrl" -}}
{{- if .Values.adminConsole.publicUrl -}}
{{- include "authup.assertUrlScheme" (dict "key" "adminConsole.publicUrl" "url" (include "authup.tplvalues.render" (dict "value" .Values.adminConsole.publicUrl "context" $) | trimSuffix "/")) -}}
{{- else -}}
{{- include "authup.ingress.derivedUrl" (dict "ingress" .Values.adminConsole.ingress "context" $) -}}
{{- end -}}
{{- end -}}

{{/*
Browser-facing server-core URL for the UI (NUXT_PUBLIC_API_URL).
*/}}
{{- define "authup.adminConsole.apiUrl" -}}
{{- if .Values.adminConsole.apiUrl -}}
{{- include "authup.assertUrlScheme" (dict "key" "adminConsole.apiUrl" "url" (include "authup.tplvalues.render" (dict "value" .Values.adminConsole.apiUrl "context" $) | trimSuffix "/")) -}}
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
{{- if and .Values.adminConsole.enabled .Values.server.trustedOriginsAppendAdminConsole -}}
{{- $uiOrigin := include "authup.urlOrigin" (include "authup.adminConsole.publicUrl" .) -}}
{{- $serverOrigin := include "authup.urlOrigin" (include "authup.server.publicUrl" .) -}}
{{- if and $uiOrigin (ne $uiOrigin $serverOrigin) -}}
{{- $origins = append $origins $uiOrigin -}}
{{- end -}}
{{- end -}}
{{- $origins = $origins | uniq -}}
{{- range $origins -}}
{{- include "authup.assertTrustedOrigin" . -}}
{{- end -}}
{{- $origins | join "," -}}
{{- end -}}

{{/*
Post-render origin assertion. A trusted origin becomes an `<origin>/**`
redirect pattern on every realm's built-in system clients, and `**` in the
host matches the rest of the value outright, so one typo turns that
allowlist into allow-any-origin. authup rejects it at boot (beta.59+);
asserting here turns a crash-looping IdP into a failed render. A single `*`
is a supported host wildcard and stays allowed.
*/}}
{{- define "authup.assertTrustedOrigin" -}}
{{- if contains "**" . -}}
{{- fail (printf "authup: a trusted origin must not use \"**\" in the host, it would match every origin. Use a single \"*\" for a host wildcard (got %q)." .) -}}
{{- end -}}
{{- end -}}
