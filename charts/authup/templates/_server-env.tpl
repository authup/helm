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
{{- if .Values.server.provisioning.enabled }}
PROVISIONING_DIRECTORY_PATH: "/etc/authup/provisioning"
{{- end }}
LOG_DIRECTORY_PATH: "/var/log/authup"
{{- $reserved := list "DB_TYPE" "DB_HOST" "DB_PORT" "DB_USERNAME" "DB_DATABASE" "DB_PASSWORD" "PUBLIC_URL" "TRUSTED_ORIGINS" "TRUST_PROXY" "REGISTRATION_ENABLED" "PASSWORD_RECOVERY_ENABLED" "EMAIL_VERIFICATION_ENABLED" "ACCOUNT_CONSOLE_ENABLED" "MFA_ENABLED" "MFA_REQUIRED" "PROVISIONING_DIRECTORY_PATH" "LOG_DIRECTORY_PATH" "THEME_DIRECTORY_PATH" "THEME_FRAGMENTS_ENABLED" "USER_ADMIN_PASSWORD" "USER_ADMIN_PASSWORD_RESET" "CLIENT_SYSTEM_ENABLED" "CLIENT_SYSTEM_SECRET" "CLIENT_SYSTEM_SECRET_RESET" "REDIS" "SMTP" "SECRETS_ENCRYPTION_KEY" }}
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
Usage: {{ include "authup.server.secretEnv" (dict "context" $ "hook" true) }}

"hook" marks the pre-upgrade migration Job and drops REDIS and SMTP. Not
tidiness: both Secrets are ordinary release resources, and helm applies a
pre-upgrade hook BEFORE the release manifest, so the upgrade that first enables
valkey or SMTP would schedule a hook pod whose secretKeyRef target does not
exist yet (CreateContainerConfigError until the hook times out). `migration run`
builds config + logger + database only, no cache and no mail module, so neither
value is read there. USER_ADMIN_PASSWORD and CLIENT_SYSTEM_SECRET go too: the
migration builds no identity or provisioning module either, and the auth Secret
they read is itself a release resource (an upgrade dropping auth.existingSecret
for a chart-managed one creates it only AFTER the hook), on top of
CLIENT_SYSTEM_SECRET's key being conditional. The hook keeps exactly two:
DB_PASSWORD, without which the migration cannot run, and the KEK (see below).
*/}}
{{- define "authup.server.secretEnv" -}}
{{- $ctx := required "authup.server.secretEnv: call it as (dict \"context\" $ \"hook\" bool)" .context -}}
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "authup.database.secretName" $ctx }}
      key: {{ include "authup.database.passwordKey" $ctx }}
{{- if and (not .hook) (include "authup.redis.enabled" $ctx) }}
- name: REDIS
  valueFrom:
    secretKeyRef:
      name: {{ include "authup.redis.secretName" $ctx }}
      key: {{ include "authup.redis.secretKey" $ctx }}
{{- end }}
{{- if and (not .hook) (include "authup.smtp.enabled" $ctx) }}
- name: SMTP
  valueFrom:
    secretKeyRef:
      name: {{ include "authup.smtp.secretName" $ctx }}
      key: {{ include "authup.smtp.secretKey" $ctx }}
{{- end }}
{{- if not .hook }}
- name: USER_ADMIN_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "authup.auth.secretName" $ctx }}
      key: {{ $ctx.Values.auth.secretKeys.adminPasswordKey }}
{{- end }}
{{- if and (not .hook) $ctx.Values.auth.systemClientEnabled }}
- name: CLIENT_SYSTEM_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ include "authup.auth.secretName" $ctx }}
      key: {{ $ctx.Values.auth.secretKeys.systemClientSecretKey }}
{{- end }}
{{- if include "authup.auth.hasSecretsEncryptionKey" $ctx }}
{{- /* Never optional: a silently missing KEK would boot authup into
       plaintext-at-rest and defer unrecoverable decrypt failures. Kept on the
       hook for the same reason, even though its key is conditional and
       `migration run` does not read it today: a migration that ever touches a
       wrapped column must fail closed, not run without the key. The cost is
       that enabling auth.secretsEncryptionKey and server.migration.enabled in
       ONE upgrade schedules a hook pod referencing a key the release has not
       written yet. Enable a write-once KEK on its own upgrade. */}}
