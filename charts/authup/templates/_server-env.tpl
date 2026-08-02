{{/*
Non-secret server-core environment as a YAML map. Single source for the env
ConfigMap AND the migration Job (which inlines it so a pre-upgrade hook never
runs against the previous release's ConfigMap).
Strict-boolean variables are always quoted: authup crashes the boot on
unparsable boolean strings by design.
*/}}
{{- define "authup.server.configEnv" -}}
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
{{- $reserved := list "DB_TYPE" "DB_HOST" "DB_PORT" "DB_USERNAME" "DB_DATABASE" "DB_PASSWORD" "PUBLIC_URL" "TRUSTED_ORIGINS" "TRUST_PROXY" "REGISTRATION_ENABLED" "PASSWORD_RECOVERY_ENABLED" "EMAIL_VERIFICATION_ENABLED" "MFA_ENABLED" "MFA_REQUIRED" "USER_ADMIN_PASSWORD" "USER_ADMIN_PASSWORD_RESET" "CLIENT_SYSTEM_ENABLED" "CLIENT_SYSTEM_SECRET" "CLIENT_SYSTEM_SECRET_RESET" "REDIS" "SMTP" "SECRETS_ENCRYPTION_KEY" }}
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
