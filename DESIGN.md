# Authup Helm Chart Design

Status: implemented. This is the authoritative architecture record for the
chart. It incorporates evidence from the Authup monorepo and comparative
reviews of authelia/chartrepo, goauthentik/helm, bitnami/charts and
PrivateAIM/helm.

## 1. Goals and constraints

1. Provide Bitnami-grade values ergonomics without external chart dependencies:
   existing-secret key mapping, tpl-rendered extension points, predictable
   naming, diagnostics and standard workload controls.
2. Deploy every supported Authup v1.0.0-beta.64 role from the one upstream
   `authup/authup` image.
3. Keep a default install useful: a combined Authup server plus built-in
   PostgreSQL, while making external database and cache services the documented
   production path.
4. Preserve a single browser origin in combined and split topologies.
5. Keep the repository solo-maintainable with generated documentation/schema,
   executable render contracts and release-please-owned versions.

The chart has no dependencies. The Bitnami licensing change, the retirement of
k8s-at-home/common, and Authelia's removal of database subcharts all make small
vendored backing-service templates cheaper and more reliable than another
library or database chart dependency.

## 2. Runtime topology

Authup beta.64 replaces app-path arguments with direct CLI roles:

| Chart role | Args | Port | Default |
|---|---|---:|---|
| combined server | `start` | 3000 | yes |
| core API | `start core` | 3000 | split mode |
| auth console | `start console auth` | 3020 | split mode, required |
| admin console | `start console admin` | 3021 | split mode, optional |
| account console | `start console account` | 3022 | split mode, optional |
| worker | `start worker` | none | optional |
| migration Job | `migration run` | none | optional upgrades |

`server.splitConsoles=false` keeps the minimum topology: one Deployment runs
the API, enabled consoles and in-process worker behavior. Setting it true
changes that Deployment to the core role and creates explicit console
Deployments. The auth console cannot be disabled in split mode because it owns
the login flow. Admin and account consoles can be scaled or disabled
independently.

The worker is a separate Deployment only when `worker.enabled=true`. Its process
gets `WORKER_ENABLED=true`; the API gets `WORKER_ENABLED=false`. It shares
database, cache, configuration and log mechanics with core, but it has no
Service, ports or HTTP probes. It does not receive SMTP or bootstrap identity
secrets because those modules are outside the worker role.

Each role has explicit templates. Their structural duplication is deliberate:
authentik built and later removed a generic role loop because heterogeneous
probes, ports, Services and settings became harder to understand. Shared
helpers are limited to genuinely identical env, mount, ingress and naming
mechanics.

## 3. Configuration model

Authup beta.64 reads one `authup.yml` schema across roles. The chart mounts an
inline or existing ConfigMap at `/etc/authup/authup.yml`. Environment variables
remain the primary interface and override file values.

The chart exposes three layers:

1. First-class values for load-bearing database, URL, feature, security and
   role-ownership settings.
2. Secrets through `valueFrom.secretKeyRef`; Authup has no equivalent `*_FILE`
   interface.
3. Tpl-rendered escape hatches (`server.config`, extra env carriers, volumes and
   `server.configuration`) for the long tail.

The chart does not mirror the complete application configuration schema. That
would require release-by-release maintenance like Authelia's large ConfigMap
template. `server.config` rejects names owned by first-class values, preventing
duplicate ConfigMap keys and hidden overrides. The small, stable theme manifest
is the one exception because composing it from structured values catches errors
that otherwise surface only during application boot.

Filesystem locations follow the image contract:

- configuration: `/etc/authup/authup.yml`
- provisioning: `/etc/authup/provisioning`
- file logs: `/var/log/authup`
- npm cache: `/tmp/.npm-cache`

There is no chart-managed writable root and no `WRITABLE_DIRECTORY_PATH`.

## 4. URLs and single-origin routing