- name: SECRETS_ENCRYPTION_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "authup.auth.secretName" $ctx }}
      key: {{ $ctx.Values.auth.secretKeys.secretsEncryptionKeyKey }}
{{- end }}
- name: npm_config_cache
  value: /tmp/.npm-cache
{{- end -}}

{{/*
Shared volumes / volumeMounts for the server container (logs, tmp,
provisioning files, config file).
Usage: {{ include "authup.server.volumeMounts" (dict "context" $ "hook" true) }}
The `required` on .context is load-bearing: helm renders with missingkey=zero, so
a call site that passed a bare `.` would leave every guard below reading false and
emit logs+tmp only, silently dropping the config file. Failing the render is
the chart's posture everywhere else.

"hook" marks the pre-upgrade migration Job. It drops the provisioning mount,
whose ConfigMap/Secret is an ordinary release resource that helm applies AFTER
the hook: the upgrade that first sets server.provisioning.files would leave the
hook pod in ContainerCreating on a "configmap not found" until it times out, and
`migration run` never reads those files anyway (ProvisionerModule is registered
by the start command only). The writable directory stays for BOTH: under the
image's NODE_ENV=production the logger opens <writable>/http.log and
<writable>/error.log before the migration touches the database, and an
uncreatable path is a hard ENOENT failure.

The config file stays for both as well, and mounting it is not optional:
`migration run` loads authup.yml unconditionally, and the db keys
that only the file can carry (ssl, socketPath, replication, extensions, poolSize)
decide how the migration connects and what it creates. Dropping it would silently
migrate over a plaintext connection. The Job reads it from a hook-scoped copy
instead: see authup.server.configurationConfigMapName.

The theme volume rides the same flag. It used to be a pair of deployment-only
defines carved out for exactly this hook reason, which left two calling
conventions in deployment.yaml two lines apart; one mechanism is one thing to
get right. authup.server.themeEnv stays separate: it splits along a different
axis (configEnv is one define shared by the env ConfigMap and the Job's inlined
env, and THEME_* must stay in its reserved-key list either way).
*/}}
{{- define "authup.server.volumeMounts" -}}
{{- $ctx := required "authup.server.volumeMounts: call it as (dict \"context\" $ \"hook\" bool)" .context -}}
- name: logs
  mountPath: /var/log/authup
- name: tmp
  mountPath: /tmp
{{- if and (not .hook) $ctx.Values.server.provisioning.enabled (or $ctx.Values.server.provisioning.files $ctx.Values.server.provisioning.existingConfigMap $ctx.Values.server.provisioning.existingSecret) }}
- name: provisioning
  mountPath: /etc/authup/provisioning
  readOnly: true
{{- end }}
{{- if or $ctx.Values.server.configuration $ctx.Values.server.existingConfigmap }}
- name: configuration
  mountPath: /etc/authup/authup.yml
  subPath: authup.yml
  readOnly: true
{{- end }}
{{- if and (not .hook) (include "authup.server.themeMounted" $ctx) }}
- name: theme
  mountPath: {{ include "authup.server.themeMountPath" $ctx }}
  readOnly: true
{{- end }}
{{- end -}}

{{- define "authup.server.volumes" -}}
{{- $ctx := required "authup.server.volumes: call it as (dict \"context\" $ \"hook\" bool)" .context -}}
- name: logs
  emptyDir: {}
