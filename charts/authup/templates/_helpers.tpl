{{/*
Expand the name of the chart.
*/}}
{{- define "authup.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Release-scoped fully qualified name. Every resource name derives from this.
*/}}
{{- define "authup.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Per-component names. The base is truncated BEFORE suffixing so the component
suffix always survives: otherwise a 63-char fullname would collapse every
component onto one identical name.

The budget is DERIVED from the suffix, not hardcoded, because the ceiling that
actually bites is 63 and not the 253 a ConfigMap allows: a Service name is a
DNS-1035 label, and a Job name is copied into the job-name pod labels where a
label value stops at 63. A flat `trunc 52` let the 13-character
`-admin-console` suffix render a 66-character Service that the API server
rejects outright, so a long release name could not install at all.

`min 52` is load-bearing, not decoration. The derived budget is WIDER than 52
for short suffixes, and widening would RENAME resources on releases whose
fullname lands between 53 and 55 characters. A renamed Secret carrying
`helm.sh/resource-policy: keep` means the old one is orphaned and a new
admin password and system-client secret are generated: a silent credential
rotation on upgrade. The budget may therefore only ever tighten, which by
construction touches only names that are already too long to exist.

Usage: {{ include "authup.component.fullname" (dict "context" $ "suffix" "server") }}
*/}}
{{- define "authup.component.fullname" -}}
{{- $suffix := .suffix -}}
{{- $budget := min 52 (sub 63 (add1 (len $suffix))) | int -}}
{{- printf "%s-%s" (include "authup.fullname" .context | trunc $budget | trimSuffix "-") $suffix -}}
{{- end -}}

{{- define "authup.server.fullname" -}}
{{- include "authup.component.fullname" (dict "context" . "suffix" "server") -}}
{{- end -}}

{{- define "authup.adminConsole.fullname" -}}
{{- include "authup.component.fullname" (dict "context" . "suffix" "admin-console") -}}
{{- end -}}

{{- define "authup.authConsole.fullname" -}}
{{- include "authup.component.fullname" (dict "context" . "suffix" "auth-console") -}}
{{- end -}}

{{- define "authup.accountConsole.fullname" -}}
{{- include "authup.component.fullname" (dict "context" . "suffix" "account-console") -}}
{{- end -}}

{{- define "authup.worker.fullname" -}}
{{- include "authup.component.fullname" (dict "context" . "suffix" "worker") -}}
{{- end -}}

{{- define "authup.postgresql.fullname" -}}
{{- include "authup.component.fullname" (dict "context" . "suffix" "postgresql") -}}
{{- end -}}

{{- define "authup.mysql.fullname" -}}
{{- include "authup.component.fullname" (dict "context" . "suffix" "mysql") -}}
{{- end -}}

{{- define "authup.valkey.fullname" -}}
{{- include "authup.component.fullname" (dict "context" . "suffix" "valkey") -}}
{{- end -}}

{{/*
Namespace, honoring namespaceOverride.
*/}}
{{- define "authup.namespace" -}}
{{- default .Release.Namespace .Values.namespaceOverride -}}
{{- end -}}

{{/*
Chart name and version label value.
*/}}
{{- define "authup.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Render a value that may contain templates.
Usage: {{ include "authup.tplvalues.render" (dict "value" .Values.<path> "context" $) }}
*/}}
{{- define "authup.tplvalues.render" -}}
{{- $value := typeIs "string" .value | ternary .value (toYaml .value) -}}
{{- if contains "{{" (toString $value) -}}
{{- tpl $value .context -}}
{{- else -}}
{{- $value -}}
{{- end -}}
{{- end -}}

{{/*
Boolean that may arrive as a tpl-rendered string, so an umbrella chart can drive
it from one of its own switches. Returns "true" (truthy) or "" (falsy).

Strict on purpose. The schema no longer rejects a string here, and a rendered
"false" is a NON-EMPTY string, i.e. truthy to a Go template `if`: a lenient
reader would create the resource exactly when the parent switched it off.
Anything that is not true/false/"" fails the render instead.
Usage: {{ if (include "authup.flag" (dict "value" .Values.server.route.enabled "context" $ "key" "server.route.enabled")) }}
*/}}
{{- define "authup.flag" -}}
{{- $rendered := include "authup.tplvalues.render" (dict "value" .value "context" .context) | trim -}}
{{- $value := lower $rendered -}}
{{- if eq $value "true" -}}
true
{{- else if not (or (eq $value "false") (eq $value "")) -}}
{{- fail (printf "authup: %s must be true or false (or a template rendering to one of them), got %q." .key $rendered) -}}
{{- end -}}
{{- end -}}

