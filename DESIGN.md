# Authup Helm Chart Repository — Design

Status: draft for review. Distilled from deep-dives into `authelia/chartrepo`,
`goauthentik/helm`, `PrivateAIM/helm` (both authup deployments), `bitnami/charts`
(common + keycloak + postgresql + redis), and the authup monorepo's own deployment
surface (Dockerfile, config module, docs). Full research reports live outside the
repo; every decision below cites its evidence.

## 1. Goals and constraints

1. **Bitnami-grade flexibility without bitnami dependencies.** The chart adopts the
   bitnami values UX (`existingSecret` + key mapping, `extraEnvVars` /
   `extraEnvVarsCM` / `extraEnvVarsSecret`, `extraVolumes`, `initContainers`,
   `sidecars`, `extraDeploy`, `commonLabels` / `commonAnnotations`,
   `fullnameOverride`, `diagnosticMode`, multi-release-per-namespace naming) but
   depends on **zero** external charts. Rationale: the Broadcom/bitnami licensing
   change made bitnami subcharts effectively unusable (PrivateAIM is actively
   migrating off them; authentik must pin docker-official images plus
   `global.security.allowInsecureImages: true` just to keep the postgres subchart
   alive), authentik's k8s-at-home common-library era ended when that library died
   upstream, and Authelia removed its redis/postgres/mariadb subcharts in 0.11.0
   after years of maintenance. The ~5 naming/label/secret helpers worth having are
   vendored locally (Apache-2.0-clean, bitnami-compatible key names).
2. **Two workloads, one chart, one image.** `authup/authup` is a single image whose
   entrypoint dispatches on args: `server/core start` (server-core, the IdP/API) and
   `client/web start` (client-web, the Nuxt admin UI). The `authup` CLI supervisor is
   **not routable through the container entrypoint** and the monorepo docs pin
   "containers with one service each" as the production topology — so the chart
   ships two Deployments and never a combined pod.
3. **The container port is always 3000 for both services.** The entrypoint
   force-exports `PORT=3000` / `NUXT_PORT=3000`; a chart-set `PORT` env is dead.
   `containerPort` is pinned, only Service ports are values.
4. **Hybrid database model: postgres AND mysql are first-class** (`DB_TYPE`
   supports both), with in-cluster dev/small-prod provisioning for either engine and
   `externalDatabase` as the documented production path. sqlite is impossible on the
   published image (`NODE_ENV=production` is baked in and production forbids
   sqlite), so the chart hard-fails when no database is configured.
5. **Solo-maintainable repo.** release-please (`release-type: helm`) owns version
   bumps (tada5hi already operates exactly this in PrivateAIM/helm); generated
   README + values.schema.json with CI drift gates; the whole pipeline runnable
   locally through a Makefile.

## 2. Repository layout

