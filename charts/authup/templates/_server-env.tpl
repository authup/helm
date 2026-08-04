{{/*
Non-secret server-core environment as a YAML map. Single source for the env
ConfigMap AND the migration Job (which inlines it so a pre-upgrade hook never
runs against the previous release's ConfigMap).
Strict-boolean variables are always quoted: authup crashes the boot on
unparsable boolean strings by design.
*/}}
{{- define "authup.server.configEnv" -}}
{{- include "authup.server.validateTheme" . -}}
DB_TYPE: {{ include "authup.database.type" . | quote }}
DB_HOST: {{ include "authup.database.host" . | quote }}
DB_PORT: {{ include "authup.database.port" . | quote }}
DB_USERNAME: {{ include "authup.database.user" . | quote }}
DB_DATABASE: {{ include "authup.database.name" . | quote }}
{{- $publicUrl := include "authup.server.publicUrl" . }}
{{- if $publicUrl }}
PUBLIC_URL: {{ $publicUrl | quote }}
{{- end }}
{{- $trustedOrigins := include "authup.server.trustedOrigins" . }}
{{- if $trustedOrigins }}
TRUSTED_ORIGINS: {{ $trustedOrigins | quote }}
{{- end }}
{{- if not (kindIs "invalid" .Values.server.trustProxy) }}
TRUST_PROXY: {{ .Values.server.trustProxy | toString | quote }}
{{- end }}
REGISTRATION_ENABLED: {{ .Values.server.features.registration | toString | quote }}
PASSWORD_RECOVERY_ENABLED: {{ .Values.server.features.passwordRecovery | toString | quote }}
EMAIL_VERIFICATION_ENABLED: {{ .Values.server.features.emailVerification | toString | quote }}
MFA_ENABLED: {{ .Values.server.mfa.enabled | toString | quote }}
MFA_REQUIRED: {{ .Values.server.mfa.required | toString | quote }}
{{- if .Values.auth.adminPasswordReset }}
USER_ADMIN_PASSWORD_RESET: "true"
{{- end }}
{{- if .Values.auth.systemClientEnabled }}
CLIENT_SYSTEM_ENABLED: "true"
{{- if .Values.auth.systemClientSecretReset }}
CLIENT_SYSTEM_SECRET_RESET: "true"
{{- end }}
{{- end }}
{{- $reserved := list "DB_TYPE" "DB_HOST" "DB_PORT" "DB_USERNAME" "DB_DATABASE" "DB_PASSWORD" "PUBLIC_URL" "TRUSTED_ORIGINS" "TRUST_PROXY" "REGISTRATION_ENABLED" "PASSWORD_RECOVERY_ENABLED" "EMAIL_VERIFICATION_ENABLED" "MFA_ENABLED" "MFA_REQUIRED" "THEME_DIRECTORY_PATH" "THEME_FRAGMENTS_ENABLED" "USER_ADMIN_PASSWORD" "USER_ADMIN_PASSWORD_RESET" "CLIENT_SYSTEM_ENABLED" "CLIENT_SYSTEM_SECRET" "CLIENT_SYSTEM_SECRET_RESET" "REDIS" "SMTP" "SECRETS_ENCRYPTION_KEY" }}
{{- range $key, $value := .Values.server.config }}
{{- if has $key $reserved }}
{{- fail (printf "authup: server.config.%s collides with a first-class chart value — set it through the dedicated value instead." $key) }}
{{- end }}
{{ $key }}: {{ include "authup.tplvalues.render" (dict "value" ($value | toString) "context" $) | quote }}
{{- end }}
{{- end -}}

{{/*
Secret-backed server-core env entries (valueFrom.secretKeyRef list).
Shared by the Deployment and the migration Job.
*/}}
{{- define "authup.server.secretEnv" -}}
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "authup.database.secretName" . }}
      key: {{ include "authup.database.passwordKey" . }}
{{- if include "authup.redis.enabled" . }}
- name: REDIS
  valueFrom:
    secretKeyRef:
      name: {{ include "authup.redis.secretName" . }}
      key: {{ include "authup.redis.secretKey" . }}
{{- end }}
{{- if include "authup.smtp.enabled" . }}
- name: SMTP
  valueFrom:
    secretKeyRef:
      name: {{ include "authup.smtp.secretName" . }}
      key: {{ include "authup.smtp.secretKey" . }}
{{- end }}
- name: USER_ADMIN_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "authup.auth.secretName" . }}
      key: {{ .Values.auth.secretKeys.adminPasswordKey }}
{{- if .Values.auth.systemClientEnabled }}
- name: CLIENT_SYSTEM_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ include "authup.auth.secretName" . }}
      key: {{ .Values.auth.secretKeys.systemClientSecretKey }}
{{- end }}
{{- if include "authup.auth.hasSecretsEncryptionKey" . }}
{{- /* Never optional: a silently missing KEK would boot authup into
       plaintext-at-rest and defer unrecoverable decrypt failures. */}}