{{/*
Standard labels.
Usage: {{ include "authup.labels" (dict "context" $ "component" "server") }}
*/}}
{{- define "authup.labels" -}}
app.kubernetes.io/name: {{ include "authup.name" .context }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
app.kubernetes.io/managed-by: {{ .context.Release.Service }}
helm.sh/chart: {{ include "authup.chart" .context }}
{{- if .context.Chart.AppVersion }}
app.kubernetes.io/version: {{ .context.Chart.AppVersion | quote }}
{{- end }}
{{- if .component }}
app.kubernetes.io/component: {{ .component }}
{{- end }}
{{- if .context.Values.commonLabels }}
{{ include "authup.tplvalues.render" (dict "value" .context.Values.commonLabels "context" .context) }}
{{- end }}
{{- end -}}

{{/*
Selector labels. Immutable: name + instance (+ component) only — user labels
never reach selectors.
Usage: {{ include "authup.matchLabels" (dict "context" $ "component" "server") }}
*/}}
{{- define "authup.matchLabels" -}}
app.kubernetes.io/name: {{ include "authup.name" .context }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
{{- if .component }}
app.kubernetes.io/component: {{ .component }}
{{- end }}
{{- end -}}

{{/*
Common annotations applied to every object.
*/}}
{{- define "authup.annotations" -}}
{{- if .context.Values.commonAnnotations -}}
{{ include "authup.tplvalues.render" (dict "value" .context.Values.commonAnnotations "context" .context) }}
{{- end -}}
{{- end -}}

{{/*
Full image reference from an image root, honoring global.imageRegistry and digest.
Usage: {{ include "authup.image" (dict "imageRoot" .Values.image "global" .Values.global "chart" .Chart) }}
*/}}
{{- define "authup.image" -}}
{{- $registry := .imageRoot.registry -}}
{{- if and .global .global.imageRegistry -}}
{{- $registry = .global.imageRegistry -}}
{{- end -}}
{{- $repository := .imageRoot.repository -}}
{{- $ref := $repository -}}
{{- if $registry -}}
{{- $ref = printf "%s/%s" $registry $repository -}}
{{- end -}}
{{- if .imageRoot.digest -}}
{{- printf "%s@%s" $ref .imageRoot.digest -}}
{{- else -}}
{{- $tag := .imageRoot.tag | default .chart.AppVersion -}}
{{- printf "%s:%s" $ref $tag -}}
{{- end -}}
{{- end -}}

{{/*
The authup application image.
*/}}
{{- define "authup.appImage" -}}
{{- include "authup.image" (dict "imageRoot" .Values.image "global" .Values.global "chart" .Chart) -}}
{{- end -}}

{{/*
imagePullSecrets block merging global and per-image secrets.
Usage: {{ include "authup.imagePullSecrets" . }}
*/}}
{{- define "authup.imagePullSecrets" -}}
{{- $secrets := list -}}
{{- range ((.Values.global).imagePullSecrets) -}}
{{- if kindIs "map" . -}}
{{- $secrets = append $secrets .name -}}
{{- else -}}
{{- $secrets = append $secrets . -}}
{{- end -}}
{{- end -}}
{{- range .Values.image.pullSecrets -}}
{{- if kindIs "map" . -}}
{{- $secrets = append $secrets .name -}}
{{- else -}}
{{- $secrets = append $secrets . -}}
{{- end -}}
{{- end -}}
{{- $secrets = $secrets | uniq -}}
{{- if $secrets }}
imagePullSecrets:
{{- range $secrets }}
  - name: {{ include "authup.tplvalues.render" (dict "value" . "context" $) }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
ServiceAccount name.
*/}}
{{- define "authup.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "authup.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Pod anti-affinity preset.
Usage: {{ include "authup.podAntiAffinity" (dict "context" $ "component" "server" "preset" .Values.server.podAntiAffinityPreset) }}
*/}}
{{- define "authup.podAntiAffinity" -}}
{{- if eq .preset "hard" }}
podAntiAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
    - topologyKey: kubernetes.io/hostname
      labelSelector:
        matchLabels: {{- include "authup.matchLabels" (dict "context" .context "component" .component) | nindent 10 }}
{{- else if eq .preset "soft" }}
podAntiAffinity:
  preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 1
      podAffinityTerm:
        topologyKey: kubernetes.io/hostname
        labelSelector:
          matchLabels: {{- include "authup.matchLabels" (dict "context" .context "component" .component) | nindent 12 }}
{{- end }}
{{- end -}}

{{/*
Topology spread constraints with the pod's selector labels defaulted in.
Usage: {{ include "authup.topologySpreadConstraints" (dict "context" $ "component" "server" "constraints" .Values.server.topologySpreadConstraints) }}
*/}}
{{- define "authup.topologySpreadConstraints" -}}
{{- $out := list -}}
{{- range .constraints -}}
{{- $c := . -}}
{{- if not $c.labelSelector -}}
{{- $c = merge (dict "labelSelector" (dict "matchLabels" (include "authup.matchLabels" (dict "context" $.context "component" $.component) | fromYaml))) $c -}}
{{- end -}}
{{- $out = append $out $c -}}
{{- end -}}
{{- toYaml $out -}}
{{- end -}}

{{/*
Render a security context map without its "enabled" key.
*/}}
{{- define "authup.securityContext" -}}
{{- omit . "enabled" | toYaml -}}
{{- end -}}

{{/*
Storage class honoring the global default.
*/}}
{{- define "authup.storageClass" -}}
{{- $class := .persistence.storageClass -}}
{{- if and .global .global.defaultStorageClass -}}
{{- $class = .global.defaultStorageClass -}}
{{- end -}}
{{- if $class }}
storageClassName: {{ $class | quote }}
{{- end }}
{{- end -}}
