{{/*
Database dispatch helpers. Consuming templates never know whether the built-in
postgresql, the built-in mysql, or an external database is active.
*/}}

{{- define "authup.database.type" -}}
{{- if .Values.postgresql.enabled -}}
postgres
{{- else if .Values.mysql.enabled -}}
mysql
{{- else -}}
{{- .Values.database.type -}}
{{- end -}}
{{- end -}}

{{- define "authup.database.host" -}}
{{- if .Values.postgresql.enabled -}}
{{- include "authup.postgresql.fullname" . -}}
{{- else if .Values.mysql.enabled -}}
{{- include "authup.mysql.fullname" . -}}
{{- else -}}
{{- include "authup.tplvalues.render" (dict "value" .Values.externalDatabase.host "context" $) -}}
{{- end -}}
{{- end -}}

{{- define "authup.database.port" -}}
{{- if .Values.postgresql.enabled -}}
5432
{{- else if .Values.mysql.enabled -}}
3306
{{- else if .Values.externalDatabase.port -}}
{{- .Values.externalDatabase.port -}}
{{- else if eq .Values.database.type "mysql" -}}
3306
{{- else -}}
5432
{{- end -}}
{{- end -}}

{{- define "authup.database.user" -}}
{{- if .Values.postgresql.enabled -}}
{{- .Values.postgresql.auth.username -}}
{{- else if .Values.mysql.enabled -}}
{{- .Values.mysql.auth.username -}}
{{- else -}}
{{- .Values.externalDatabase.user -}}
{{- end -}}
{{- end -}}

{{- define "authup.database.name" -}}
{{- if .Values.postgresql.enabled -}}
{{- .Values.postgresql.auth.database -}}
{{- else if .Values.mysql.enabled -}}
{{- .Values.mysql.auth.database -}}
{{- else -}}
{{- .Values.externalDatabase.database -}}
{{- end -}}
{{- end -}}

{{- define "authup.database.secretName" -}}
{{- if .Values.postgresql.enabled -}}
{{- include "authup.postgresql.fullname" . -}}
{{- else if .Values.mysql.enabled -}}
{{- include "authup.mysql.fullname" . -}}
{{- else if .Values.externalDatabase.existingSecret -}}
{{- include "authup.tplvalues.render" (dict "value" .Values.externalDatabase.existingSecret "context" $) -}}
{{- else -}}
{{- printf "%s-externaldb" (include "authup.fullname" .) -}}
{{- end -}}
{{- end -}}

{{- define "authup.database.passwordKey" -}}
{{- if or .Values.postgresql.enabled .Values.mysql.enabled -}}
password
{{- else if .Values.externalDatabase.existingSecret -}}
{{- .Values.externalDatabase.existingSecretPasswordKey -}}
{{- else -}}
password
{{- end -}}
{{- end -}}

{{/*
Cache (Valkey / external Redis) helpers. authup consumes ONE env var, REDIS,
holding a full connection URL. Because the URL embeds the password it always
lives in a Secret.
*/}}

{{- define "authup.redis.enabled" -}}
{{- if or .Values.valkey.enabled .Values.externalRedis.url .Values.externalRedis.host .Values.externalRedis.existingSecret -}}true{{- end -}}
{{- end -}}

{{- define "authup.redis.secretName" -}}
{{- if .Values.valkey.enabled -}}
{{- include "authup.valkey.fullname" . -}}
{{- else if .Values.externalRedis.existingSecret -}}
{{- include "authup.tplvalues.render" (dict "value" .Values.externalRedis.existingSecret "context" $) -}}
{{- else -}}
{{- printf "%s-redis" (include "authup.fullname" .) -}}
{{- end -}}
{{- end -}}

{{- define "authup.redis.secretKey" -}}
{{- if .Values.valkey.enabled -}}
connection-string
{{- else if .Values.externalRedis.existingSecret -}}
{{- .Values.externalRedis.existingSecretKey -}}
{{- else -}}
redis-connection-string
{{- end -}}
{{- end -}}