- name: SECRETS_ENCRYPTION_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "authup.auth.secretName" . }}
      key: {{ .Values.auth.secretKeys.secretsEncryptionKeyKey }}
{{- end }}
- name: npm_config_cache
  value: /tmp/.npm-cache
{{- end -}}

{{/*
Shared volumes / volumeMounts for the server container (writable dir, tmp,
provisioning files, config file).
*/}}
{{- define "authup.server.volumeMounts" -}}
- name: writable
  mountPath: /usr/src/app/writable
- name: tmp
  mountPath: /tmp
{{- if and .Values.server.provisioning.enabled (or .Values.server.provisioning.files .Values.server.provisioning.existingConfigMap .Values.server.provisioning.existingSecret) }}
- name: provisioning
  mountPath: /usr/src/app/writable/provisioning
  readOnly: true
{{- end }}
{{- if or .Values.server.configuration .Values.server.existingConfigmap }}
- name: configuration
  mountPath: /usr/src/app/authup.server.core.conf
  subPath: authup.server.core.conf
  readOnly: true
{{- end }}
{{- end -}}

{{- define "authup.server.volumes" -}}
- name: writable
  emptyDir: {}
- name: tmp
  emptyDir: {}
{{- if and .Values.server.provisioning.enabled (or .Values.server.provisioning.files .Values.server.provisioning.existingConfigMap .Values.server.provisioning.existingSecret) }}
- name: provisioning
  {{- if .Values.server.provisioning.existingSecret }}
  secret:
    secretName: {{ include "authup.tplvalues.render" (dict "value" .Values.server.provisioning.existingSecret "context" $) }}
  {{- else }}
  configMap:
    name: {{ include "authup.server.provisioningConfigMapName" . }}
  {{- end }}
{{- end }}
{{- if or .Values.server.configuration .Values.server.existingConfigmap }}
- name: configuration
  configMap:
    name: {{ include "authup.server.configurationConfigMapName" . }}
{{- end }}
{{- end -}}

{{/*
Theme volume / volumeMount, deliberately NOT part of the shared server
helpers: the migration Job is a pre-upgrade HOOK, and hooks precede regular
resources, so on the upgrade that first enables theming it would reference a
ConfigMap that does not exist yet and hang. A migration run has no use for
the theme either way.
*/}}
{{/*
Theme environment, kept OUT of authup.server.configEnv for the same reason
as the volume: the migration Job inlines configEnv, and pointing
THEME_DIRECTORY_PATH at a directory that Job does not mount would describe
a pod that does not exist. Nothing reads it there today (the migration
command boots only config + logger, never the http module), but the env
should not contradict the pod it is in.

THEME_* stays in configEnv's reserved-key list regardless, so a
`server.config` entry cannot emit a duplicate key into the same ConfigMap.
*/}}
{{- define "authup.server.themeEnv" -}}
{{- if include "authup.server.themeMounted" . }}
THEME_DIRECTORY_PATH: {{ include "authup.server.themeMountPath" . | quote }}
THEME_FRAGMENTS_ENABLED: {{ .Values.server.theme.fragmentsEnabled | toString | quote }}
{{- end }}
{{- end -}}

{{- define "authup.server.themeVolumeMounts" -}}
{{- if include "authup.server.themeMounted" . }}
- name: theme
  mountPath: {{ include "authup.server.themeMountPath" . }}
  readOnly: true
{{- end }}
{{- end -}}

{{- define "authup.server.themeVolumes" -}}
{{- if include "authup.server.themeMounted" . }}
- name: theme
  configMap:
    name: {{ include "authup.server.themeConfigMapName" . }}
    {{- /* Whole-volume projection on purpose: a subPath mount is frozen
           until the pod restarts, which would destroy authup's live theme
           reload. */}}
    {{- if .Values.server.theme.existingConfigMap }}
    {{- with .Values.server.theme.existingConfigMapItems }}
    items: {{- include "authup.tplvalues.render" (dict "value" . "context" $) | nindent 6 }}
    {{- end }}
    {{- else }}
    items:
      {{- range $path, $content := .Values.server.theme.files }}
      - key: {{ include "authup.server.themeConfigMapKey" $path }}
        path: {{ $path }}
      {{- end }}
    {{- end }}
{{- end }}
{{- end -}}