`server.publicUrl` is the deployment-wide public URL and OIDC issuer. When it
is empty, the chart derives it from server Ingress. Scheme checks run both on
literal values and after tpl rendering.

In combined mode the one server exposes every enabled surface. Split mode must
preserve the same origin:

- `/console/auth` routes to the auth console
- `/console/admin` routes to the admin console
- `/console/account` routes to the account console
- exact admin/account login start and callback paths route to core
- all remaining API paths route to core

The console listeners serve from `/`, so the public prefix must be stripped.
Generated Kubernetes Ingress resources deliberately target ingress-nginx and
use its regex rewrite annotations. Gateway API HTTPRoutes use portable
`URLRewrite` filters with `ReplacePrefixMatch`.

The three public console prefixes are fixed parts of the Authup beta.64
contract, not chart values. Enabling a generated console Ingress or HTTPRoute
requires the corresponding server resource, which carries both the API and the
core-owned login/callback exceptions. A path-prefixed deployment-wide public
URL is rejected in split mode because it cannot preserve these root prefixes.

Each split console gets the shared `PUBLIC_URL` plus an `INTERNAL_URL` pointing
at the core Service for server-side calls. Database, Redis, SMTP and bootstrap
identity secrets never enter console pods.

An empty HTTPRoute match defaults to a root catch-all. The chart therefore
fails a server route whose derived public URL contains a sub-path but supplies
no explicit match and rewrite. `route.enabled` supports boolean strings for
umbrella charts, and the strict helper validates those values even when the
corresponding role is disabled.

## 5. Database and cache

The published production image cannot use SQLite. Exactly one of these paths is
required:

- built-in PostgreSQL (default)
- built-in MySQL
- `externalDatabase`

The built-in services are small single-instance StatefulSets on official
images. They are appropriate for development and small deployments, not a
replacement for a production database operator or managed service.

Database dispatch helpers hide the active engine from consuming templates and
always put passwords in Secrets. The chart never generates credentials for an
external database it does not own.

Authup's cache variable is `REDIS`, a full connection URL. Because the URL can
contain a password, it is also Secret-backed. More than one API replica or an
API HPA requires Redis: the in-memory fallback makes authorization codes,
revocations and MFA challenges pod-local and breaks correctness.

## 6. Secrets

The chart-managed auth Secret uses explicit value, existing lookup, then random
generation for the initial admin password and optional system-client secret.
`helm.sh/resource-policy: keep` preserves it across uninstall/reinstall
mistakes. Pure template GitOps cannot make lookup-generated values stable, so
those users must provide explicit values or an existing Secret.

`SECRETS_ENCRYPTION_KEY` is different: it is never generated. It is effectively
write-once because losing or rotating it makes wrapped MFA seeds and signing
keys unreadable. References are fail-closed and existing-secret use requires an
explicit enabled flag.

## 7. Migrations and upgrades

Authup core can initialize and migrate at startup. A pre-install migration Job
would run before chart-managed databases exist, so fresh installs rely on core
startup and its generous startup probe.

`server.migration.enabled=true` creates a pre-upgrade Job. On upgrade, and on
every ArgoCD sync when `useHelmHooks=false`, core gets `MIGRATION_ENABLED=false`
and the Job owns schema migration before pods roll.
Non-persistent built-in databases are the exception: their rollout replaces the
database after the hook, so core initializes the replacement at boot. This
avoids concurrent DDL when the migrated database survives the rollout.

Helm creates hooks before regular release resources. The Job therefore:

- inlines the next release's non-secret config
- receives database password and optional encryption key only
- omits Redis, SMTP, bootstrap identity and provisioning inputs
- mounts a hook-scoped copy of `authup.yml`
- mounts `/var/log/authup`

The hook configuration ConfigMap and migration NetworkPolicy run at Helm
hook-weight -5; the Job runs at 0. This ensures configuration and egress policy
exist before the pod. `useHelmHooks=false` emits ArgoCD annotations instead. It
is not a Flux or plain-Helm mode because a normal Job has immutable pod
templates and no correct upgrade ordering.