- name: tmp
  emptyDir: {}
{{- if and (not .hook) $ctx.Values.server.provisioning.enabled (or $ctx.Values.server.provisioning.files $ctx.Values.server.provisioning.existingConfigMap $ctx.Values.server.provisioning.existingSecret) }}
- name: provisioning
  {{- if $ctx.Values.server.provisioning.existingSecret }}
  secret:
    secretName: {{ include "authup.tplvalues.render" (dict "value" $ctx.Values.server.provisioning.existingSecret "context" $ctx) }}
  {{- else }}
  configMap:
    name: {{ include "authup.server.provisioningConfigMapName" $ctx }}
  {{- end }}
{{- end }}
{{- if or $ctx.Values.server.configuration $ctx.Values.server.existingConfigmap }}
- name: configuration
  configMap:
    name: {{ include "authup.server.configurationConfigMapName" (dict "context" $ctx "hook" .hook) }}
{{- end }}
{{- if and (not .hook) (include "authup.server.themeMounted" $ctx) }}
- name: theme
  configMap:
    name: {{ include "authup.server.themeConfigMapName" $ctx }}
    {{- /* Whole-volume projection on purpose: a subPath mount is frozen
           until the pod restarts, which would destroy authup's live theme
           reload. */}}
    {{- if $ctx.Values.server.theme.existingConfigMap }}
    {{- with $ctx.Values.server.theme.existingConfigMapItems }}
    items: {{- include "authup.tplvalues.render" (dict "value" . "context" $ctx) | nindent 6 }}
    {{- end }}
    {{- else }}
    items:
      {{- range $path := splitList "\n" (include "authup.server.themePaths" $ctx) }}
      - key: {{ include "authup.server.themeConfigMapKey" $path }}
        path: {{ $path }}
      {{- end }}
    {{- end }}
{{- end }}
{{- end -}}

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
{{- if and .Values.server.theme.enabled (or .Values.server.theme.files .Values.server.theme.existingConfigMap (include "authup.server.themeManifestConfigured" .)) -}}
true
{{- end -}}
{{- end -}}

{{/*
True when any structured manifest value is set, i.e. when the chart owns
theme.json instead of the operator writing it into `files` by hand.
*/}}
{{- define "authup.server.themeManifestConfigured" -}}
{{- $t := .Values.server.theme -}}
{{- if or $t.title $t.favicon $t.logo $t.logoDark $t.stylesheet $t.tokens $t.tokensDark -}}
true
{{- end -}}
{{- end -}}

{{/*
theme.json composed from the structured manifest values. Only keys the
operator actually set are emitted: authup fails the boot on an UNKNOWN
manifest key, and would also read an empty string as a real (broken) asset
reference, so a "" must never reach the file.

`version` is authup's manifest version, not the chart's: it is how a future
per-realm layout change becomes detectable instead of silent.
*/}}
{{- define "authup.server.themeManifest" -}}
{{- $ctx := . -}}
{{- $t := .Values.server.theme -}}
{{- $manifest := dict "version" 1 -}}
{{- range $key := list "title" "favicon" "logo" "logoDark" "stylesheet" -}}
{{- $value := get $t $key -}}
{{- if $value -}}
{{- $_ := set $manifest $key (include "authup.tplvalues.render" (dict "value" $value "context" $ctx)) -}}
{{- end -}}
{{- end -}}
{{- range $key := list "tokens" "tokensDark" -}}
{{- $source := get $t $key -}}
{{- if $source -}}
{{- $rendered := dict -}}
{{- range $name, $value := $source -}}
{{- $_ := set $rendered $name (include "authup.tplvalues.render" (dict "value" ($value | toString) "context" $ctx)) -}}
{{- end -}}
{{- $_ := set $manifest $key $rendered -}}
{{- end -}}
{{- end -}}
{{- toPrettyJson $manifest -}}
{{- end -}}

