<div align="center">

[<img src="https://raw.githubusercontent.com/authup/helm/master/assets/icon.svg" width="96" alt="Authup logo">](https://authup.org)

</div>

# authup

![Version](https://img.shields.io/badge/Version-0.4.1?style=flat-square&color=informational) <!-- x-release-please-version -->
![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.0.0-beta.65](https://img.shields.io/badge/AppVersion-1.0.0--beta.65-informational?style=flat-square)

Authup is an authentication & authorization system. This chart deploys its combined or split API, console and worker roles, with optional built-in PostgreSQL, MySQL and Valkey instances. It runs Authup v1.0.0-beta.64's role-based
CLI topology:

- one combined API and console workload by default (`start`)
- optional split API (`start core`) plus auth, admin and account console
  workloads (`start console <name>`), enabled with `server.splitConsoles=true`
- an optional dedicated background worker (`start worker`)
- optional single-instance **PostgreSQL**, **MySQL** or **Valkey** built-in
  instances on docker-official images, a convenience for dev and small
  deployments, not the production database story.

> This chart is pre-1.0: breaking changes land on the middle version digit and
> are documented in [BREAKING.md](./BREAKING.md). Pin your chart version.

## Installing

```bash
helm repo add authup https://helm.authup.org
helm install authup authup/authup

# or via OCI
helm install authup oci://ghcr.io/authup/helm/authup
```

The default install starts the combined server and a built-in PostgreSQL.
Retrieve the generated admin password:

```bash
kubectl get secret authup -o jsonpath='{.data.admin-password}' | base64 -d
```

## Typical production values

```yaml
server:
  publicUrl: https://auth.example.com
  ingress:
    enabled: true
    hostname: auth.example.com
    tls: true
  migration:
    enabled: true

worker:
  enabled: true

postgresql:
  enabled: false
externalDatabase:
  host: postgres.example.internal
  user: authup
  database: authup
  existingSecret: my-db-secret

valkey:
  enabled: true

auth:
  existingSecret: my-authup-secret   # admin-password (+ optional system-client-secret, secrets-encryption-key)
```

`PUBLIC_URL` is derived from `server.ingress` when it is not set directly.
The combined server, split consoles and API must share this public origin.
Split Ingress resources use ingress-nginx rewrites for `/console/auth`,
`/console/admin` and `/console/account`; Gateway API HTTPRoutes express the
same topology with portable `URLRewrite` filters.

To scale or isolate roles independently while keeping one browser origin:

```yaml
server:
  publicUrl: https://auth.example.com
  splitConsoles: true
  ingress:
    enabled: true
    hostname: auth.example.com
    tls: true

authConsole:
  ingress:
    enabled: true
adminConsole:
  enabled: true
  ingress:
    enabled: true
accountConsole:
  enabled: true
  ingress:
    enabled: true
```

The split auth console is required because it owns the login flow. Disable the
admin or account console independently when those surfaces are not needed. The
public URL must remain at the origin root; split mode reserves the `/console/*`
prefixes shown above.

Notable operational facts (enforced or warned about by the chart):

- **A database is mandatory.** The published image cannot fall back to sqlite.
- **`server.replicaCount > 1` requires a cache** (built-in Valkey or
  `externalRedis`): authorization codes, token revocations and MFA challenges
  are cache-backed and break across replicas otherwise.
- **`PUBLIC_URL` is permanent.** Changing it breaks enrolled WebAuthn
  credentials and the OIDC issuer.
- **`auth.secretsEncryptionKey` is write-once.** The chart never generates it;
  set it deliberately and back it up.
- **Configuration is mounted at `/etc/authup/authup.yml`.** Provisioning files
  live under `/etc/authup/provisioning`; file logs use `/var/log/authup`.
- **The migration Job is upgrade-only.** Fresh installs let the server create
  its database after built-in database resources become ready.
- The long tail of Authup options is available via `server.config` (plain
  env name/value pairs), `server.extraEnvVars`, or a mounted
  `server.configuration` file. See the
  [Authup configuration reference](https://authup.org).

## Theming the served consoles

The served consoles (the auth pages, `/console/admin` and `/console/account`) are rebranded
from a directory the chart mounts read-only. Set the manifest as values and the
chart composes `theme.json` for you; `files` carries the assets it references:

```yaml
server:
  theme:
    enabled: true
    title: Sign in to ACME
    logo: assets/logo.svg
    stylesheet: assets/theme.css
    tokens:
      # the accent the whole primary palette is mixed from
      --authup-periwinkle: "#c0392b"
      --authup-surface-card: "#ffffff"
    tokensDark:
      --authup-surface-card: "#201e1d"
    files:
      assets/logo.svg: |
        <svg xmlns="http://www.w3.org/2000/svg" ...></svg>
      assets/theme.css: |
        .a-auth-shell-card { border: 1px solid var(--authup-surface-border); }
```

A colour in `tokens` wins in dark mode too, so surface colours belong in both
maps. The chart rejects at render time what Authup rejects at boot or answers
with a 404: an asset outside `assets/`, an asset no file provides, a token name
that is not a lowercase custom property, and a token value carrying `url(` or
`;`. Only `assets/` is served over HTTP, so `theme.json` is unreachable by
construction.

`existingConfigMap` replaces the whole mechanism when you need binary assets
(`binaryData`); it is mounted whole, so it must carry `theme.json` itself and
cannot be combined with the manifest values. `fragmentsEnabled` splices
`fragments/head.html` into the console `<head>` verbatim: raw operator markup
on the origin that holds your users' session cookies, hence opt-in.

> The theme directory is as sensitive as the config file: CSS there can restyle
> or cover the OAuth2 consent buttons. Never source it from somewhere a tenant
> or a lower-privileged CI job can write.

Theming is experimental upstream: the directory layout and the `theme*` options
may change in an Authup minor release. See the
[Authup theming guide](https://authup.org/guide/deployment/theming.html).

## GitOps / ArgoCD

The generate-once-keep-forever behavior of empty passwords relies on helm's
`lookup`, which is inert under `helm template` and ArgoCD-style renders: every
sync would apply a fresh random value, roll the pods through the checksum
annotations, and desync the stored Secret from the live credential. When
deploying via GitOps, always set explicit credential values or reference
`*.existingSecret` — the chart prints a NOTES warning whenever generated
credentials are in play.

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| tada5hi |  | <https://github.com/tada5hi> |

## Requirements

Kubernetes: `>=1.25.0-0`

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| accountConsole.affinity | object | `{}` | Affinity (overrides the anti-affinity preset when set) |
| accountConsole.args | list | `[]` | Override the container args |
| accountConsole.autoscaling.hpa.enabled | bool | `false` | Enable HPA for the account console |
| accountConsole.autoscaling.hpa.maxReplicas | int | `5` | Maximum replicas |
| accountConsole.autoscaling.hpa.minReplicas | int | `2` | Minimum replicas |
| accountConsole.autoscaling.hpa.targetCPU | int | `75` | Target CPU utilization percentage |
| accountConsole.autoscaling.hpa.targetMemory | string | `""` | Target memory utilization percentage |
| accountConsole.command | list | `[]` | Override the container command |
| accountConsole.config | object | `{}` | Extra environment variables rendered literally into the env ConfigMap |
| accountConsole.containerPorts.http | int | `3022` | Account console listener port |
| accountConsole.containerSecurityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"enabled":true,"readOnlyRootFilesystem":false,"runAsNonRoot":false,"runAsUser":0,"seccompProfile":{"type":"RuntimeDefault"}}` | Container security context (same root-image caveat as the server) |
| accountConsole.customLivenessProbe | object | `{}` | Custom liveness probe |
| accountConsole.customReadinessProbe | object | `{}` | Custom readiness probe |
| accountConsole.customStartupProbe | object | `{}` | Custom startup probe |
| accountConsole.disableRestartOnChanges | bool | `false` | Disable the checksum annotations that roll pods on config changes |
| accountConsole.enabled | bool | `true` | Enable the account console and deploy it separately in split-console mode |
| accountConsole.extraEnvVars | list | `[]` | Extra environment variables for the account console container |
| accountConsole.extraEnvVarsCM | string | `""` | Extra ConfigMap with environment variables (tpl-rendered name) |
| accountConsole.extraEnvVarsSecret | string | `""` | Extra Secret with environment variables (tpl-rendered name) |
| accountConsole.extraVolumeMounts | list | `[]` | Extra volume mounts (tpl-rendered) |
| accountConsole.extraVolumes | list | `[]` | Extra volumes (tpl-rendered) |
| accountConsole.hostAliases | list | `[]` | Pod host aliases |
| accountConsole.ingress.annotations | object | `{}` | Ingress annotations (tpl-rendered; use-regex and rewrite-target are chart-owned) |
| accountConsole.ingress.certManager | bool | `false` | Request a cert-manager certificate (adds kubernetes.io/tls-acme) |
| accountConsole.ingress.enabled | bool | `false` | Enable ingress-nginx routing for the split account console (requires server.ingress.enabled) |
| accountConsole.ingress.extraPaths | list | `[]` | Extra paths for the primary host |
| accountConsole.ingress.extraRules | list | `[]` | Full custom rules (tpl-rendered; appended after the generated rules) |
| accountConsole.ingress.extraTls | list | `[]` | Extra TLS entries |
| accountConsole.ingress.hostname | string | `""` | Ingress hostname (tpl-rendered; defaults to server.ingress.hostname) |
| accountConsole.ingress.ingressClassName | string | `""` | Ingress class name |
| accountConsole.ingress.tls | bool | `false` | Enable TLS for the hostname |
| accountConsole.initContainers | list | `[]` | Init containers (tpl-rendered) |
| accountConsole.lifecycleHooks | object | `{}` | Container lifecycle hooks |
| accountConsole.livenessProbe.enabled | bool | `true` | Enable the liveness probe |
| accountConsole.livenessProbe.failureThreshold | int | `3` |  |
| accountConsole.livenessProbe.initialDelaySeconds | int | `0` |  |
| accountConsole.livenessProbe.periodSeconds | int | `30` |  |
| accountConsole.livenessProbe.successThreshold | int | `1` |  |
| accountConsole.livenessProbe.timeoutSeconds | int | `5` |  |
| accountConsole.networkPolicy.allowExternal | bool | `true` | Allow ingress from anywhere |
| accountConsole.networkPolicy.allowExternalEgress | bool | `true` | Allow all egress |
| accountConsole.networkPolicy.enabled | bool | `false` | Create a NetworkPolicy for the account console |
| accountConsole.networkPolicy.extraEgress | list | `[]` | Extra egress rules |
| accountConsole.networkPolicy.extraIngress | list | `[]` | Extra ingress rules |
| accountConsole.networkPolicy.ingressNSMatchLabels | object | `{}` | Namespace labels allowed to connect when allowExternal is false |
| accountConsole.networkPolicy.ingressPodMatchLabels | object | `{}` | Pod labels allowed to connect when allowExternal is false |
| accountConsole.nodeSelector | object | `{}` | Node selector |
| accountConsole.pdb.create | bool | `false` | Create a PodDisruptionBudget for the account console |
| accountConsole.pdb.maxUnavailable | string | `""` | Maximum unavailable pods (defaults to 1 when both are empty) |
| accountConsole.pdb.minAvailable | string | `""` | Minimum available pods |
| accountConsole.podAnnotations | object | `{}` | Pod annotations (tpl-rendered) |
| accountConsole.podAntiAffinityPreset | string | `"soft"` | Pod anti-affinity preset: soft, hard or "" |
| accountConsole.podLabels | object | `{}` | Pod labels (tpl-rendered) |
| accountConsole.podSecurityContext | object | `{"enabled":true,"fsGroup":1000}` | Pod security context |
| accountConsole.priorityClassName | string | `""` | Priority class name |
| accountConsole.readinessProbe.enabled | bool | `true` | Enable the readiness probe |
| accountConsole.readinessProbe.failureThreshold | int | `3` |  |
| accountConsole.readinessProbe.initialDelaySeconds | int | `0` |  |
| accountConsole.readinessProbe.periodSeconds | int | `10` |  |
| accountConsole.readinessProbe.successThreshold | int | `1` |  |
| accountConsole.readinessProbe.timeoutSeconds | int | `5` |  |
| accountConsole.replicaCount | int | `1` | Number of account console replicas |
| accountConsole.resources | object | `{"limits":{"memory":"512Mi"},"requests":{"cpu":"100m","memory":"256Mi"}}` | Account console container resources |
| accountConsole.revisionHistoryLimit | int | `3` | Deployment revision history limit |
| accountConsole.route.annotations | object | `{}` | HTTPRoute annotations |
| accountConsole.route.enabled | bool | `false` | Create a Gateway API HTTPRoute for the account console (requires server.route.enabled; tpl-rendered: a string rendering to "true" enables it, so an umbrella chart can drive this from one of its own switches; "false" and "" disable it, anything else fails the render) |
| accountConsole.route.hostnames | list | `[]` | Route hostnames ([] = derived from server.publicUrl) |
| accountConsole.route.parentRefs | list | `[]` | Gateway parentRefs |
| accountConsole.schedulerName | string | `""` | Scheduler name |
| accountConsole.service.annotations | object | `{}` | Service annotations (tpl-rendered) |
| accountConsole.service.clusterIP | string | `""` | Static cluster IP |
| accountConsole.service.externalTrafficPolicy | string | `"Cluster"` | External traffic policy |
| accountConsole.service.extraPorts | list | `[]` | Extra service ports |
| accountConsole.service.loadBalancerIP | string | `""` | LoadBalancer IP |
| accountConsole.service.loadBalancerSourceRanges | list | `[]` | LoadBalancer source ranges |
| accountConsole.service.nodePorts.http | string | `""` | Node port ("" = auto-assign) |
| accountConsole.service.ports.http | int | `3022` | Service HTTP port |
| accountConsole.service.sessionAffinity | string | `"None"` | Session affinity |
| accountConsole.service.sessionAffinityConfig | object | `{}` | Session affinity config |
| accountConsole.service.type | string | `"ClusterIP"` | Service type |
| accountConsole.sidecars | list | `[]` | Sidecar containers (tpl-rendered) |
| accountConsole.startupProbe.enabled | bool | `true` | Enable the startup probe |
| accountConsole.startupProbe.failureThreshold | int | `24` |  |
| accountConsole.startupProbe.initialDelaySeconds | int | `5` |  |
| accountConsole.startupProbe.periodSeconds | int | `5` |  |
| accountConsole.startupProbe.successThreshold | int | `1` |  |
| accountConsole.startupProbe.timeoutSeconds | int | `5` |  |
| accountConsole.terminationGracePeriodSeconds | int | `30` | Pod termination grace period |
| accountConsole.tolerations | list | `[]` | Tolerations |
| accountConsole.topologySpreadConstraints | list | `[]` | Topology spread constraints |
| accountConsole.updateStrategy | object | `{"type":"RollingUpdate"}` | Deployment update strategy |
| adminConsole.affinity | object | `{}` | Affinity (overrides the anti-affinity preset when set) |
| adminConsole.args | list | `[]` | Override the container args |
| adminConsole.autoscaling.hpa.enabled | bool | `false` | Enable HPA for the admin console |
| adminConsole.autoscaling.hpa.maxReplicas | int | `5` | Maximum replicas |
| adminConsole.autoscaling.hpa.minReplicas | int | `2` | Minimum replicas |
| adminConsole.autoscaling.hpa.targetCPU | int | `75` | Target CPU utilization percentage |
| adminConsole.autoscaling.hpa.targetMemory | string | `""` | Target memory utilization percentage |
| adminConsole.command | list | `[]` | Override the container command |
| adminConsole.config | object | `{}` | Extra environment variables rendered literally into the env ConfigMap |
| adminConsole.containerPorts.http | int | `3021` | Admin console listener port |
| adminConsole.containerSecurityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"enabled":true,"readOnlyRootFilesystem":false,"runAsNonRoot":false,"runAsUser":0,"seccompProfile":{"type":"RuntimeDefault"}}` | Container security context (same root-image caveat as the server) |
| adminConsole.customLivenessProbe | object | `{}` | Custom liveness probe |
| adminConsole.customReadinessProbe | object | `{}` | Custom readiness probe |
| adminConsole.customStartupProbe | object | `{}` | Custom startup probe |
| adminConsole.disableRestartOnChanges | bool | `false` | Disable the checksum annotations that roll pods on config changes |
| adminConsole.enabled | bool | `true` | Enable the admin console and deploy it separately in split-console mode |
| adminConsole.extraEnvVars | list | `[]` | Extra environment variables for the admin console container |
| adminConsole.extraEnvVarsCM | string | `""` | Extra ConfigMap with environment variables (tpl-rendered name) |
| adminConsole.extraEnvVarsSecret | string | `""` | Extra Secret with environment variables (tpl-rendered name) |
| adminConsole.extraVolumeMounts | list | `[]` | Extra volume mounts (tpl-rendered) |
| adminConsole.extraVolumes | list | `[]` | Extra volumes (tpl-rendered) |
| adminConsole.hostAliases | list | `[]` | Pod host aliases |
| adminConsole.ingress.annotations | object | `{}` | Ingress annotations (tpl-rendered; use-regex and rewrite-target are chart-owned) |
| adminConsole.ingress.certManager | bool | `false` | Request a cert-manager certificate (adds kubernetes.io/tls-acme) |
| adminConsole.ingress.enabled | bool | `false` | Enable ingress-nginx routing for the split admin console (requires server.ingress.enabled) |
| adminConsole.ingress.extraPaths | list | `[]` | Extra paths for the primary host |
| adminConsole.ingress.extraRules | list | `[]` | Full custom rules (tpl-rendered; appended after the generated rules) |
| adminConsole.ingress.extraTls | list | `[]` | Extra TLS entries |
| adminConsole.ingress.hostname | string | `""` | Ingress hostname (tpl-rendered; defaults to server.ingress.hostname) |
| adminConsole.ingress.ingressClassName | string | `""` | Ingress class name |
| adminConsole.ingress.tls | bool | `false` | Enable TLS for the hostname |
| adminConsole.initContainers | list | `[]` | Init containers (tpl-rendered) |
| adminConsole.lifecycleHooks | object | `{}` | Container lifecycle hooks |
| adminConsole.livenessProbe.enabled | bool | `true` | Enable the liveness probe |
| adminConsole.livenessProbe.failureThreshold | int | `3` |  |
| adminConsole.livenessProbe.initialDelaySeconds | int | `0` |  |
| adminConsole.livenessProbe.periodSeconds | int | `30` |  |
| adminConsole.livenessProbe.successThreshold | int | `1` |  |
| adminConsole.livenessProbe.timeoutSeconds | int | `5` |  |
| adminConsole.networkPolicy.allowExternal | bool | `true` | Allow ingress from anywhere |
| adminConsole.networkPolicy.allowExternalEgress | bool | `true` | Allow all egress |
| adminConsole.networkPolicy.enabled | bool | `false` | Create a NetworkPolicy for the admin console |
| adminConsole.networkPolicy.extraEgress | list | `[]` | Extra egress rules |
| adminConsole.networkPolicy.extraIngress | list | `[]` | Extra ingress rules |
| adminConsole.networkPolicy.ingressNSMatchLabels | object | `{}` | Namespace labels allowed to connect when allowExternal is false |
| adminConsole.networkPolicy.ingressPodMatchLabels | object | `{}` | Pod labels allowed to connect when allowExternal is false |
| adminConsole.nodeSelector | object | `{}` | Node selector |
| adminConsole.pdb.create | bool | `false` | Create a PodDisruptionBudget for the admin console |
| adminConsole.pdb.maxUnavailable | string | `""` | Maximum unavailable pods (defaults to 1 when both are empty) |
| adminConsole.pdb.minAvailable | string | `""` | Minimum available pods |
| adminConsole.podAnnotations | object | `{}` | Pod annotations (tpl-rendered) |
| adminConsole.podAntiAffinityPreset | string | `"soft"` | Pod anti-affinity preset: soft, hard or "" |
| adminConsole.podLabels | object | `{}` | Pod labels (tpl-rendered) |
| adminConsole.podSecurityContext | object | `{"enabled":true,"fsGroup":1000}` | Pod security context |
| adminConsole.priorityClassName | string | `""` | Priority class name |
| adminConsole.readinessProbe.enabled | bool | `true` | Enable the readiness probe |
| adminConsole.readinessProbe.failureThreshold | int | `3` |  |
| adminConsole.readinessProbe.initialDelaySeconds | int | `0` |  |
| adminConsole.readinessProbe.periodSeconds | int | `10` |  |
| adminConsole.readinessProbe.successThreshold | int | `1` |  |
| adminConsole.readinessProbe.timeoutSeconds | int | `5` |  |
| adminConsole.replicaCount | int | `1` | Number of admin console replicas |
| adminConsole.resources | object | `{"limits":{"memory":"512Mi"},"requests":{"cpu":"100m","memory":"256Mi"}}` | Admin console container resources |
| adminConsole.revisionHistoryLimit | int | `3` | Deployment revision history limit |
| adminConsole.route.annotations | object | `{}` | HTTPRoute annotations |
| adminConsole.route.enabled | bool | `false` | Create a Gateway API HTTPRoute for the admin console (requires server.route.enabled; tpl-rendered: a string rendering to "true" enables it, so an umbrella chart can drive this from one of its own switches; "false" and "" disable it, anything else fails the render) |
| adminConsole.route.hostnames | list | `[]` | Route hostnames ([] = derived from server.publicUrl) |
| adminConsole.route.parentRefs | list | `[]` | Gateway parentRefs |
| adminConsole.schedulerName | string | `""` | Scheduler name |
| adminConsole.service.annotations | object | `{}` | Service annotations (tpl-rendered) |
| adminConsole.service.clusterIP | string | `""` | Static cluster IP |
| adminConsole.service.externalTrafficPolicy | string | `"Cluster"` | External traffic policy |
| adminConsole.service.extraPorts | list | `[]` | Extra service ports |
| adminConsole.service.loadBalancerIP | string | `""` | LoadBalancer IP |
| adminConsole.service.loadBalancerSourceRanges | list | `[]` | LoadBalancer source ranges |
| adminConsole.service.nodePorts.http | string | `""` | Node port ("" = auto-assign) |
| adminConsole.service.ports.http | int | `3021` | Service HTTP port |
| adminConsole.service.sessionAffinity | string | `"None"` | Session affinity |
| adminConsole.service.sessionAffinityConfig | object | `{}` | Session affinity config |
| adminConsole.service.type | string | `"ClusterIP"` | Service type |
| adminConsole.sidecars | list | `[]` | Sidecar containers (tpl-rendered) |
| adminConsole.startupProbe.enabled | bool | `true` | Enable the startup probe |
| adminConsole.startupProbe.failureThreshold | int | `24` |  |
| adminConsole.startupProbe.initialDelaySeconds | int | `5` |  |
| adminConsole.startupProbe.periodSeconds | int | `5` |  |
| adminConsole.startupProbe.successThreshold | int | `1` |  |
| adminConsole.startupProbe.timeoutSeconds | int | `5` |  |
| adminConsole.terminationGracePeriodSeconds | int | `30` | Pod termination grace period |
| adminConsole.tolerations | list | `[]` | Tolerations |
| adminConsole.topologySpreadConstraints | list | `[]` | Topology spread constraints |
| adminConsole.updateStrategy | object | `{"type":"RollingUpdate"}` | Deployment update strategy |
| auth.adminPassword | string | `""` | Initial admin user password ("" = generate once, keep across upgrades). Changing it after the first install only takes effect with adminPasswordReset=true for one upgrade cycle |
| auth.adminPasswordReset | bool | `false` | Re-assert the admin password on every boot (USER_ADMIN_PASSWORD_RESET) |
| auth.existingSecret | string | `""` | Existing secret holding the keys below instead of the chart-managed secret (tpl-rendered) |
| auth.secretKeys.adminPasswordKey | string | `"admin-password"` | Key inside the (existing) secret holding the admin password |
| auth.secretKeys.secretsEncryptionKeyKey | string | `"secrets-encryption-key"` | Key inside the (existing) secret holding the secrets encryption key |
| auth.secretKeys.systemClientSecretKey | string | `"system-client-secret"` | Key inside the (existing) secret holding the system client secret |
| auth.secretsEncryptionKey | string | `""` | Optional AES-256 key-encryption-key wrapping the realm key store (SECRETS_ENCRYPTION_KEY, base64-encoded 32 bytes). Deliberately never generated by the chart: this key is effectively write-once — losing or rotating it bricks wrapped MFA seeds and signing keys. Set it explicitly here, or reference it via existingSecret plus secretsEncryptionKeyEnabled=true, and back it up. |
| auth.secretsEncryptionKeyEnabled | bool | `false` | Declare that auth.existingSecret carries the secrets encryption key (under secretKeys.secretsEncryptionKeyKey). Required for the key to be wired from an existing secret — it is never inferred, so a missing key can not silently fail open into plaintext-at-rest |
| auth.systemClientEnabled | bool | `false` | Provision the built-in system client (CLIENT_SYSTEM_ENABLED); required for machine-to-machine consumers |
| auth.systemClientSecret | string | `""` | System client secret ("" = generate once when systemClientEnabled) |
| auth.systemClientSecretReset | bool | `false` | Re-assert the system client secret on every boot (CLIENT_SYSTEM_SECRET_RESET) |
| authConsole.affinity | object | `{}` | Affinity (overrides the anti-affinity preset when set) |
| authConsole.args | list | `[]` | Override the container args |
| authConsole.autoscaling.hpa.enabled | bool | `false` | Enable HPA for the auth console |
| authConsole.autoscaling.hpa.maxReplicas | int | `5` | Maximum replicas |
| authConsole.autoscaling.hpa.minReplicas | int | `2` | Minimum replicas |
| authConsole.autoscaling.hpa.targetCPU | int | `75` | Target CPU utilization percentage |
| authConsole.autoscaling.hpa.targetMemory | string | `""` | Target memory utilization percentage |
| authConsole.command | list | `[]` | Override the container command |
| authConsole.config | object | `{}` | Extra environment variables rendered literally into the env ConfigMap |
| authConsole.containerPorts.http | int | `3020` | Auth console listener port |
| authConsole.containerSecurityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"enabled":true,"readOnlyRootFilesystem":false,"runAsNonRoot":false,"runAsUser":0,"seccompProfile":{"type":"RuntimeDefault"}}` | Container security context (same root-image caveat as the server) |
| authConsole.customLivenessProbe | object | `{}` | Custom liveness probe |
| authConsole.customReadinessProbe | object | `{}` | Custom readiness probe |
| authConsole.customStartupProbe | object | `{}` | Custom startup probe |
| authConsole.disableRestartOnChanges | bool | `false` | Disable the checksum annotations that roll pods on config changes |
| authConsole.enabled | bool | `true` | Deploy the auth console as its own workload in split-console mode. Must stay true: the auth console owns login and cannot be disabled (ignored in combined mode) |
| authConsole.extraEnvVars | list | `[]` | Extra environment variables for the auth console container |
| authConsole.extraEnvVarsCM | string | `""` | Extra ConfigMap with environment variables (tpl-rendered name) |
| authConsole.extraEnvVarsSecret | string | `""` | Extra Secret with environment variables (tpl-rendered name) |
| authConsole.extraVolumeMounts | list | `[]` | Extra volume mounts (tpl-rendered) |
| authConsole.extraVolumes | list | `[]` | Extra volumes (tpl-rendered) |
| authConsole.hostAliases | list | `[]` | Pod host aliases |
| authConsole.ingress.annotations | object | `{}` | Ingress annotations (tpl-rendered; use-regex and rewrite-target are chart-owned) |
| authConsole.ingress.certManager | bool | `false` | Request a cert-manager certificate (adds kubernetes.io/tls-acme) |
| authConsole.ingress.enabled | bool | `false` | Enable ingress-nginx routing for the split auth console (requires server.ingress.enabled) |
| authConsole.ingress.extraPaths | list | `[]` | Extra paths for the primary host |
| authConsole.ingress.extraRules | list | `[]` | Full custom rules (tpl-rendered; appended after the generated rules) |
| authConsole.ingress.extraTls | list | `[]` | Extra TLS entries |
| authConsole.ingress.hostname | string | `""` | Ingress hostname (tpl-rendered; defaults to server.ingress.hostname) |
| authConsole.ingress.ingressClassName | string | `""` | Ingress class name |
| authConsole.ingress.tls | bool | `false` | Enable TLS for the hostname |
| authConsole.initContainers | list | `[]` | Init containers (tpl-rendered) |
| authConsole.lifecycleHooks | object | `{}` | Container lifecycle hooks |
| authConsole.livenessProbe.enabled | bool | `true` | Enable the liveness probe |
| authConsole.livenessProbe.failureThreshold | int | `3` |  |
| authConsole.livenessProbe.initialDelaySeconds | int | `0` |  |
| authConsole.livenessProbe.periodSeconds | int | `30` |  |
| authConsole.livenessProbe.successThreshold | int | `1` |  |
| authConsole.livenessProbe.timeoutSeconds | int | `5` |  |
| authConsole.networkPolicy.allowExternal | bool | `true` | Allow ingress from anywhere |
| authConsole.networkPolicy.allowExternalEgress | bool | `true` | Allow all egress |
| authConsole.networkPolicy.enabled | bool | `false` | Create a NetworkPolicy for the auth console |
| authConsole.networkPolicy.extraEgress | list | `[]` | Extra egress rules |
| authConsole.networkPolicy.extraIngress | list | `[]` | Extra ingress rules |
| authConsole.networkPolicy.ingressNSMatchLabels | object | `{}` | Namespace labels allowed to connect when allowExternal is false |
| authConsole.networkPolicy.ingressPodMatchLabels | object | `{}` | Pod labels allowed to connect when allowExternal is false |
| authConsole.nodeSelector | object | `{}` | Node selector |
| authConsole.pdb.create | bool | `false` | Create a PodDisruptionBudget for the auth console |
| authConsole.pdb.maxUnavailable | string | `""` | Maximum unavailable pods (defaults to 1 when both are empty) |
| authConsole.pdb.minAvailable | string | `""` | Minimum available pods |
| authConsole.podAnnotations | object | `{}` | Pod annotations (tpl-rendered) |
| authConsole.podAntiAffinityPreset | string | `"soft"` | Pod anti-affinity preset: soft, hard or "" |
| authConsole.podLabels | object | `{}` | Pod labels (tpl-rendered) |
| authConsole.podSecurityContext | object | `{"enabled":true,"fsGroup":1000}` | Pod security context |
| authConsole.priorityClassName | string | `""` | Priority class name |
| authConsole.readinessProbe.enabled | bool | `true` | Enable the readiness probe |
| authConsole.readinessProbe.failureThreshold | int | `3` |  |
| authConsole.readinessProbe.initialDelaySeconds | int | `0` |  |
| authConsole.readinessProbe.periodSeconds | int | `10` |  |
| authConsole.readinessProbe.successThreshold | int | `1` |  |
| authConsole.readinessProbe.timeoutSeconds | int | `5` |  |
| authConsole.replicaCount | int | `1` | Number of auth console replicas |
| authConsole.resources | object | `{"limits":{"memory":"512Mi"},"requests":{"cpu":"100m","memory":"256Mi"}}` | Auth console container resources |
| authConsole.revisionHistoryLimit | int | `3` | Deployment revision history limit |
| authConsole.route.annotations | object | `{}` | HTTPRoute annotations |
| authConsole.route.enabled | bool | `false` | Create a Gateway API HTTPRoute for the auth console (requires server.route.enabled; tpl-rendered: a string rendering to "true" enables it, so an umbrella chart can drive this from one of its own switches; "false" and "" disable it, anything else fails the render) |
| authConsole.route.hostnames | list | `[]` | Route hostnames ([] = derived from server.publicUrl) |
| authConsole.route.parentRefs | list | `[]` | Gateway parentRefs |
| authConsole.schedulerName | string | `""` | Scheduler name |
| authConsole.service.annotations | object | `{}` | Service annotations (tpl-rendered) |
| authConsole.service.clusterIP | string | `""` | Static cluster IP |
| authConsole.service.externalTrafficPolicy | string | `"Cluster"` | External traffic policy |
| authConsole.service.extraPorts | list | `[]` | Extra service ports |
| authConsole.service.loadBalancerIP | string | `""` | LoadBalancer IP |
| authConsole.service.loadBalancerSourceRanges | list | `[]` | LoadBalancer source ranges |
| authConsole.service.nodePorts.http | string | `""` | Node port ("" = auto-assign) |
| authConsole.service.ports.http | int | `3020` | Service HTTP port |
| authConsole.service.sessionAffinity | string | `"None"` | Session affinity |
| authConsole.service.sessionAffinityConfig | object | `{}` | Session affinity config |
| authConsole.service.type | string | `"ClusterIP"` | Service type |
| authConsole.sidecars | list | `[]` | Sidecar containers (tpl-rendered) |
| authConsole.startupProbe.enabled | bool | `true` | Enable the startup probe |
| authConsole.startupProbe.failureThreshold | int | `24` |  |
| authConsole.startupProbe.initialDelaySeconds | int | `5` |  |
| authConsole.startupProbe.periodSeconds | int | `5` |  |
| authConsole.startupProbe.successThreshold | int | `1` |  |
| authConsole.startupProbe.timeoutSeconds | int | `5` |  |
| authConsole.terminationGracePeriodSeconds | int | `30` | Pod termination grace period |
| authConsole.tolerations | list | `[]` | Tolerations |
| authConsole.topologySpreadConstraints | list | `[]` | Topology spread constraints |
| authConsole.updateStrategy | object | `{"type":"RollingUpdate"}` | Deployment update strategy |
| commonAnnotations | object | `{}` | Annotations added to every object |
| commonLabels | object | `{}` | Labels added to every object |
| database.type | string | `"postgres"` | Database engine when using externalDatabase: postgres or mysql |
| diagnosticMode.args | list | `["infinity"]` | Args overriding the containers' args in diagnostic mode |
| diagnosticMode.command | list | `["sleep"]` | Command overriding the containers' command in diagnostic mode |
| diagnosticMode.enabled | bool | `false` | Start every container with a sleep command and disable probes (debugging) |
| externalDatabase.database | string | `"authup"` | External database name (must exist, or the user needs CREATE privilege) |
| externalDatabase.existingSecret | string | `""` | Existing secret with the database password (tpl-rendered) |
| externalDatabase.existingSecretPasswordKey | string | `"password"` | Key inside externalDatabase.existingSecret holding the password |
| externalDatabase.host | string | `""` | External database host (tpl-rendered). Setting this selects the external database |
| externalDatabase.password | string | `""` | External database password (stored in a chart-managed secret, never inline env) |
| externalDatabase.port | string | `""` | External database port ("" = engine default: 5432 / 3306) |
| externalDatabase.user | string | `"authup"` | External database user |
| externalRedis.existingSecret | string | `""` | Existing secret holding a FULL connection URL (tpl-rendered) |
| externalRedis.existingSecretKey | string | `"redis-connection-string"` | Key inside externalRedis.existingSecret holding the connection URL |
| externalRedis.host | string | `""` | External Redis host (alternative to url; the chart composes the URL) |
| externalRedis.password | string | `""` | External Redis password |
| externalRedis.port | int | `6379` | External Redis port |
| externalRedis.url | string | `""` | Full external Redis/Valkey connection URL (redis://[user:pass@]host:port); stored in a chart-managed secret |
| extraDeploy | list | `[]` | Extra objects to deploy (rendered through tpl; list of manifests or strings) |
| fullnameOverride | string | `""` | Override the fully qualified release name |
| global.defaultStorageClass | string | `""` | Global default storage class for dynamic provisioning |
| global.imagePullSecrets | list | `[]` | Global image pull secrets (list of names or objects) |
| global.imageRegistry | string | `""` | Global container image registry override (takes precedence over image.registry) |
| image.digest | string | `""` | Authup image digest (takes precedence over tag) |
| image.pullPolicy | string | `"IfNotPresent"` | Authup image pull policy |
| image.pullSecrets | list | `[]` | Authup image pull secrets |
| image.registry | string | `"docker.io"` | Authup image registry |
| image.repository | string | `"authup/authup"` | Authup image repository (one image serves every application role) |
| image.tag | string | `""` | Authup image tag (defaults to the chart appVersion) |
| mysql.affinity | object | `{}` | MySQL affinity |
| mysql.auth.database | string | `"authup"` | MySQL database name (created on first boot) |
| mysql.auth.password | string | `""` | MySQL password ("" = generate once, keep across upgrades) |
| mysql.auth.username | string | `"authup"` | MySQL application username |
| mysql.containerSecurityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"enabled":true,"runAsGroup":999,"runAsNonRoot":true,"runAsUser":999,"seccompProfile":{"type":"RuntimeDefault"}}` | MySQL container security context |
| mysql.enabled | bool | `false` | Deploy the built-in MySQL instance |
| mysql.extraEnvVars | list | `[]` | Extra environment variables for the MySQL container |
| mysql.image.pullPolicy | string | `"IfNotPresent"` | MySQL image pull policy |
| mysql.image.registry | string | `"docker.io"` | MySQL image registry |
| mysql.image.repository | string | `"mysql"` | MySQL image repository (docker official image) |
| mysql.image.tag | string | `"8.4"` | MySQL image tag |
| mysql.nodeSelector | object | `{}` | MySQL node selector |
| mysql.persistence.enabled | bool | `true` | Persist MySQL data |
| mysql.persistence.existingClaim | string | `""` | Use an existing PVC instead of creating one |
| mysql.persistence.size | string | `"8Gi"` | PVC size |
| mysql.persistence.storageClass | string | `""` | PVC storage class ("" = cluster default; global.defaultStorageClass wins) |
| mysql.podSecurityContext | object | `{"enabled":true,"fsGroup":999}` | MySQL pod security context |
| mysql.resources | object | `{"limits":{"memory":"1Gi"},"requests":{"cpu":"100m","memory":"512Mi"}}` | MySQL container resources |
| mysql.tolerations | list | `[]` | MySQL tolerations |
| nameOverride | string | `""` | Override the chart name |
| namespaceOverride | string | `""` | Override the release namespace |
| postgresql.affinity | object | `{}` | PostgreSQL affinity |
| postgresql.auth.database | string | `"authup"` | PostgreSQL database name (created on first boot) |
| postgresql.auth.password | string | `""` | PostgreSQL password ("" = generate once, keep across upgrades) |
| postgresql.auth.username | string | `"authup"` | PostgreSQL application username |
| postgresql.containerSecurityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"enabled":true,"runAsGroup":999,"runAsNonRoot":true,"runAsUser":999,"seccompProfile":{"type":"RuntimeDefault"}}` | PostgreSQL container security context |
| postgresql.enabled | bool | `true` | Deploy the built-in PostgreSQL instance |
| postgresql.extraEnvVars | list | `[]` | Extra environment variables for the PostgreSQL container |
| postgresql.image.pullPolicy | string | `"IfNotPresent"` | PostgreSQL image pull policy |
| postgresql.image.registry | string | `"docker.io"` | PostgreSQL image registry |
| postgresql.image.repository | string | `"postgres"` | PostgreSQL image repository (docker official image) |
| postgresql.image.tag | string | `"17"` | PostgreSQL image tag |
| postgresql.nodeSelector | object | `{}` | PostgreSQL node selector |
| postgresql.persistence.enabled | bool | `true` | Persist PostgreSQL data |
| postgresql.persistence.existingClaim | string | `""` | Use an existing PVC instead of creating one |
| postgresql.persistence.size | string | `"8Gi"` | PVC size |
| postgresql.persistence.storageClass | string | `""` | PVC storage class ("" = cluster default; global.defaultStorageClass wins) |
| postgresql.podSecurityContext | object | `{"enabled":true,"fsGroup":999}` | PostgreSQL pod security context |
| postgresql.resources | object | `{"limits":{"memory":"1Gi"},"requests":{"cpu":"100m","memory":"256Mi"}}` | PostgreSQL container resources |
| postgresql.tolerations | list | `[]` | PostgreSQL tolerations |
| server.affinity | object | `{}` | Affinity (overrides the anti-affinity preset when set) |
| server.args | list | `[]` | Override the container args |
| server.autoscaling.hpa.enabled | bool | `false` | Enable HPA for server-core (requires a configured cache) |
| server.autoscaling.hpa.maxReplicas | int | `5` | Maximum replicas |
| server.autoscaling.hpa.minReplicas | int | `2` | Minimum replicas |
| server.autoscaling.hpa.targetCPU | int | `75` | Target CPU utilization percentage |
| server.autoscaling.hpa.targetMemory | string | `""` | Target memory utilization percentage |
| server.command | list | `[]` | Override the container command |
| server.config | object | `{}` | Extra environment variables rendered literally into the env ConfigMap (map of NAME: value) for options without first-class values, e.g. AUTH_CONSOLE_PATH / ACCOUNT_CONSOLE_PATH, which replace a served console with your own build (pair them with extraVolumes; the substituted package owns the login flow, so use server.theme for branding instead). In split-console mode set them in authConsole.config / accountConsole.config: `start core` does not read console paths |
| server.configuration | string | `""` | Content of authup.yml mounted at /etc/authup/authup.yml for file-only options (middleware objects, per-field SMTP, CORS allowlist). Environment variables always win over file values. |
| server.containerSecurityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"enabled":true,"readOnlyRootFilesystem":false,"runAsNonRoot":false,"runAsUser":0,"seccompProfile":{"type":"RuntimeDefault"}}` | Container security context. The upstream image runs as root and needs writable log and npm cache paths; the chart mounts emptyDirs at /var/log/authup and /tmp. |
| server.customLivenessProbe | object | `{}` | Custom liveness probe |
| server.customReadinessProbe | object | `{}` | Custom readiness probe |
| server.customStartupProbe | object | `{}` | Custom startup probe overriding the structured one |
| server.disableRestartOnChanges | bool | `false` | Disable the checksum annotations that roll pods on config/secret changes |
| server.enabled | bool | `true` | Deploy the server-core service |
| server.existingConfigmap | string | `""` | Existing ConfigMap holding authup.yml (tpl-rendered) |
| server.extraEnvVars | list | `[]` | Extra environment variables for the server container |
| server.extraEnvVarsCM | string | `""` | Extra ConfigMap with environment variables (tpl-rendered name) |
| server.extraEnvVarsSecret | string | `""` | Extra Secret with environment variables (tpl-rendered name) |
| server.extraVolumeMounts | list | `[]` | Extra volume mounts (tpl-rendered) |
| server.extraVolumes | list | `[]` | Extra volumes (tpl-rendered) |
| server.features.accountConsole | string | `""` | Deprecated: use accountConsole.enabled. Any non-empty value fails. |
| server.features.emailVerification | bool | `false` | Enable email verification (EMAIL_VERIFICATION_ENABLED; requires SMTP) |
| server.features.passwordRecovery | bool | `false` | Enable password recovery (PASSWORD_RECOVERY_ENABLED; requires SMTP) |
| server.features.registration | bool | `false` | Enable self-service user registration (REGISTRATION_ENABLED) |
| server.hostAliases | list | `[]` | Pod host aliases |
| server.ingress.annotations | object | `{}` | Ingress annotations (tpl-rendered). Token responses are large; with ingress-nginx consider proxy-buffer-size 16k+. |
| server.ingress.certManager | bool | `false` | Request a cert-manager certificate (adds kubernetes.io/tls-acme) |
| server.ingress.enabled | bool | `false` | Enable ingress for server-core. NOTE: this also exposes the UNAUTHENTICATED /metrics endpoint publicly — block it at the ingress controller or disable it via server.configuration (core.middlewarePrometheus: false) when it is not scraped |
| server.ingress.extraHosts | list | `[]` | Extra hosts |
| server.ingress.extraPaths | list | `[]` | Extra paths for the primary host |
| server.ingress.extraRules | list | `[]` | Full custom rules (tpl-rendered; appended after the generated rules) |
| server.ingress.extraTls | list | `[]` | Extra TLS entries |
| server.ingress.hostname | string | `""` | Ingress hostname (tpl-rendered); also drives the derived PUBLIC_URL |
| server.ingress.ingressClassName | string | `""` | Ingress class name |
| server.ingress.path | string | `"/"` | Ingress path |
| server.ingress.pathType | string | `"Prefix"` | Ingress path type |
| server.ingress.tls | bool | `false` | Enable TLS for the hostname (secret <hostname>-tls unless extraTls overrides) |
| server.initContainers | list | `[]` | Init containers (tpl-rendered) |
| server.lifecycleHooks | object | `{}` | Container lifecycle hooks |
| server.livenessProbe.enabled | bool | `true` | Enable the liveness probe (GET / status endpoint) |
| server.livenessProbe.failureThreshold | int | `3` |  |
| server.livenessProbe.initialDelaySeconds | int | `0` |  |
| server.livenessProbe.periodSeconds | int | `30` |  |
| server.livenessProbe.successThreshold | int | `1` |  |
| server.livenessProbe.timeoutSeconds | int | `5` |  |
| server.metrics.serviceMonitor | object | `{"enabled":false,"honorLabels":false,"interval":"30s","jobLabel":"","labels":{},"metricRelabelings":[],"namespace":"","relabelings":[],"scrapeTimeout":""}` | The /metrics endpoint is UNAUTHENTICATED; keep it off the public ingress |
| server.metrics.serviceMonitor.enabled | bool | `false` | Create a prometheus-operator ServiceMonitor scraping /metrics |
| server.metrics.serviceMonitor.honorLabels | bool | `false` | Honor labels |
| server.metrics.serviceMonitor.interval | string | `"30s"` | Scrape interval |
| server.metrics.serviceMonitor.jobLabel | string | `""` | Job label |
| server.metrics.serviceMonitor.labels | object | `{}` | ServiceMonitor labels |
| server.metrics.serviceMonitor.metricRelabelings | list | `[]` | Metric relabelings |
| server.metrics.serviceMonitor.namespace | string | `""` | ServiceMonitor namespace ("" = release namespace) |
| server.metrics.serviceMonitor.relabelings | list | `[]` | Relabelings |
| server.metrics.serviceMonitor.scrapeTimeout | string | `""` | Scrape timeout |
| server.mfa.enabled | bool | `false` | Enable multi-factor authentication (MFA_ENABLED) |
| server.mfa.required | bool | `false` | Require MFA for every user (MFA_REQUIRED; needs mfa.enabled) |
| server.migration.backoffLimit | int | `3` | Job backoff limit |
| server.migration.enabled | bool | `false` | Run `migration run` as a pre-upgrade hook Job. Recommended for multi-replica deployments (serializes DDL before pods roll). Fresh installs and non-persistent built-in databases migrate at boot regardless. Under useHelmHooks=false the Job runs as an ArgoCD Sync-phase hook ordered after the built-in database by sync-wave, so it is safe from the first sync |
| server.migration.podAnnotations | object | `{}` | Job pod annotations |
| server.migration.resources | object | `{}` | Job resources ({} = server resources defaults) |
| server.migration.ttlSecondsAfterFinished | int | `300` | Delete the Job this many seconds after it finishes ("" = keep) |
| server.networkPolicy.allowExternal | bool | `true` | Allow ingress from anywhere. When false, only the split console pods and the configured selectors may connect: add your ingress controller via ingressNSMatchLabels, ingressPodMatchLabels or extraIngress (required) |
| server.networkPolicy.allowExternalEgress | bool | `true` | Allow all egress |
| server.networkPolicy.enabled | bool | `false` | Create a NetworkPolicy for the server and, with server.migration.enabled, a hook-scoped egress policy for the migration Job |
| server.networkPolicy.extraEgress | list | `[]` | Extra egress rules (also applied to the migration Job policy) |
| server.networkPolicy.extraIngress | list | `[]` | Extra ingress rules |
| server.networkPolicy.ingressNSMatchLabels | object | `{}` | Namespace labels allowed to connect when allowExternal is false |
| server.networkPolicy.ingressPodMatchLabels | object | `{}` | Pod labels allowed to connect when allowExternal is false |
| server.nodeSelector | object | `{}` | Node selector |
| server.pdb.create | bool | `false` | Create a PodDisruptionBudget for server-core |
| server.pdb.maxUnavailable | string | `""` | Maximum unavailable pods (defaults to 1 when both are empty) |
| server.pdb.minAvailable | string | `""` | Minimum available pods |
| server.podAnnotations | object | `{}` | Pod annotations (tpl-rendered) |
| server.podAntiAffinityPreset | string | `"soft"` | Pod anti-affinity preset: soft, hard or "" |
| server.podLabels | object | `{}` | Pod labels (tpl-rendered) |
| server.podSecurityContext | object | `{"enabled":true,"fsGroup":1000}` | Pod security context |
| server.priorityClassName | string | `""` | Priority class name |
| server.provisioning.enabled | bool | `false` | Mount provisioning files consumed at boot (fail-closed: an invalid file aborts startup) |
| server.provisioning.existingConfigMap | string | `""` | Existing ConfigMap with provisioning files (tpl-rendered) |
| server.provisioning.existingSecret | string | `""` | Existing Secret with provisioning files (tpl-rendered; takes precedence — use for provisioning content that carries credentials) |
| server.provisioning.files | object | `{}` | Map of filename -> file content (tpl-rendered; the extension selects the reader). Lands in a ConfigMap — credential-bearing provisioning content belongs in existingSecret instead |
| server.publicUrl | string | `""` | Public URL of Authup (PUBLIC_URL), shared by the API and consoles and used as the OIDC issuer origin. "" = derived from server.ingress when enabled. Changing it later breaks enrolled WebAuthn credentials and the OIDC issuer. |
| server.readinessProbe.enabled | bool | `true` | Enable the readiness probe (GET / status endpoint) |
| server.readinessProbe.failureThreshold | int | `3` |  |
| server.readinessProbe.initialDelaySeconds | int | `0` |  |
| server.readinessProbe.periodSeconds | int | `10` |  |
| server.readinessProbe.successThreshold | int | `1` |  |
| server.readinessProbe.timeoutSeconds | int | `5` |  |
| server.replicaCount | int | `1` | Number of server-core replicas (values > 1 REQUIRE a configured cache) |
| server.resources | object | `{"limits":{"memory":"2Gi"},"requests":{"cpu":"250m","memory":"512Mi"}}` | Server container resources |
| server.revisionHistoryLimit | int | `3` | Deployment revision history limit |
| server.route.annotations | object | `{}` | HTTPRoute annotations |
| server.route.enabled | bool | `false` | Create a Gateway API HTTPRoute for server-core (tpl-rendered: a string rendering to "true" enables it, so an umbrella chart can drive this from one of its own switches; "false" and "" disable it, anything else fails the render) |
| server.route.filters | list | `[]` | Rule filters (tpl-rendered), e.g. a URLRewrite stripping a path prefix |
| server.route.hostnames | list | `[]` | Route hostnames ([] = derived from server.publicUrl / ingress hostname; only the host is kept, a public URL path is dropped and needs its own matches entry) |
| server.route.matches | list | `[]` | Rule matches (tpl-rendered); [] is the Gateway API default, PathPrefix "/" |
| server.route.parentRefs | list | `[]` | Gateway parentRefs |
| server.schedulerName | string | `""` | Scheduler name |
| server.service.annotations | object | `{}` | Service annotations (tpl-rendered) |
| server.service.clusterIP | string | `""` | Static cluster IP |
| server.service.externalTrafficPolicy | string | `"Cluster"` | External traffic policy |
| server.service.extraPorts | list | `[]` | Extra service ports |
| server.service.loadBalancerIP | string | `""` | LoadBalancer IP |
| server.service.loadBalancerSourceRanges | list | `[]` | LoadBalancer source ranges |
| server.service.nodePorts.http | string | `""` | Node port ("" = auto-assign) |
| server.service.ports.http | int | `3000` | Service HTTP port (the container port is fixed at 3000) |
| server.service.sessionAffinity | string | `"None"` | Session affinity |
| server.service.sessionAffinityConfig | object | `{}` | Session affinity config |
| server.service.type | string | `"ClusterIP"` | Service type |
| server.sidecars | list | `[]` | Sidecar containers (tpl-rendered) |
| server.splitConsoles | bool | `false` | Run API-only server pods and deploy consoles separately (requires the public URL at the origin root because console prefixes are fixed) |
| server.startupProbe.enabled | bool | `true` | Enable the startup probe (first boot runs database creation, migrations and provisioning) |
| server.startupProbe.failureThreshold | int | `60` |  |
| server.startupProbe.initialDelaySeconds | int | `5` |  |
| server.startupProbe.periodSeconds | int | `5` |  |
| server.startupProbe.successThreshold | int | `1` |  |
| server.startupProbe.timeoutSeconds | int | `5` |  |
| server.terminationGracePeriodSeconds | int | `30` | Pod termination grace period (server-core tears down within ~10s after signal) |
| server.theme.enabled | bool | `false` | Mount an operator theme for the served consoles (auth, admin and account). Experimental upstream: the directory layout and the theme* options may change in a minor release |
| server.theme.existingConfigMap | string | `""` | Existing ConfigMap holding the theme (tpl-rendered name). Use for binary assets, which cannot be expressed in files. Mounted whole, so it must carry theme.json itself and excludes the manifest values above |
| server.theme.existingConfigMapItems | list | `[]` | Key -> path projection for existingConfigMap, so its keys can land in subdirectories (e.g. [{key: theme-css, path: assets/theme.css}]). Empty mounts every key flat at the theme root |
| server.theme.favicon | string | `""` | Favicon path, relative to the theme root and under assets/ (e.g. assets/favicon.svg). Must be a key of files |
| server.theme.files | object | `{}` | Map of path -> file content, relative to the theme root (tpl-rendered). Keys may carry a "/" ("assets/theme.css") and are projected into subdirectories. Only assets/ is served over HTTP. Text only — use existingConfigMap with binaryData for images. Set theme.json here only when writing the manifest by hand instead of using the values above |
| server.theme.fragmentsEnabled | bool | `false` | Read fragments/head.html and splice it into the console <head>. Raw, unsanitized markup on the identity provider origin, so it is opt-in |
| server.theme.logo | string | `""` | Logo replacing the built-in mark on both consoles, under assets/. Painted into the existing mark's box, so it needs no sizing |
| server.theme.logoDark | string | `""` | Dark-mode logo variant, under assets/. Without it dark mode reuses logo, which disappears when the mark is drawn dark-on-light |
| server.theme.stylesheet | string | `""` | Stylesheet path, under assets/ and ending in .css. Linked last, so it beats the token block; it is unlayered, so set dark colors explicitly |
| server.theme.title | string | `""` | Document title of the served consoles ("" = authup's own) |
| server.theme.tokens | object | `{}` | authup-periwinkle alone recolors buttons, focus rings and links. A color set here also wins in dark mode: put surface colors in both tokens and tokensDark |
| server.theme.tokensDark | object | `{}` | CSS custom properties applied in dark mode only (tpl-rendered) |
| server.tolerations | list | `[]` | Tolerations |
| server.topologySpreadConstraints | list | `[]` | Topology spread constraints (a missing labelSelector is filled with the pod's selector labels) |
| server.trustProxy | string | `"1"` | TRUST_PROXY setting. The chart defaults to one trusted hop (the ingress), not authup's spoofable trust-everything default |
| server.trustedOrigins | list | `[]` | Additional trusted first-party app origins (TRUSTED_ORIGINS). Each entry is added to the redirect allowlist of the per-realm built-in system clients (admin-console, account-console), so any listed origin can complete a login and obtain a full-permission token. A host may carry a single "*" (https://*.example.com); "**" in a host is rejected by authup at boot. List or comma-separated string; tpl-rendered. |
| server.updateStrategy | object | `{"type":"RollingUpdate"}` | Deployment update strategy |
| serviceAccount.annotations | object | `{}` | ServiceAccount annotations (tpl-rendered) |
| serviceAccount.automountServiceAccountToken | bool | `false` | Automount the service account token |
| serviceAccount.create | bool | `true` | Create a ServiceAccount (shared by all application roles) |
| serviceAccount.name | string | `""` | ServiceAccount name ("" = generated from the fullname) |
| smtp.connectionString | string | `""` | SMTP connection string (smtp(s)://user:pass@host:port); stored in a chart-managed secret |
| smtp.existingSecret | string | `""` | Existing secret holding the SMTP connection string (tpl-rendered) |
| smtp.existingSecretKey | string | `"smtp-connection-string"` | Key inside smtp.existingSecret holding the connection string |
| useHelmHooks | bool | `true` | Render Helm hook annotations on the migration Job. Set false only for ArgoCD, which reads its own Sync-phase, sync-wave annotations instead. ArgoCD also understands Helm hooks, but maps pre-upgrade to an unordered PreSync hook: with server.migration.enabled and a built-in database, set false so the Job waits for the database instead of deadlocking the first sync. Flux and plain helm need true: a plain Job's pod template is immutable, so the next upgrade cannot patch it. |
| valkey.affinity | object | `{}` | Valkey affinity |
| valkey.auth.password | string | `""` | Valkey password ("" = generate once, keep across upgrades) |
| valkey.containerSecurityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"enabled":true,"runAsGroup":999,"runAsNonRoot":true,"runAsUser":999,"seccompProfile":{"type":"RuntimeDefault"}}` | Valkey container security context |
| valkey.enabled | bool | `false` | Deploy the built-in Valkey instance |
| valkey.image.pullPolicy | string | `"IfNotPresent"` | Valkey image pull policy |
| valkey.image.registry | string | `"docker.io"` | Valkey image registry |
| valkey.image.repository | string | `"valkey/valkey"` | Valkey image repository (docker official image) |
| valkey.image.tag | string | `"8"` | Valkey image tag |
| valkey.nodeSelector | object | `{}` | Valkey node selector |
| valkey.persistence.enabled | bool | `false` | Persist Valkey data (the cache content is reconstructable; default off) |
| valkey.persistence.size | string | `"1Gi"` | PVC size |
| valkey.persistence.storageClass | string | `""` | PVC storage class |
| valkey.podSecurityContext | object | `{"enabled":true,"fsGroup":999}` | Valkey pod security context |
| valkey.resources | object | `{"limits":{"memory":"256Mi"},"requests":{"cpu":"50m","memory":"64Mi"}}` | Valkey container resources |
| valkey.tolerations | list | `[]` | Valkey tolerations |
| worker.affinity | object | `{}` | Affinity (overrides the anti-affinity preset when set) |
| worker.args | list | `[]` | Override the container args |
| worker.autoscaling.hpa.enabled | bool | `false` | Enable HPA for the worker |
| worker.autoscaling.hpa.maxReplicas | int | `3` | Maximum replicas |
| worker.autoscaling.hpa.minReplicas | int | `1` | Minimum replicas |
| worker.autoscaling.hpa.targetCPU | int | `75` | Target CPU utilization percentage |
| worker.autoscaling.hpa.targetMemory | string | `""` | Target memory utilization percentage |
| worker.command | list | `[]` | Override the container command |
| worker.containerSecurityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"enabled":true,"readOnlyRootFilesystem":false,"runAsNonRoot":false,"runAsUser":0,"seccompProfile":{"type":"RuntimeDefault"}}` | Container security context |
| worker.disableRestartOnChanges | bool | `false` | Disable checksum annotations that roll pods on configuration changes |
| worker.enabled | bool | `false` | Deploy a dedicated background worker (requires server.enabled). It never migrates: on a fresh install it restarts until the server has initialized the schema; enable server.migration.enabled so upgrades run the Job first |
| worker.extraEnvVars | list | `[]` | Extra environment variables for the worker container |
| worker.extraEnvVarsCM | string | `""` | Extra ConfigMap with environment variables (tpl-rendered name) |
| worker.extraEnvVarsSecret | string | `""` | Extra Secret with environment variables (tpl-rendered name) |
| worker.extraVolumeMounts | list | `[]` | Extra volume mounts (tpl-rendered) |
| worker.extraVolumes | list | `[]` | Extra volumes (tpl-rendered) |
| worker.hostAliases | list | `[]` | Pod host aliases |
| worker.initContainers | list | `[]` | Init containers (tpl-rendered) |
| worker.lifecycleHooks | object | `{}` | Container lifecycle hooks |
| worker.networkPolicy.allowExternalEgress | bool | `true` | Allow all egress |
| worker.networkPolicy.enabled | bool | `false` | Create an egress NetworkPolicy for the worker |
| worker.networkPolicy.extraEgress | list | `[]` | Extra egress rules |
| worker.nodeSelector | object | `{}` | Node selector |
| worker.pdb.create | bool | `false` | Create a PodDisruptionBudget for the worker |
| worker.pdb.maxUnavailable | string | `""` | Maximum unavailable pods (defaults to 1 when both are empty) |
| worker.pdb.minAvailable | string | `""` | Minimum available pods |
| worker.podAnnotations | object | `{}` | Pod annotations (tpl-rendered) |
| worker.podAntiAffinityPreset | string | `"soft"` | Pod anti-affinity preset: soft, hard or "" |
| worker.podLabels | object | `{}` | Pod labels (tpl-rendered) |
| worker.podSecurityContext | object | `{"enabled":true,"fsGroup":1000}` | Pod security context |
| worker.priorityClassName | string | `""` | Priority class name |
| worker.replicaCount | int | `1` | Number of worker replicas (one is normally sufficient) |
| worker.resources | object | `{"limits":{"memory":"1Gi"},"requests":{"cpu":"100m","memory":"256Mi"}}` | Worker container resources |
| worker.revisionHistoryLimit | int | `3` | Deployment revision history limit |
| worker.schedulerName | string | `""` | Scheduler name |
| worker.sidecars | list | `[]` | Sidecar containers (tpl-rendered) |
| worker.terminationGracePeriodSeconds | int | `30` | Pod termination grace period |
| worker.tolerations | list | `[]` | Tolerations |
| worker.topologySpreadConstraints | list | `[]` | Topology spread constraints |
| worker.updateStrategy | object | `{"type":"RollingUpdate"}` | Deployment update strategy |