```
authup/helm
├── charts/authup/
│   ├── Chart.yaml               # apiVersion v2, dependencies: [] — self-contained
│   ├── values.yaml              # "# --" helm-docs comments + "# @schema" blocks
│   ├── values.schema.json       # GENERATED (dadav/helm-schema), drift-gated
│   ├── README.md                # GENERATED (helm-docs), drift-gated
│   ├── README.md.gotmpl
│   ├── BREAKING.md              # value-migration ledger for the 0.x line
│   ├── CHANGELOG.md             # release-please owned
│   ├── .helmignore
│   ├── ci/                     # ct install scenario matrix (one install per file)
│   │   ├── default-values.yaml          # bundled postgres, both services
│   │   ├── mysql-values.yaml            # bundled mysql
│   │   ├── external-db-values.yaml      # externalDatabase + existingSecret fixture
│   │   ├── redis-values.yaml            # bundled valkey + replicas 2
│   │   └── server-only-values.yaml      # ui.enabled=false (headless deployment)
│   ├── ci/manifests/           # fixtures pre-applied before ct install
│   └── templates/
│       ├── _helpers.tpl        # names, labels, images (vendored bitnami-compatible)
│       ├── _secrets.tpl        # lookup-based generate-if-absent + existingSecret resolution
│       ├── _database.tpl       # engine dispatch helpers (host/port/type/secret)
│       ├── _urls.tpl           # publicUrl / apiUrl / origin derivation
│       ├── validations.yaml    # render-nothing fail-fast cross-field guards
│       ├── secret.yaml         # chart-managed auth secret
│       ├── secret-db.yaml      # external-db password fallback secret
│       ├── secret-redis.yaml
│       ├── configmap-provisioning.yaml
│       ├── serviceaccount.yaml
│       ├── extra-list.yaml     # extraDeploy passthrough
│       ├── NOTES.txt
│       ├── server/             # server-core: deployment, service, ingress,
│       │                       # httproute, configmap-env, migration-job, hpa,
│       │                       # pdb, networkpolicy, servicemonitor
│       ├── ui/                 # client-web: deployment, service, ingress,
│       │                       # httproute, configmap-env, hpa, pdb, networkpolicy
│       ├── postgresql/         # optional built-in dev instance (statefulset,
│       │                       # service, secret) — docker-official image
│       ├── mysql/              # optional built-in dev instance — docker-official image
│       └── valkey/             # optional built-in cache instance
├── .github/
│   ├── configs/{ct.yaml, lintconf.yaml, chart_schema.yaml}
│   └── workflows/{lint-test.yaml, release.yaml}
├── release-please-config.json + .release-please-manifest.json
├── renovate.json
├── Makefile                     # docs / schema / lint / template targets == CI
├── CONTRIBUTING.md
└── README.md                    # repo-level: install one-liner, links
```

Single chart today, but the `charts/` + per-chart tooling layout is what `ct`,
chart-releaser, helm-docs and renovate all assume, and it leaves room for future
charts (e.g. an `authup-remote` RBAC chart, authentik-style).

## 3. Chart architecture

### 3.1 Workloads

| | `server` (server-core) | `ui` (client-web) |
|---|---|---|
| args | `["server/core", "start"]` | `["client/web", "start"]` |
| containerPort | 3000 (pinned) | 3000 (pinned) |
| role | OAuth2/OIDC IdP origin + SSR auth pages | admin console, ordinary OAuth2 RP |
| state | stateless w/ external DB+redis | fully stateless |
| probes | httpGet `/` (status endpoint); generous startupProbe (boot = migrate + provision) | httpGet `/` |
| scaling | replicas > 1 **requires redis** (hard template fail) | free |
| default | enabled | enabled (`ui.enabled: false` = headless IdP) |

Per-role template directories, ~85% duplication between the two deployment
templates **accepted deliberately** — authentik tried the DRY role-loop and
reverted it ("takes DRY maybe a bit too far"); with genuinely heterogeneous roles
the explicit files stay greppable and modifiable.

The structure is worker-ready: when authup's server/worker split lands, it becomes
a third directory `templates/worker/` with the same skeleton.

### 3.2 Naming, labels, multi-release

Vendored helpers (bitnami-compatible semantics, local implementation):

