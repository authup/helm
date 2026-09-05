{{/* Non-secret environment shared by one split console workload. */}}
{{- define "authup.console.configEnv" -}}
{{- $ctx := required "authup.console.configEnv: context is required" .context -}}
{{- $values := required "authup.console.configEnv: values are required" .values -}}
{{- $portName := printf "%s_CONSOLE_PORT" .prefix -}}
{{- $publicUrl := include "authup.server.publicUrl" $ctx -}}
{{- if $publicUrl }}
PUBLIC_URL: {{ $publicUrl | quote }}
{{- end }}
INTERNAL_URL: {{ printf "http://%s:%v" (include "authup.server.fullname" $ctx) $ctx.Values.server.service.ports.http | quote }}
{{- $trustedOrigins := include "authup.server.trustedOrigins" $ctx }}
{{- if $trustedOrigins }}
TRUSTED_ORIGINS: {{ $trustedOrigins | quote }}
{{- end }}
ADMIN_CONSOLE_ENABLED: {{ $ctx.Values.adminConsole.enabled | toString | quote }}
ACCOUNT_CONSOLE_ENABLED: {{ $ctx.Values.accountConsole.enabled | toString | quote }}
{{ $portName }}: {{ $values.containerPorts.http | toString | quote }}
{{- if include "authup.server.themeMounted" $ctx }}
{{ include "authup.server.themeEnv" $ctx }}
{{- end }}
{{- $reserved := list "PUBLIC_URL" "INTERNAL_URL" "TRUSTED_ORIGINS" "ADMIN_CONSOLE_ENABLED" "ACCOUNT_CONSOLE_ENABLED" $portName "THEME_DIRECTORY_PATH" "THEME_FRAGMENTS_ENABLED" }}
{{- range $key, $value := $values.config }}
{{- if has $key $reserved }}
{{- fail (printf "authup: %s.config.%s collides with a first-class chart value; set the dedicated value instead." $.key $key) }}
{{- end }}
{{ $key }}: {{ include "authup.tplvalues.render" (dict "value" ($value | toString) "context" $ctx) | quote }}
{{- end }}
{{- end -}}

{{/* Configuration, theme and temporary mounts used by split consoles. */}}
{{- define "authup.console.volumeMounts" -}}
{{- $ctx := required "authup.console.volumeMounts: context is required" .context -}}
- name: tmp
  mountPath: /tmp
{{- if or $ctx.Values.server.configuration $ctx.Values.server.existingConfigmap }}
- name: configuration
  mountPath: /etc/authup/authup.yml
  subPath: authup.yml
  readOnly: true
{{- end }}
{{- if include "authup.server.themeMounted" $ctx }}
- name: theme
  mountPath: {{ include "authup.server.themeMountPath" $ctx }}
  readOnly: true
{{- end }}
{{- end -}}

{{- define "authup.console.volumes" -}}
{{- $ctx := required "authup.console.volumes: context is required" .context -}}
- name: tmp
  emptyDir: {}
{{- if or $ctx.Values.server.configuration $ctx.Values.server.existingConfigmap }}
- name: configuration
  configMap:
    name: {{ include "authup.server.configurationConfigMapName" (dict "context" $ctx "hook" false) }}
{{- end }}
{{- if include "authup.server.themeMounted" $ctx }}
- name: theme
  configMap:
    name: {{ include "authup.server.themeConfigMapName" $ctx }}
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
