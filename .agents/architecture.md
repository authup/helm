# Architecture

`DESIGN.md` is the authoritative rationale. This file is the compact list of
operational invariants that template changes must preserve.

## Authup beta.64 runtime contract

1. **One image, explicit roles.** The supported default args are `start` for the
   combined server, `start core` for the split API, `start console auth|admin|account`
   for split consoles, `start worker` for the worker, and `migration run` for the
   upgrade Job. Do not restore `server/core`, `client/admin-console`, or a second
   image.
2. **Combined is the default.** `server.splitConsoles=false` creates one server
   Deployment. Split mode changes the server role to core and creates console
   Deployments. The auth console is required in split mode because it owns login;
   admin and account remain independently optional.
3. **Role ports come from Authup.** Core listens on 3000. Split auth, admin and
   account consoles listen on 3020, 3021 and 3022. The worker has no listener,
   Service, or HTTP probe.
4. **Worker ownership is explicit.** `worker.enabled=true` sets
   `WORKER_ENABLED=true` on the worker and `WORKER_ENABLED=false` on the server.
   The worker gets database and Redis credentials, but not SMTP, bootstrap
   identity secrets, migrations, or console secrets. It requires the server
   because both roles share chart-managed configuration and credentials.
5. **The filesystem contract is fixed.** Configuration is `authup.yml` at
   `/etc/authup/authup.yml`, provisioning is `/etc/authup/provisioning`, and
   logs are `/var/log/authup`. There is no chart-managed writable root and no
   `WRITABLE_DIRECTORY_PATH`.

## Configuration and state

6. **Strict booleans render quoted.** Authup's strict env reader fails boot on
   malformed values. First-class boolean env values go through
   `toString | quote`.
7. **The cache env var is `REDIS`.** It is a full connection URL, not
   `REDIS_URL`. Because it embeds credentials, it comes from a Secret through
   `secretKeyRef`.
8. **A database is mandatory.** The production image cannot use SQLite.
   `validations.yaml` fails unless built-in PostgreSQL, built-in MySQL, or
   `externalDatabase.host` is configured.
9. **Multiple API replicas require shared cache.** Without Redis, Authup falls
   back to per-process state for authorization codes, revocations and MFA
   challenges. Replica counts above one and HPA therefore fail without cache.
10. **`SECRETS_ENCRYPTION_KEY` is write-once and never generated.** Losing or
    rotating it makes wrapped rows unreadable. Existing-secret use requires an
    explicit opt-in and the reference is never optional.
11. **No config-schema mirror.** First-class values cover load-bearing options;
    `server.config`, extra env carriers and `server.configuration` cover the
    long tail. `server.config` keys that collide with a first-class variable
    fail the render. The small theme manifest is the only deliberate mirrored
    file format.
12. **Secrets never render as pod env literals.** Inline secret values are
    stored in chart-managed Secrets and referenced with `secretKeyRef`. An
    external database password is never invented.
13. **Generated credentials use lookup-or-generate.** The chart-managed auth
    Secret is lookup-stable under Helm and kept with a resource policy. Pure
    template GitOps cannot preserve generated values, so those users must set
    explicit values or existing Secrets.

## URLs and routing

14. **Every browser-facing role shares `server.publicUrl`.** It is either set
    explicitly or derived from server Ingress. Literal and template-rendered
    URLs are both checked for an HTTP scheme. Split consoles receive the same
    `PUBLIC_URL` and use an in-cluster `INTERNAL_URL` for server-side API calls.
15. **Split consoles preserve one origin.** They are exposed under
    `/console/auth`, `/console/admin` and `/console/account`. Generated Ingress
    resources use ingress-nginx regex rewrites. Gateway API routes use
    `URLRewrite` with `ReplacePrefixMatch`. Exact admin/account login and
    callback paths must remain on the API before broader console prefixes.
    A generated console Ingress or HTTPRoute requires the matching server
    resource so those core-owned paths cannot disappear. Split mode rejects a
    path-prefixed server public URL.
16. **HTTPRoute flags are strict.** `route.enabled` accepts a boolean or a
    template-rendered boolean string. `authup.flag` validates every role even
    when that role is disabled, because a non-empty string `"false"` is truthy
    to Go templates.
17. **An empty HTTPRoute match is a catch-all.** A server public URL carrying a
    path requires explicit match and rewrite rules. The validation prevents a
    sub-path deployment from taking over the full hostname.

## Workload and hook safety

18. **Selectors are immutable and minimal.** `authup.matchLabels` emits only
    name, instance and component. User labels never enter selectors. Component
    labels distinguish server, each console, worker and migration pods.
19. **Component names truncate before suffixing.** The suffix-specific budget
    keeps every Service name and label value at 63 characters while preserving
    existing valid resource names. Never widen the `min 52` budget without a
    cross-revision name audit; a renamed kept Secret rotates credentials.
20. **The migration Job is pre-upgrade only.** Fresh installs need regular
    backing resources before the server can initialize the database. On
    upgrades, the Job runs before the rollout. The server sets
    `MIGRATION_ENABLED=false` only during upgrades when this Job owns migration.
21. **Hook inputs must exist before regular resources.** The migration Job
    inlines non-secret config, narrows secrets to database password and optional
    encryption key, skips provisioning, and mounts a hook-scoped copy of
    `authup.yml`. The configuration ConfigMap and migration NetworkPolicy have
    weight -5; the Job has weight 0.
22. **`useHelmHooks=false` is ArgoCD-only.** It emits PreSync resources. Flux
    and plain Helm need native hooks or they apply an immutable Job as a normal
    resource without correct ordering.
23. **Checksum annotations follow every consumed input.** Deployments roll on
    chart-managed env, Secret, provisioning, configuration and theme changes.
    `disableRestartOnChanges` is the explicit escape hatch.

## Network and platform behavior

24. **Policies follow roles.** The server policy accepts enabled split consoles.
    Console policies reach the server. Worker and migration policies provide
    DNS plus release-local database/cache access when external egress is denied.
    External services require the corresponding `extraEgress` rules.
25. **The migration policy is a hook.** A regular NetworkPolicy created after a
    pre-upgrade Job cannot protect that Job. Keep its hook family and ordering
    aligned with the migration Job for Helm and ArgoCD.
26. **Built-in stores are minimal conveniences.** PostgreSQL, MySQL and Valkey
    are vendored single-instance StatefulSets on official images. Production
    users should prefer external or operator-managed services.
27. **`global` stays schema-open.** Helm passes a parent's complete global map
    into subcharts before schema validation. Closing this node makes the chart
    unusable under unrelated umbrella globals.
28. **Every list and map passthrough is tpl-rendered.** Umbrella charts rely on
    this. Free-form maps need `# @schema additionalProperties: true`.

## Validation and generated artifacts

- Cross-field rules and moved-value tombstones live in
  `templates/validations.yaml`.
- `values.yaml` is the source for both generated README value tables and the
  strict JSON schema.
- Every `.Values.*` template path must exist in `values.yaml`; the coverage
  script enforces it.
- `scripts/check-beta64-contract.py` renders real manifests and asserts the
  CLI, env, mount, routing, policy and migration contracts. Add an assertion
  there before changing one of those boundaries.