{{/*
Absolute path the theme volume is mounted at, and the value of
THEME_DIRECTORY_PATH. A constant: the chart owns both ends.
*/}}
{{- define "authup.server.themeMountPath" -}}
/etc/authup/theme
{{- end -}}

{{/*
Flatten a theme path into a valid ConfigMap key ("/" is not allowed in one).
The volume's items list projects it back, so the encoding never reaches the
operator.
*/}}
{{- define "authup.server.themeConfigMapKey" -}}
{{- . | replace "/" "__" -}}
{{- end -}}

{{- define "authup.server.themeConfigMapName" -}}
{{- if .Values.server.theme.existingConfigMap -}}
{{- include "authup.tplvalues.render" (dict "value" .Values.server.theme.existingConfigMap "context" $) -}}
{{- else -}}
{{- printf "%s-theme" (include "authup.server.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
True when a theme should be mounted at all.
*/}}
{{- define "authup.server.themeMounted" -}}
{{- if and .Values.server.theme.enabled (or .Values.server.theme.files .Values.server.theme.existingConfigMap) -}}
true
{{- end -}}
{{- end -}}

{{/*
Render-time validation. The chart fails loud rather than shipping a
silently-inert theme: the dominant failure mode of theming is a page that
looks exactly like an un-themed page.
*/}}
{{- define "authup.server.validateTheme" -}}
{{- if .Values.server.theme.enabled }}
{{- if not (or .Values.server.theme.files .Values.server.theme.existingConfigMap) }}
{{- fail "authup: server.theme.enabled requires server.theme.files or server.theme.existingConfigMap — an empty theme directory would render an un-themed page with no error." }}
{{- end }}
{{- if and .Values.server.theme.files .Values.server.theme.existingConfigMap }}
{{- fail "authup: set either server.theme.files or server.theme.existingConfigMap, not both — the existing ConfigMap would win and the inline files would be silently ignored." }}
{{- end }}
{{- range $path, $content := .Values.server.theme.files }}
{{- if hasPrefix "/" $path }}
{{- fail (printf "authup: server.theme.files key %q must be relative to the theme root." $path) }}
{{- end }}
{{- if contains ".." $path }}
{{- fail (printf "authup: server.theme.files key %q must not traverse out of the theme root." $path) }}
{{- end }}
{{- if contains "__" $path }}
{{- fail (printf "authup: server.theme.files key %q must not contain \"__\" — it is reserved for encoding the path separator into a ConfigMap key." $path) }}
{{- end }}
{{- /* A ConfigMap data key must match ^[A-Za-z0-9._-]+$, so a path
       carrying a space, a colon or any other character outside this set
       would flatten into an INVALID key and fail at apply time with a
       Kubernetes validation error instead of here. The set is the one the
       server's own asset handler accepts, so the chart now rejects at
       render time exactly what the server would 404 at request time. */}}
{{- if not (regexMatch "^[a-zA-Z0-9][a-zA-Z0-9._/-]*$" $path) }}
{{- fail (printf "authup: server.theme.files key %q must start with a letter or digit and contain only letters, digits, \".\", \"_\", \"-\" and \"/\"." $path) }}
{{- end }}
{{- end }}
{{- end }}
{{- if and .Values.server.theme.existingConfigMapItems (not .Values.server.theme.existingConfigMap) }}
{{- fail "authup: server.theme.existingConfigMapItems requires server.theme.existingConfigMap." }}
{{- end }}
{{- end -}}

{{- define "authup.server.provisioningConfigMapName" -}}
{{- if .Values.server.provisioning.existingConfigMap -}}
{{- include "authup.tplvalues.render" (dict "value" .Values.server.provisioning.existingConfigMap "context" $) -}}
{{- else -}}
{{- printf "%s-provisioning" (include "authup.server.fullname" .) -}}
{{- end -}}
{{- end -}}

{{- define "authup.server.configurationConfigMapName" -}}
{{- if .Values.server.existingConfigmap -}}
{{- include "authup.tplvalues.render" (dict "value" .Values.server.existingConfigmap "context" $) -}}
{{- else -}}
{{- printf "%s-configuration" (include "authup.server.fullname" .) -}}
{{- end -}}
{{- end -}}