{{/*
Every path the chart-managed theme ConfigMap carries, newline separated.
Single source for the ConfigMap keys AND the volume's items projection, so
the two cannot diverge into a key that is stored but never mounted.
*/}}
{{- define "authup.server.themePaths" -}}
{{- $paths := list -}}
{{- if include "authup.server.themeManifestConfigured" . -}}
{{- $paths = append $paths "theme.json" -}}
{{- end -}}
{{- range $path, $content := .Values.server.theme.files -}}
{{- $paths = append $paths $path -}}
{{- end -}}
{{- $paths | join "\n" -}}
{{- end -}}

{{/*
Render-time validation. The chart fails loud rather than shipping a
silently-inert theme: the dominant failure mode of theming is a page that
looks exactly like an un-themed page.
*/}}
{{- define "authup.server.validateTheme" -}}
{{- $ctx := . }}
{{- $theme := .Values.server.theme }}
{{- $manifest := include "authup.server.themeManifestConfigured" . }}
{{- if .Values.server.theme.enabled }}
{{- if not (or $theme.files $theme.existingConfigMap $manifest) }}
{{- fail "authup: server.theme.enabled requires server.theme.files, server.theme.existingConfigMap or the structured manifest values (title / logo / tokens / ...). An empty theme directory would render an un-themed page with no error." }}
{{- end }}
{{- if and $theme.files $theme.existingConfigMap }}
{{- fail "authup: set either server.theme.files or server.theme.existingConfigMap, not both — the existing ConfigMap would win and the inline files would be silently ignored." }}
{{- end }}
{{- if and $manifest $theme.existingConfigMap }}
{{- fail "authup: the structured server.theme manifest values cannot be combined with server.theme.existingConfigMap: the ConfigMap is mounted whole, so the chart-composed theme.json would never reach the pod. Put theme.json into that ConfigMap instead." }}
{{- end }}
{{- if and $manifest (hasKey $theme.files "theme.json") }}
{{- fail "authup: server.theme.files has a \"theme.json\" key while the structured manifest values are also set. The chart composes theme.json from those values, so one of the two would be silently dropped. Use one or the other." }}
{{- end }}
{{- /* An asset reference the theme does not carry is the exact failure the
       chart exists to catch: authup answers 404 and the page renders
       un-themed, which looks identical to theming being off. Only assets/
       is served over HTTP (the theme root is deliberately unreachable, so
       theme.json cannot be fetched), hence the prefix requirement. */}}
{{- $imageExtensions := list ".svg" ".png" ".jpg" ".jpeg" ".gif" ".webp" ".avif" ".ico" }}
{{- range $key := list "favicon" "logo" "logoDark" }}
{{- $raw := get $theme $key }}
{{- if $raw }}
{{- /* Assert the RENDERED value: themeManifest tpl-renders it, so a
       template-valued path only materializes here (invariant 7). Validating
       the raw string would reject every umbrella-injected expression, since
       none of them start with "assets/". */}}
{{- $value := include "authup.tplvalues.render" (dict "value" $raw "context" $ctx) }}
{{- if not (hasPrefix "assets/" $value) }}
{{- fail (printf "authup: server.theme.%s must reference a file under \"assets/\" (got %q). assets/ is the only directory authup serves over HTTP." $key $value) }}
{{- end }}
{{- $matched := false }}
{{- range $extension := $imageExtensions }}
{{- if hasSuffix $extension (lower $value) }}{{- $matched = true }}{{- end }}
{{- end }}
{{- if not $matched }}
{{- fail (printf "authup: server.theme.%s must be an image (%s), got %q. authup returns 404 for any other type." $key (join ", " $imageExtensions) $value) }}
{{- end }}
{{- if not (hasKey ($theme.files | default dict) $value) }}
{{- fail (printf "authup: server.theme.%s references %q, which is not a key of server.theme.files. The asset would 404 and the console would render un-themed." $key $value) }}
{{- end }}
{{- end }}
{{- end }}
{{- if $theme.stylesheet }}
{{- $stylesheet := include "authup.tplvalues.render" (dict "value" $theme.stylesheet "context" $ctx) }}
{{- if not (hasPrefix "assets/" $stylesheet) }}
{{- fail (printf "authup: server.theme.stylesheet must reference a file under \"assets/\" (got %q). assets/ is the only directory authup serves over HTTP." $stylesheet) }}
{{- end }}
{{- if not (hasSuffix ".css" (lower $stylesheet)) }}
{{- fail (printf "authup: server.theme.stylesheet must be a .css file (got %q)." $stylesheet) }}
{{- end }}
{{- if not (hasKey ($theme.files | default dict) $stylesheet) }}
{{- fail (printf "authup: server.theme.stylesheet references %q, which is not a key of server.theme.files. The stylesheet would 404 and the console would render un-themed." $stylesheet) }}
{{- end }}
{{- end }}
{{- /* Mirrors authup's own manifest validation. It fails the BOOT on a bad
       token, so catching it at render time turns a crash-looping IdP into a
       failed `helm upgrade`. */}}
{{- range $key := list "tokens" "tokensDark" }}
{{- range $name, $value := (get $theme $key) }}
{{- if not (regexMatch "^--[a-z0-9-]+$" $name) }}
{{- fail (printf "authup: server.theme.%s key %q must be a lowercase CSS custom property (--foo-bar)." $key $name) }}
{{- end }}
{{- $rendered := include "authup.tplvalues.render" (dict "value" ($value | toString) "context" $ctx) }}
{{- if gt (len $rendered) 256 }}
{{- fail (printf "authup: server.theme.%s.%s exceeds the 256 character limit authup enforces on a token value." $key $name) }}
{{- end }}
{{- range $forbidden := list "}" "<" ">" ";" "@" "\\" "/*" "url(" "expression(" }}
{{- if contains $forbidden $rendered }}
{{- fail (printf "authup: server.theme.%s.%s contains %q, which authup rejects in a token value. Use server.theme.stylesheet for anything needing url() or multiple declarations." $key $name $forbidden) }}
{{- end }}
{{- end }}
{{- end }}
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