Under ArgoCD the Job is a Sync-phase hook (not PreSync), at sync-wave -1: a
PreSync hook runs before every Sync-phase resource, including the built-in
database, which deadlocked a fresh install (issue #30). Everything the Job's
pod spec can reference (the built-in database, the ServiceAccount, and the
auth/external-db Secrets when they carry values the Job needs) renders at wave
-10; the hook-scoped ConfigMap and NetworkPolicy at -5. ArgoCD waits for each
wave to be healthy before starting the next, so the Job always runs after its
own inputs exist, and still before the server Deployment (implicit wave 0).

## 8. Network policy

Policies are opt-in and permissive by default. When tightened:

- core ingress accepts the enabled split console components plus configured
  ingress-controller selectors
- each console accepts HTTP ingress and can reach core
- worker egress permits DNS and release-local database/cache pods
- the hook-scoped migration policy permits DNS and release-local backing pods
- external services require operator-supplied `extraEgress`

Component and instance labels scope every peer. The migration policy must remain
a hook; a regular policy would be created after the hook pod needs it, which is
the root cause of issue #22.

## 9. Kubernetes resource conventions

- Selectors contain only name, release instance and component. User labels do
  not enter immutable selectors.
- Component fullnames truncate the base before suffixing with a suffix-specific
  budget. The budget may tighten to make invalid names legal, but must not widen
  and rename existing resources. A renamed kept Secret can rotate credentials.
- Checksums roll pods when any consumed chart-managed env, Secret,
  configuration, provisioning or theme input changes.
- Tpl rendering applies to list/map extension points so umbrella charts can
  inject their own values.
- The generated schema is strict except for intentionally extensible maps and
  the `global` map. Helm copies the parent's full global map into subcharts, so
  that node must stay open.

## 10. Validation and testing

Cross-field constraints live in `templates/validations.yaml`: database choice,
replica/cache requirements, security combinations, URL shape, Ingress hostname,
strict flags, moved-value tombstones and split-mode dependencies.

`scripts/check-beta64-contract.py` renders manifests and asserts the upstream
integration boundary: args, ports, role env, secret isolation, mounts,
install/upgrade migration ownership, prefix rewrites, exact API routes, hook
annotations and NetworkPolicy peers. `make test` runs this alongside lint, every
CI values render and the values-coverage audit. CI additionally regenerates the
README/schema and installs the scenario matrix on kind.

## 11. Releases

release-please owns `Chart.yaml` version, both changelogs and the manifest.
`appVersion` tracks Authup independently. Breaking 0.x chart changes use a
Conventional Commit breaking marker and are recorded in `BREAKING.md` with a
fail-loud old-value guard when a key moves.

Publishing uses hevi/chart-releaser to create the GitHub chart release, update
the classic repository index and push the OCI artifact. Built artifacts remain
idempotent on reruns.

## 12. Deliberate non-goals

| Not doing | Reason |
|---|---|
| Bitnami/common or database subcharts | licensing and ecosystem churn outweigh a few local helpers/templates |
| Full Authup config-file templating | env-first configuration plus escape hatches avoid a schema treadmill |
| Generic role-loop templates | explicit heterogeneous roles are easier to audit and change |
| Pre-install migration Job | hooks run before chart-managed backing services exist |
| Service or HTTP probes for worker | the beta.64 worker has no HTTP listener |
| Different public origins for split consoles | Authup's browser and login contracts use one deployment-wide public URL |
| PVC for file logs | application state is in the database; log persistence belongs in collection infrastructure |
| Run-without-database demo mode | impossible in the production image |

Deferred before chart 1.0: per-credential existing Secrets for built-in stores,
backing-store NetworkPolicies, a non-root default after upstream image support,
an ingress metrics-blocking convenience, and chart signing.
