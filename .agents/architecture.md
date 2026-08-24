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
9. **Component fullnames truncate the base BEFORE suffixing, on a budget
   derived from the suffix.** `authup.component.fullname`
   (`dict "context" $ "suffix" "server"`) is the single implementation; every
   component name and the migration Job go through it. Truncating first is what
   keeps names DISTINCT (a 63-char fullname would otherwise collapse every
   component onto one name); deriving the budget is what keeps them LEGAL.

   The ceiling is 63, not the 253 a ConfigMap allows, wherever a name becomes a
   DNS-1035 label (Service) or a label value (a Job name is copied into the
   `job-name` pod labels). The old flat `trunc 52` ignored that: `-admin-console`
   rendered a 66-char Service, so any release name from ~43 characters up could
   not install at all, and appending `-migration` to the `-server` name reached
   69. Both are now `min 52 (63 - len(suffix) - 1)`.

   `min 52` is the load-bearing half. The derived budget is WIDER than 52 for
   short suffixes, and widening RENAMES resources on releases whose fullname
   lands between 53 and 55 characters. A renamed Secret carrying
   `helm.sh/resource-policy: keep` orphans the old one and generates a new admin
   password: a silent credential rotation on upgrade. **The budget may only ever
   tighten**, which by construction touches only names too long to exist. Assert
   that when changing it (see testing.md), do not assume it.
10. **The migration Job shares the deployment's env by construction, minus
    what a hook cannot see.** `authup.server.configEnv` (map),
    `authup.server.secretEnv` (list) and the two volume helpers are the single
    sources consumed by both `server/deployment.yaml` and
    `server/migration-job.yaml`; the Job INLINES the config map (a pre-upgrade
    hook would otherwise run against the previous release's ConfigMap). The
    Job is pre-upgrade ONLY (never pre-install: hooks run before backing
    services exist; authup migrates at boot on fresh installs). With
    `useHelmHooks=false` it renders ArgoCD `PreSync` hook annotations instead,
    which is an ArgoCD-only mode: see rule 19.

    Helm applies a pre-upgrade hook BEFORE the release manifest, so every
    NON-HOOK resource the Job references must already exist from the PREVIOUS
    release. A hook resource at a lower weight is the one exception: it is
    created earlier in the same hook phase, which is exactly what the config
    copy below relies on. Four
    helpers take a `hook` flag (`secretEnv`, the two volume helpers and
    `configurationConfigMapName`; `configEnv` does not, it is inlined instead)
    and drop what `migration run` does not read. That flag is the ONE mechanism
    for this: the theme volume used to be a pair of deployment-only defines
    carved out for the same reason, and two conventions in one `volumeMounts:`
    block is how the next mount ends up on the wrong side. `themeEnv` stays
    separate because it splits along a different axis. Dropped:
    `REDIS`, `SMTP` (their Secrets are release resources, and the migration
    builds no cache or mail module) and the provisioning mount (`ProvisionerModule`
    is registered by the start command only). What stays, stays for a reason:
    the writable directory, because under the image's `NODE_ENV=production` the
    logger opens `<writable>/http.log` before the first query and an uncreatable
    path is a hard ENOENT; and the config file, because `migration run` loads
    `authup.server.core.conf` unconditionally and its file-only db keys (`ssl`,
    `socketPath`, `replication`, `extensions`) decide how the migration connects.
    The Job reads that file from a hook-scoped COPY
    (`server/configmap-migration-configuration.yaml`, weight -5) for the same
    reason it inlines the env: the release ConfigMap is either absent or one
    release stale when the hook runs. `USER_ADMIN_PASSWORD` and
    `CLIENT_SYSTEM_SECRET` go the same way: no identity or provisioning module
    on the migration path, and the auth Secret they read is itself a release
    resource. `SECRETS_ENCRYPTION_KEY` deliberately does NOT, even though its
    key is conditional too and the migration does not read it today: rule 6's
    fail-closed posture outranks the one-off break, so a write-once KEK gets its
    own upgrade.

    What the flag cannot reach, i.e. the residuals to keep in mind when adding
    anything to the Job: `DB_PASSWORD` (the Secret behind it changes on an engine
    switch, on adopting a built-in engine after `externalDatabase`, and on a
    first inline `externalDatabase.password`, since `secret-db.yaml` is a release
    resource too); the `serviceAccountName`, whose ServiceAccount renders only
    under `serviceAccount.create`, so flipping that on fails pod ADMISSION with
    no container status to read; and the `extraEnvVarsCM` / `extraEnvVarsSecret`
    / `extraVolumes` passthroughs, whose targets are operator-owned unless the
    operator ships them through `extraDeploy`, which renders them into the
    release manifest and therefore after the hook.
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
    The ONE mirrored schema is the theme manifest (`server.theme.title` /
    `logo` / `tokens` / ... compose `theme.json`), and it earns the exception
    on three counts: the file is a fixed 8-key document rather than a growing
    config surface, authup fails the BOOT on an unknown key or a malformed
    token so a typo has no cheaper detector, and the alternative is a JSON
    blob inside a YAML string with no schema at all. It stays worth it only
    while the manifest stays small: `files` remains the escape hatch, and a
    hand-written `theme.json` there is still supported (the two are mutually
    exclusive by validation).
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
    `server.route.enabled` / `adminConsole.route.enabled` extend this to a
    BOOLEAN, read through `authup.flag`. That reader is strict by necessity:
    the schema is widened to `[boolean, string]` so it no longer rejects
    garbage, and a rendered `"false"` is a non-empty (truthy) string, so a
    plain `if` would create the route exactly when the parent switched it off.
    All six read sites (2 HTTPRoutes, 2 validations, 2 NOTES) convert together
    or the sub-path catch-all guard of rule 18 stops covering umbrella users.
17. **`global` must stay open in the schema.** helm copies a parent chart's
    ENTIRE `global` map into every subchart before validating that subchart's
    schema, so `additionalProperties: false` there makes the chart
    uninstallable as a dependency of any umbrella that sets a global this
    chart does not declare. `values.yaml` carries the
    `# @schema additionalProperties: true` opt-out and `ci/default-values.yaml`
    a stray global key as the regression guard. The chart reads only
    `imageRegistry` / `imagePullSecrets` / `defaultStorageClass` and ignores
    the rest.
18. **An HTTPRoute rule with no `matches` is a catch-all.** The Gateway API
    defaults an empty `matches` to PathPrefix `/`, and route hostnames come
    from the public URL's ORIGIN (the path is dropped), so a sub-path
    deployment would silently take over the whole shared hostname.
    `validations.yaml` fails that combination; `route.matches` / `route.filters`
    are the raw passthroughs that express it (authup always serves at `/`, so
    the prefix must be matched AND rewritten away).
19. **`useHelmHooks=false` is an ArgoCD-only mode.** ArgoCD renders with
    `helm template` and never executes Helm hooks, so it needs its own
    `argocd.argoproj.io/hook` annotations. Flux is the opposite: helm-controller
    runs a real `helm upgrade` and honours Helm hooks natively. Turning them off
    there applies the migration Job as an ordinary release resource, and
    `Job.spec.template` is immutable, so the next upgrade that touches the pod
    template (image tag, `appVersion` label, a new env) fails to patch it. A
    content-hashed Job name would make that apply-able but not correct: helm
    orders a plain Job AFTER the Deployment and does not wait for it, which is
    the ordering the Job exists to provide. So the value stays doc-scoped to
    ArgoCD and NOTES warns when it is set. ArgoCD also maps Helm hooks onto its
    own sync phases, so `true` works there as well; the flag only chooses which
    annotation family drives the Job.

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