- `authup.fullname` — release-scoped, honors `fullnameOverride` (bitnami key name,
  not Authelia's confusing nameOverride-acts-as-fullname variant), 63-char safe.
- `authup.server.fullname` / `authup.ui.fullname` — `<fullname>-server` / `<fullname>-ui`.
- `authup.labels.standard` / `authup.labels.matchLabels` — the five
  `app.kubernetes.io/*` labels; selectors carry ONLY name+instance+component
  (user `commonLabels` never leak into immutable selectors — the bitnami `pick`
  guard). `app.kubernetes.io/component: server|ui` separates the two Services'
  selectors within one release.
- Zero literal names anywhere; NetworkPolicies scoped by instance labels; no
  cluster-scoped resources. Two releases in one namespace need zero overrides —
  the PrivateAIM 13-row "must match" secret-name table is the anti-pattern this
  kills.

### 3.3 Config model: explicit env, not a config-file mirror

Authup is env-configured (env beats config file), so the chart renders env vars and
**never re-templates authup's config schema** — Authelia's 714-line configMap with
~30 `semverCompare` version gates is the negative print (a chart PR per app
release, plus their verified schema-drift bugs). Three layers:

1. **First-class values** for the load-bearing ~15 options, rendered into a
   per-role env ConfigMap (`<fullname>-server-env`): `PUBLIC_URL`,
   `TRUSTED_ORIGINS`, `TRUST_PROXY`, feature flags
   (`REGISTRATION_ENABLED`, `PASSWORD_RECOVERY_ENABLED`,
   `EMAIL_VERIFICATION_ENABLED`), MFA block, event-log block, token TTLs,
   bootstrap toggles. Strict-boolean vars (`EVENT_LOG_*`, `MFA_*`,
   `LOGIN_ATTEMPT_THROTTLE_ENABLED`) always render `quote`d — authup's
   `readBoolStrict` crashes the pod on sloppy values.
2. **Secrets via `valueFrom.secretKeyRef`** (authup has no `*_FILE` support, so no
   file-mounted secrets): `DB_PASSWORD`, `REDIS` (URL form embeds the password —
   the whole connection string lives in a Secret, the flame-hub
   `redis-connection-string` lesson), `SMTP`, `USER_ADMIN_PASSWORD`,
   `CLIENT_SYSTEM_SECRET`, `SECRETS_ENCRYPTION_KEY`.
3. **Escape hatches** for the long tail (~40 env vars total exist):
   `extraEnvVars`, `extraEnvVarsCM`, `extraEnvVarsSecret` per role, all
   tpl-rendered. Plus `server.configuration` / `server.existingConfigmap` mounting
   an `authup.server.core.conf` for the file-only options (middleware objects,
   explicit CORS allowlist, per-field SMTP) — env still wins, so secrets stay in
   env.

Checksum annotations (`checksum/env`, `checksum/secret`, `checksum/provisioning`)
on both pod templates so config rotation rolls pods; opt-out flag.

### 3.4 Secret management

One chart-managed Secret (`<fullname>`) with the bitnami contract:

```yaml
auth:
  adminPassword: ""            # "" => generated (lookup-stable across upgrades)
  systemClientEnabled: false
  systemClientSecret: ""       # "" => generated when enabled
  existingSecret: ""           # whole-secret override
  secretKeys:                  # key-name indirection for foreign secrets
    adminPasswordKey: admin-password
    systemClientSecretKey: system-client-secret
    secretsEncryptionKeyKey: secrets-encryption-key
```

- **Generate-if-absent with upgrade stability**: explicit value → `lookup` of the
  existing Secret → random. `helm.sh/resource-policy: keep` on the generated
  Secret. Admin password and system-client secret are safe to generate (authup
  only applies them at bootstrap unless `*_RESET=true`, which the chart exposes as
  opt-in values, never hardcoded `"true"` like the PrivateAIM chart).
- **`SECRETS_ENCRYPTION_KEY` is special — never silently generated.** It is
  effectively write-once (removing/rotating it while wrapped rows exist bricks MFA
  seeds and wrapped signing keys). Modes: unset (default; authup warns at boot),
  `auth.secretsEncryptionKey` explicit value, or `existingSecret` reference. A
  generated mode is deliberately not offered in v1: `lookup` is inert under
  `helm template` / ArgoCD, and a GitOps-driven regeneration of this particular
  key is unrecoverable. NOTES.txt carries the back-up-your-key warning.
- The GitOps/lookup caveat is documented once, at the `auth` block.

### 3.5 Database — the hybrid model

```yaml
database:                        # selects what the app connects to
  type: postgres                 # postgres | mysql
externalDatabase:                # production path
  host: ""
  port: ""                       # "" => engine default (5432/3306)
  user: authup
  database: authup
  password: ""
  existingSecret: ""
  existingSecretPasswordKey: password
postgresql:                      # built-in dev/small-prod instance
  enabled: true                  # docker.io/library/postgres, single StatefulSet
  auth: {username: authup, password: "", database: authup, existingSecret: ""}
  persistence: {enabled: true, size: 8Gi, storageClass: ""}
  image: {repository: postgres, tag: "17"}   # docker-official, overridable
mysql:
  enabled: false                 # docker.io/library/mysql, same shape
```

- **Dispatch helpers** (`authup.database.{type,host,port,name,user,secretName,passwordKey}`)
  branch on `postgresql.enabled` / `mysql.enabled` / external — consuming
  templates never know which mode is active (the keycloak `keycloak.database.*`
  pattern). `DB_TYPE` follows the active built-in engine automatically;
  `database.type` only matters for `externalDatabase`.
- **Built-in instances are vendored minimal templates, not subcharts**: one
  single-instance StatefulSet + Service + Secret + PVC per engine, running
  **docker-official images** (`postgres`, `mysql` — free, maintained, no bitnami
  entanglement). Explicitly positioned as dev/small-prod convenience; README
  points production at an external DB or an operator (CloudNativePG for postgres).
  This is the cohort-converged posture: Authelia removed its DB subcharts,
  authentik defaults `postgresql.enabled: false` and had to lobotomize the bitnami
  chart to keep it; PrivateAIM's develop branch (PR #161, 2026-07-29) already
  replaced bitnami postgresql with exactly this — a ~150-line vendored
  StatefulSet on `postgres:17`. The post-bitnami landscape survey confirmed no
  better dependency: groundhog2k is the only maintained non-bitnami chart family
  covering both engines but is a bus-factor-1 project, and CNPG is an operator,
  not a subchart. Owning ~150 lines per engine beats depending on any of that.
  (Deliberate deviation from the cohort's `enabled: false` default: authup
  cannot boot at all without a database, so `postgresql.enabled: true` keeps
  `helm install` working out of the box; production values disable it.)
- **Validation**: template-time `fail` when neither a built-in engine is enabled
  nor `externalDatabase.host` is set (boot cannot succeed — no sqlite on the
  image); `fail` when both engines are enabled; `fail` on unknown `database.type`.
- The external-db password given inline still lands in a chart-managed Secret
  (`<fullname>-externaldb`), never in a pod env literal (bitnami's
  `-externaldb` fallback-secret trick).
- DB auto-create at boot needs CREATE privilege; built-in instances pre-create the
  database via the official images' `POSTGRES_DB` / `MYSQL_DATABASE` env, external
  DBs get a documented note.

### 3.6 Redis / cache

```yaml
valkey:                          # built-in instance (BSD-licensed redis successor)
  enabled: false
  auth: {password: "", existingSecret: ""}
externalRedis:
  url: ""                        # full redis:// URL, OR:
  host: "", port: 6379, password: "", existingSecret: ""
```

- Composed into the single `REDIS` env var (URL form; stored in a Secret because
  it embeds the password). The variable is `REDIS` — the docker-compose doc's
  `REDIS_URL` does not exist in authup source.
- Default off (authup runs without it), **but**: `server.replicaCount > 1` or
  server HPA enabled without redis configured is a hard template `fail` — with the
  per-process MemoryCache fallback, the auth-code blob, token blocklist, and MFA
  challenge nonces are per-pod, which breaks logins and MFA across replicas, not
  just performance. NOTES also recommends redis whenever MFA is enabled (cache
  availability is on the login-path SLO per authup docs).
- Built-in instance is valkey (docker-official `valkey/valkey`) — redis relicensed
  in 2024; valkey is drop-in for authup's usage.

### 3.7 Ingress and topology

Two-host model as the default (server-core is the IdP origin serving the SSR auth
pages; client-web is an ordinary RP; **cookie-domain sharing between the two is
unsupported by authup** — the chart never sets `NUXT_PUBLIC_COOKIE_DOMAIN` and
validates against foot-guns):

```yaml
server:
  publicUrl: ""                  # authoritative override; else derived from ingress
  ingress: {enabled, hostname, path, pathType, ingressClassName, annotations,
            tls, selfSigned, certManager, extraHosts, extraPaths, extraTls, extraRules}
  route: {enabled, ...}          # Gateway API HTTPRoute (52 cheap lines)
ui:
  publicUrl: ""
  ingress: {…same shape…}
```

**URL derivation is the chart's biggest UX win** (kills the #1 misconfiguration —
dead logins from a missing trusted origin, and the PrivateAIM `values_min.yaml`
publicUrl drift):

