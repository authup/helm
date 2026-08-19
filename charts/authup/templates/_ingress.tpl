{{/*
Shared Ingress renderer.
Usage: {{ include "authup.ingress" (dict "context" $ "component" "server" "name" (include "authup.server.fullname" $) "ingress" .Values.server.ingress "serviceName" ... "servicePort" ...) }}
*/}}
{{- define "authup.ingress" -}}
{{- $ctx := .context -}}
{{- $ing := .ingress -}}
{{- $hostname := "" -}}
{{- if $ing.hostname -}}
{{- $hostname = include "authup.tplvalues.render" (dict "value" $ing.hostname "context" $ctx) -}}
{{- end -}}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ .name }}
  namespace: {{ include "authup.namespace" $ctx | quote }}
  labels: {{- include "authup.labels" (dict "context" $ctx "component" .component) | nindent 4 }}
  annotations:
    {{- include "authup.annotations" (dict "context" $ctx) | nindent 4 }}
    {{- if $ing.certManager }}
    kubernetes.io/tls-acme: "true"
    {{- end }}
    {{- if $ing.annotations }}
    {{- include "authup.tplvalues.render" (dict "value" $ing.annotations "context" $ctx) | nindent 4 }}
    {{- end }}
spec:
  {{- if $ing.ingressClassName }}
  ingressClassName: {{ $ing.ingressClassName | quote }}
  {{- end }}
  rules:
    {{- if $hostname }}
    - host: {{ $hostname | quote }}
      http:
        paths:
          - path: {{ $ing.path }}
            pathType: {{ $ing.pathType }}
            backend:
              service:
                name: {{ .serviceName }}
                port:
                  name: http
          {{- if $ing.extraPaths }}
          {{- include "authup.tplvalues.render" (dict "value" $ing.extraPaths "context" $ctx) | nindent 10 }}
          {{- end }}
    {{- end }}
    {{- range $ing.extraHosts }}
    - host: {{ include "authup.tplvalues.render" (dict "value" .name "context" $ctx) | quote }}
      http:
        paths:
          - path: {{ .path | default "/" }}
            pathType: {{ .pathType | default "Prefix" }}
            backend:
              service:
                name: {{ $.serviceName }}
                port:
                  name: http
    {{- end }}
    {{- if $ing.extraRules }}
    {{- include "authup.tplvalues.render" (dict "value" $ing.extraRules "context" $ctx) | nindent 4 }}
    {{- end }}
  {{- if or (and $hostname (or $ing.tls $ing.certManager)) $ing.extraTls }}
  tls:
    {{- if and $hostname (or $ing.tls $ing.certManager) }}
    - hosts:
        - {{ $hostname | quote }}
      {{- /* Derived from the component name, not the hostname: a wildcard host
             would produce an invalid Secret name, and a shared hostname across
             server + ui would make two ingresses fight over one secret. */}}
      secretName: {{ printf "%s-tls" .name | quote }}
    {{- end }}
    {{- if $ing.extraTls }}
    {{- include "authup.tplvalues.render" (dict "value" $ing.extraTls "context" $ctx) | nindent 4 }}
    {{- end }}
  {{- end }}
{{- end -}}

{{/*
Shared Gateway API HTTPRoute renderer.
*/}}
{{- define "authup.httproute" -}}
{{- $ctx := .context -}}
{{- $route := .route -}}
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{ .name }}
  namespace: {{ include "authup.namespace" $ctx | quote }}
  labels: {{- include "authup.labels" (dict "context" $ctx "component" .component) | nindent 4 }}
  annotations:
    {{- include "authup.annotations" (dict "context" $ctx) | nindent 4 }}
    {{- if $route.annotations }}
    {{- include "authup.tplvalues.render" (dict "value" $route.annotations "context" $ctx) | nindent 4 }}
    {{- end }}
spec:
  {{- if $route.parentRefs }}
  parentRefs: {{- include "authup.tplvalues.render" (dict "value" $route.parentRefs "context" $ctx) | nindent 4 }}
  {{- end }}
  {{- $hostnames := $route.hostnames }}
  {{- if not $hostnames }}
  {{- $derived := include "authup.urlOrigin" .publicUrl }}
  {{- if $derived }}
  {{- /* Gateway API hostnames must not carry a port. */}}
  {{- $hostnames = list (regexReplaceAll ":[0-9]+$" (regexReplaceAll "^https?://" $derived "") "") }}
  {{- end }}
  {{- end }}
  {{- if $hostnames }}
  hostnames:
    {{- range $hostnames }}
    - {{ include "authup.tplvalues.render" (dict "value" . "context" $ctx) | quote }}
    {{- end }}
  {{- end }}
  rules:
    - backendRefs:
        - name: {{ .serviceName }}
          port: {{ .servicePort }}
      {{- if $route.matches }}
      matches: {{- include "authup.tplvalues.render" (dict "value" $route.matches "context" $ctx) | nindent 8 }}
      {{- end }}
      {{- if $route.filters }}
      filters: {{- include "authup.tplvalues.render" (dict "value" $route.filters "context" $ctx) | nindent 8 }}
      {{- end }}
{{- end -}}