{{/*
ConfigMap carrying authup.yml for one consumer.
Usage: {{ include "authup.server.configurationConfigMapName" (dict "context" $ "hook" true) }}

"hook" resolves to the migration Job's own copy (templates/server/configmap-
migration-configuration.yaml), which is itself a pre-upgrade hook and is
therefore created before the Job. Two reasons the Job cannot share the release
ConfigMap: on the upgrade that first sets server.configuration it does not exist
yet, and on every later upgrade it still holds the PREVIOUS release's content
when the hook runs. Same reasoning that makes the Job inline configEnv.
An operator-supplied existingConfigmap is not the chart's to copy: it lives
outside the release and already exists when the hook runs.
*/}}
{{- define "authup.server.configurationConfigMapName" -}}
{{- $ctx := required "authup.server.configurationConfigMapName: call it as (dict \"context\" $ \"hook\" bool)" .context -}}
{{- if $ctx.Values.server.existingConfigmap -}}
{{- include "authup.tplvalues.render" (dict "value" $ctx.Values.server.existingConfigmap "context" $ctx) -}}
{{- else if .hook -}}
{{- printf "%s-migration-configuration" (include "authup.server.fullname" $ctx) -}}
{{- else -}}
{{- printf "%s-configuration" (include "authup.server.fullname" $ctx) -}}
{{- end -}}
{{- end -}}

{{/*
Rendered content of authup.yml. One source for the release
ConfigMap and the hook copy, so the migration cannot run against a config file
that differs from the one the server pods get.
*/}}
{{- define "authup.server.configurationContent" -}}
{{- include "authup.tplvalues.render" (dict "value" .Values.server.configuration "context" $) -}}
{{- end -}}