- `PUBLIC_URL` ← `server.publicUrl` | derived `http(s)://<server.ingress.hostname><path>`
- `NUXT_PUBLIC_API_URL` ← the same value (browser-reachable, never the cluster
  Service DNS; the optional private `NUXT_API_URL` may point in-cluster for SSR)
- `NUXT_PUBLIC_PUBLIC_URL` ← `ui.publicUrl` | derived from `ui.ingress`
- `TRUSTED_ORIGINS` ← user list ∪ the UI origin (auto-appended unless disabled)
- `TRUST_PROXY` defaults to `"1"` (one ingress hop), not authup's spoofable
  `true`-every-hop default.

Sub-path single-host deployments are supported (authup rebases assets off
`publicUrl`'s pathname) and documented with the nginx rewrite +
`proxy-buffer-size` annotations PrivateAIM operationally converged on (16k+
buffers for token-heavy responses). mTLS (`MTLS_PUBLIC_URL`,
`CERTIFICATE_SOURCE`) stays a documented escape hatch via `extraEnvVars`, not
first-class templating, in v1.

### 3.8 Migrations and upgrades

- server-core auto-migrates at boot (no flag to disable); a fresh install simply
  boots. The startupProbe budget is generous (migrations + provisioning on first
  boot).
- `server.migration.enabled` (default **false**) renders a **pre-upgrade-only**
  hook Job (`args: ["server/core","migration","run"]`, same env helpers as the
  Deployment so Job/Deployment can't drift). Not pre-install: on fresh installs
  the database backing service isn't up before hooks run — the exact failure that
  made authentik revert their migration Job. On upgrades the DB exists, and the
  Job serializes DDL before new pods roll — recommended (and referenced by the
  replicas>1 validation) for multi-replica deployments, since MySQL DDL is
  non-transactional and concurrent boot migrations can race.
- `useHelmHooks: false` support (ArgoCD/Flux users get a plain Job).
- Value reshuffles get authentik-style tripwires: a `deprecations.yaml` template
  fails loudly naming the moved key. BREAKING.md tracks migrations; chart
  versioning is independent SemVer (0.major.minor pre-1.0), `appVersion` tracks
  authup — never authentik's chart==app coupling (which strands chart fixes
  between app releases).

### 3.9 Provisioning files

The PrivateAIM chart's one genuinely good block, kept and hardened:

```yaml
server:
  provisioning:
    enabled: false
    files: {}                    # filename -> content (tpl-rendered); extension picks the reader
    existingConfigMap: ""        # tpl-rendered
```

Mounted read-only at `<WRITABLE_DIRECTORY_PATH>/provisioning`; checksum-annotated
(the PrivateAIM version forgot this — edits never rolled pods); values doc states
fail-closed semantics (an invalid file aborts boot) and camelCase keys.

### 3.10 Security posture

- Hardened `podSecurityContext` / `containerSecurityContext` defaults
  (runAsNonRoot 1000, readOnlyRootFilesystem, drop ALL, seccompRuntimeDefault) —
  with the caveat that the upstream image runs as root and `npm` wants a writable
  HOME: the chart mounts emptyDirs at `/usr/src/app/writable` and `/tmp`, sets
  `npm_config_cache=/tmp/.npm-cache`, and documents that full hardening is
  best-effort until upstream ships a non-root image (tracked as an upstream issue).
- `/metrics` is unauthenticated: `metrics.serviceMonitor` targets the Service
  internally, and the values doc warns against routing `/metrics` through the
  public ingress.
- NetworkPolicy shipped enabled-but-permissive (bitnami posture), instance-scoped
  selectors, tightening opt-in.
- Default-derived secrets never render as pod env literals; `start123` never
  appears anywhere (the chart generates instead).
- Anonymous `GET /` liveness endpoint for both services; terminationGracePeriodSeconds
  default ≥ 30 (server-core has a 10s forced-exit teardown timer).

### 3.11 Standard chrome (full battery, both roles)

`replicaCount`, `resources` + `resourcesPreset`, `podAnnotations`/`podLabels`,
`nodeSelector`/`tolerations`/`affinity` (+ `podAntiAffinityPreset: soft`)/
`topologySpreadConstraints`, `priorityClassName`, `schedulerName`,
`terminationGracePeriodSeconds`, `updateStrategy`, `revisionHistoryLimit`,
`command`/`args`/`lifecycleHooks` overrides, `customStartupProbe`/`customLivenessProbe`/
`customReadinessProbe` + structured probe tuning, `initContainers`, `sidecars`,
`extraVolumes`/`extraVolumeMounts`, `extraPorts`, `service.{type,ports,nodePorts,
clusterIP,loadBalancerIP,annotations,sessionAffinity}`, `pdb`, `autoscaling.hpa`,
`networkPolicy`, `serviceAccount`, `metrics.serviceMonitor`; top-level
`commonLabels`, `commonAnnotations`, `extraDeploy`, `diagnosticMode`,
`global.{imageRegistry,imagePullSecrets,defaultStorageClass}`, `clusterDomain`,
`kubeVersion`/`apiVersions` overrides. Every passthrough tpl-rendered.

### 3.12 Fail-fast validations (`validations.yaml`)

Cross-field rules the JSON schema cannot express, one render-nothing template:

1. No database configured / both built-in engines enabled / unknown `database.type`.
2. `server.replicaCount > 1` (or server HPA) without redis.
3. `mfa.required` without `mfa.enabled`; `loginThrottle` without event log
   (mirrors authup's boot validations — fail at render, not at CrashLoopBackOff).
4. `auth.existingSecret` combined with inline passwords.
5. `ui.enabled` with neither ingress nor explicit `ui.publicUrl` when server
   ingress is on (dead-login trap), and any config that would point the UI cookie
   domain at the server host.
6. Tombstones for renamed values (grows over time).

### 3.13 NOTES.txt

Computed from the same helpers the manifests use: admin UI URL, OIDC
issuer/discovery URL, `kubectl get secret` one-liners for the generated
credentials, the TRUSTED_ORIGINS reminder when overridden, the
"PUBLIC_URL changes break enrolled WebAuthn credentials" warning, the
back-up-`SECRETS_ENCRYPTION_KEY` warning when set, and resource-less-deployment
warnings.

## 4. Repo infrastructure

### 4.1 Versioning & release

- **release-please** (`release-type: helm`, component `authup`,
  `include-v-in-tag: false` → tags `authup-x.y.z`) bumps `Chart.yaml` and
  maintains CHANGELOG.md from conventional commits — the PrivateAIM-proven spine,
  matching the monorepo's culture.
- **Publish on release**: `helm/chart-releaser-action` (`CR_SKIP_EXISTING`) →
  GitHub Releases + gh-pages `index.yaml` (`https://helm.authup.org`,
  CNAME-able later), then the 6-line loop `helm push … oci://ghcr.io/authup/helm-charts`
  — dual classic + OCI, the authentik/authelia-converged shape.
  `skip-github-release` on the chart component so release-please and
  chart-releaser don't race.
- No chart signing initially (cohort-wide `sign: false`).
- Bootstrap chore: create the orphan `gh-pages` branch before the first release.

### 4.2 CI (`lint-test.yaml`)

1. `ct lint` (chart-dirs `charts`, `check-version-increment: false` —
   release-please owns versions; yamllint config from authentik's `lintconf.yaml`;
   yamale `chart_schema.yaml`).
2. helm-docs drift gate (pinned docker image, `git diff --exit-code`).
3. dadav/helm-schema drift gate (same pattern). Strict
   `additionalProperties: false` schema **plus the values-coverage audit Authelia
   lacks**: a grep-based CI check that every `.Values.*` referenced in templates
   exists in values.yaml — strict schema + template drift silently disables
   features (Authelia's HPA metrics are dead code because of exactly this).
4. `ah lint` (ArtifactHub metadata).
5. `ct install` on kind, gated by `ct list-changed`, uuid namespace,
   `--timeout 600s`, over the `ci/*-values.yaml` matrix (postgres, mysql,
   external-db + existingSecret fixture, valkey + 2 replicas, server-only).
   Authelia's lint-only CI is why its containerPort drift and copy-paste HPA/PDB
   bugs shipped; the install matrix is the cohort-proven safety net.
6. Non-blocking: hardcoded-image grep, kubeconform.

All steps are `make` targets runnable locally (authelia's Makefile discipline).

### 4.3 Dependency automation

Renovate: `helm-values` manager for the built-in DB/valkey image tags,
github-actions manager for workflow pins, conventional commit messages so bumps
flow through release-please as patches. No `bumpVersion` (release-please owns the
chart version). A `repository_dispatch` hook from the authup monorepo's release
workflow opens the `appVersion` bump PR on app releases.

## 5. Deliberate non-goals (with receipts)

| Not doing | Because |
|---|---|
| bitnami/common dependency or any library chart | Broadcom clampdown; k8s-at-home death killed authentik's v1; vendoring ~5 helpers is cheap |
| bitnami postgresql/mysql/redis subcharts | PrivateAIM migrating off; authentik lobotomized theirs; Authelia removed theirs |
| Config-file re-templating (Authelia's 714-line configMap) | authup is env-driven; the whole problem class disappears |
| Role-loop DRY deployments | authentik built it and reverted it |
| DaemonSet/StatefulSet kind-switch for the app | both services are stateless Deployments; Authelia is removing theirs |
| Traefik CRD middleware stack | forward-auth-specific; authup RPs integrate via OIDC |
| Pre-**install** migration Job | authentik reverted: hooks run before backing services exist; boot migration + startupProbe covers fresh installs |
| `authup` CLI supervisor as a pod | not routable via image entrypoint; anti-topology per authup docs |
| Chart version == appVersion | strands chart fixes between app releases (observed live on authentik main) |
| helm-unittest, signing, kubescape gates on day one | nobody in the cohort ships them; the kind matrix is the safety net |
| PVC for the writable dir | nothing durable lives there with an external DB (logs only); emptyDir |
| A "run without a database" demo mode | impossible on the published image (production forbids sqlite) |

## 6. Post-critique amendments (applied) and deferred items

A three-lens adversarial review (correctness / security / operator-UX) ran
against the initial scaffold; 40 verified findings were triaged. Applied, among
others: the release workflow's publish job runs unconditionally (chart-releaser
is idempotent via `CR_SKIP_EXISTING`; gating it on release-please outputs made
publishing unreachable under `skip-github-release`); ingress TLS secret names
derive from the component, not the hostname (wildcard hosts + shared-host
collisions); HTTPRoute hostnames strip ports; scheme-less URL values fail at
render instead of deriving a broken `"://"` origin into `TRUSTED_ORIGINS`;
`SECRETS_ENCRYPTION_KEY` from an existing secret requires an explicit
`auth.secretsEncryptionKeyEnabled` opt-in and the ref is never `optional`
(fail-closed KEK); external-db passwords are never generated (render-time fail
instead); checksum annotations cover the db/redis/smtp/valkey secrets; the
migration Job carries the full deployment env surface plus ArgoCD PreSync hook
annotations when `useHelmHooks=false`; component fullnames truncate before
suffixing; `server.config` collisions with first-class env names fail loudly;
the tightened UI NetworkPolicy always emits a peer; backing-store probes keep
credentials off argv; and the values-coverage audit resolves full dotted paths.

Deferred deliberately (revisit before 1.0): per-credential `existingSecret` on
the built-in engines; NetworkPolicies for the backing stores; a non-root
default securityContext (blocked on testing the upstream root image under
uid 1000 in the kind matrix — DESIGN §3.10's hardened-default claim is
weakened to best-effort accordingly); an `ingress.blockMetrics` convenience;
`resourcesPreset`/`kubeVersion`/`apiVersions`/`clusterDomain` chrome (dropped
as dead values); the checksum-of-secret preimage caveat (cohort-standard
behavior, documented); and chart signing.

**Publishing tool**: chart-releaser today; migration to hevi (tada5hi's own
versioner/releaser, already powering PrivateAIM/helm) is planned once
tada5hi/hevi#52 — the chart-releaser parity checklist (stable
`<chart>-<version>` tags, idempotent skip-existing publish, custom-domain
index merge with CNAME preservation, release notes + OCI push) — is green.
This repo is hevi's designated second consumer.
