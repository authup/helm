# Architecture

`DESIGN.md` at the repo root holds the full design rationale with evidence.
This file lists the operational invariants an agent must not break when
editing templates or values.

## Load-bearing rules

1. **containerPort is always 3000, for both services.** The authup image
   entrypoint force-exports `PORT=3000` / `NUXT_PORT=3000`; a chart-set `PORT`
   env is dead. Never surface a containerPort value.
2. **Strict booleans render quoted.** authup's `readBoolStrict` env reader
   (`EVENT_LOG_*`, `MFA_*`, `LOGIN_ATTEMPT_THROTTLE_ENABLED`) crashes the boot
   on unparsable values. Every boolean env in `authup.server.configEnv` goes
   through `toString | quote`.
3. **The cache env var is `REDIS`** (a full connection URL), not `REDIS_URL`
   (a documentation ghost that never existed in authup source). The URL embeds
   the password, so it always lives in a Secret and reaches the pod via
   `valueFrom.secretKeyRef`.
4. **A database is mandatory.** The published image bakes
   `NODE_ENV=production`, which forbids sqlite. `validations.yaml` hard-fails
   when neither a built-in engine nor `externalDatabase.host` is configured.
5. **replicas > 1 requires a cache.** Without redis, authup falls back to a
   per-process memory cache: authorization codes, token revocations and MFA
   challenges break across replicas (functional breakage, not just
   performance). `validations.yaml` enforces this.
6. **`SECRETS_ENCRYPTION_KEY` is write-once and never generated.** Losing or
   rotating it bricks wrapped MFA seeds and signing keys. From an existing
   secret it requires the explicit `auth.secretsEncryptionKeyEnabled` opt-in,
   and the secretKeyRef is never `optional:` (a silently missing KEK would
   fail open into plaintext-at-rest).
7. **URL values must carry a scheme, asserted twice.** `validations.yaml`
   checks literal values; the `_urls.tpl` helpers re-assert AFTER tpl
   rendering (`authup.assertUrlScheme`), because a template-valued URL only
   materializes there. `authup.urlOrigin` returns "" unless both scheme and
   host parse, so a broken origin can never reach `TRUSTED_ORIGINS`.
8. **Selectors are immutable and minimal.** `authup.matchLabels` emits only
   name + instance + component. `commonLabels` / `podLabels` must never leak
   into a selector. `app.kubernetes.io/component` separates the two services'
   Services within one release.
9. **Component fullnames truncate the base BEFORE suffixing**
   (`trunc 52` then `-server` / `-ui` / engine suffix), so long release names
   cannot collapse every resource onto one identical name.
10. **The migration Job shares the deployment's env by construction.**
    `authup.server.configEnv` (map) and `authup.server.secretEnv` (list) are
    the single sources consumed by both `server/deployment.yaml` and
    `server/migration-job.yaml`; the Job INLINES the config map (a pre-upgrade
    hook would otherwise run against the previous release's ConfigMap). The
    Job is pre-upgrade ONLY (never pre-install: hooks run before backing
    services exist; authup migrates at boot on fresh installs). With
    `useHelmHooks=false` it renders ArgoCD `PreSync` hook annotations instead.
11. **Checksum annotations roll pods on config or secret changes.** The server
    deployment checksums the env map plus every chart-managed secret it
    consumes (auth, external-db, redis, smtp, provisioning, configuration),
    each guarded by the same condition the secret renders under.
    `disableRestartOnChanges` opts out.
12. **Secrets never render as pod env literals.** Inline values land in
    chart-managed Secrets referenced via `secretKeyRef`; the external-db
    password is never generated (render-time fail instead: the chart does not
    invent credentials for a database it does not manage).
13. **Generated credentials use lookup-or-generate** (`authup.secret.rawValue`)
    with `helm.sh/resource-policy: keep`. This is incompatible with pure
    GitOps renders (lookup is inert under `helm template` / ArgoCD): NOTES and
    the README warn; GitOps users set explicit values or `existingSecret`.
    Values that feed BOTH a password key and a composed connection string
    (valkey) are resolved once per render inside a single Secret template so
    the two keys cannot diverge on fresh installs.
14. **No config-file re-templating.** authup is env-configured; the chart
    renders env vars plus escape hatches (`server.config`,
    `extraEnvVars`/`extraEnvVarsCM`/`extraEnvVarsSecret`,
    `server.configuration` file mount). Never mirror authup's config schema in
    templates (Authelia's 714-line configMap treadmill is the cautionary tale).
    `server.config` keys colliding with first-class env names fail the render.
15. **URL derivation is the chart's core UX.** `PUBLIC_URL`,
    `NUXT_PUBLIC_API_URL`, `NUXT_PUBLIC_PUBLIC_URL` derive from the two
    ingress blocks; the UI origin is auto-appended to `TRUSTED_ORIGINS`
    (`server.trustedOriginsAppendAdminConsole`). A missing trusted origin is the #1
    dead-login misconfiguration. The chart never sets
    `NUXT_PUBLIC_COOKIE_DOMAIN`: sharing a cookie domain between client-admin-console
    and the hosted auth pages is unsupported by authup.
16. **Every list/map passthrough is tpl-rendered** via
    `authup.tplvalues.render`, so umbrella charts can inject template
    expressions (the PrivateAIM lesson: their untemplatable `existingSecret`
    forced a hardcoded-names table).

## Values conventions

- bitnami-shaped keys: `fullnameOverride`, `existingSecret` + `secretKeys`
  key-mapping, `extraEnvVars`/`extraEnvVarsCM`/`extraEnvVarsSecret`,
  `extraVolumes`/`extraVolumeMounts`, `initContainers`/`sidecars`,
  `extraDeploy`, `commonLabels`/`commonAnnotations`, `diagnosticMode`,
  `useHelmHooks`.
- `values.yaml` is the single documentation source: `# --` comments feed
  helm-docs, `# @schema` blocks feed helm-schema. Every free-form or
  extensible map carries `# @schema additionalProperties: true` - the
  generated schema is strict (`additionalProperties: false`) everywhere else,
  which is what turns value typos into install-time errors. When adding a new
  map value that users extend (annotations, selectors, resources-like), add
  the annotation or the schema will silently forbid its use.
- Cross-field rules that the JSON schema cannot express live in
  `templates/validations.yaml` (render-nothing fail-fast guards). When a value
  moves, add a tripwire there that names the new location, and record the
  migration in `BREAKING.md`.
- **Values-coverage audit**: every `.Values.*` path referenced by any template
  must resolve in `values.yaml` (`scripts/check-values-coverage.py`, run by
  `make lint-values-coverage` and CI). Strict schema + a missing key = a
  silently unusable feature (the Authelia HPA-metrics trap).
