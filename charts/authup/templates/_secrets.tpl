{{/*
Resolve a secret value with upgrade stability, returned RAW (not base64).
Order: explicit value -> existing Secret content (lookup) -> generated random.
lookup is inert under `helm template` / ArgoCD-style renders; in that case a
fresh random is produced per render. GitOps users should set explicit values or
use existingSecret references.
Usage: {{ include "authup.secret.rawValue" (dict "secret" "name" "key" "k" "value" .Values.<key> "length" 32 "context" $) }}
*/}}
{{- define "authup.secret.rawValue" -}}
{{- if .value -}}
{{- .value -}}
{{- else -}}
{{- $existing := lookup "v1" "Secret" (include "authup.namespace" .context) .secret -}}
{{- if and $existing $existing.data (hasKey $existing.data .key) -}}
{{- index $existing.data .key | b64dec -}}
{{- else -}}
{{- randAlphaNum (.length | default 32 | int) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Name of the secret holding the authentication bootstrap credentials.
*/}}
{{- define "authup.auth.secretName" -}}
{{- if .Values.auth.existingSecret -}}
{{- include "authup.tplvalues.render" (dict "value" .Values.auth.existingSecret "context" $) -}}
{{- else -}}
{{- include "authup.fullname" . -}}
{{- end -}}
{{- end -}}

{{/*
Whether the chart itself manages the auth secret.
*/}}
{{- define "authup.auth.createSecret" -}}
{{- if not .Values.auth.existingSecret -}}true{{- end -}}
{{- end -}}

{{/*
Whether a secrets encryption key is deliberately configured: an inline value,
or an existing secret PLUS the explicit opt-in flag. Never inferred from
auth.existingSecret alone — a silently absent KEK would fail open into
plaintext-at-rest.
*/}}
{{- define "authup.auth.hasSecretsEncryptionKey" -}}
{{- if or .Values.auth.secretsEncryptionKey (and .Values.auth.existingSecret .Values.auth.secretsEncryptionKeyEnabled) -}}true{{- end -}}
{{- end -}}

{{/*
Name of the secret holding the SMTP connection string.
*/}}
{{- define "authup.smtp.enabled" -}}
{{- if or .Values.smtp.connectionString .Values.smtp.existingSecret -}}true{{- end -}}
{{- end -}}

{{- define "authup.smtp.secretName" -}}
{{- if .Values.smtp.existingSecret -}}
{{- include "authup.tplvalues.render" (dict "value" .Values.smtp.existingSecret "context" $) -}}
{{- else -}}
{{- printf "%s-smtp" (include "authup.fullname" .) -}}
{{- end -}}
{{- end -}}

{{- define "authup.smtp.secretKey" -}}
{{- if .Values.smtp.existingSecret -}}
{{- .Values.smtp.existingSecretKey -}}
{{- else -}}
smtp-connection-string
{{- end -}}
{{- end -}}
