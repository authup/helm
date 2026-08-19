# authup (the application)

Repo: https://github.com/authup/authup (local checkout commonly at
`/opt/projects/authup/authup`). The chart encodes facts about the app; verify
against these sources when authup releases change behavior. Pinned against the
v1.0.0-beta.62 line (chart `appVersion`).

## Image / entrypoint contract

| Fact | authup source | Chart counterpart |
|---|---|---|
| One image `authup/authup`, arg-dispatched entrypoint (`server/core start`, `client/admin-console start`, `server/core migration run`, `server/core healthcheck`) | `Dockerfile`, `entrypoint.sh` (repo root) | `args` in `templates/{server,admin-console}/deployment.yaml`, `server/migration-job.yaml` |
| Entrypoint force-exports `PORT=3000` / `NUXT_PORT=3000` (chart-set PORT is dead) | `entrypoint.sh` | containerPort pinned 3000 everywhere |
| Image runs as root; writable paths `/usr/src/app/writable` + npm cache | `Dockerfile` (`WRITABLE_DIRECTORY_PATH`, no `USER`) | emptyDir mounts + `npm_config_cache=/tmp/.npm-cache`; root securityContext default |
| `latest`/`<version>`/`beta`/`next` tags | `.github/workflows/release.yml`, `docker-nightly.yml` | `image.tag` defaults to `Chart.AppVersion` |
| `authup` CLI supervisor NOT routable through the entrypoint | `entrypoint.sh` case statement | chart never offers a combined pod |
| An unknown service arg EXITS 1 since beta.59 (it used to exit 0 and start nothing); `client/web` was renamed `client/admin-console` with no alias | `entrypoint.sh` `*)` branch | chart already passes `client/admin-console` |

## server-core env surface

Source of truth: `apps/server-core/src/app/modules/config/`
(`constants.ts` = `ConfigEnvironmentVariableName` enum, `read/env.ts`,
`normalize.ts` defaults + cross-field boot validation, `validator.ts`).
Docs mirror: `docs/src/guide/deployment/configuration-server-core*.md`.

| authup env | Chart source |
|---|---|
| `DB_TYPE/HOST/PORT/USERNAME/PASSWORD/DATABASE` (mysql, postgres, better-sqlite3 only; sqlite forbidden in production) | `_database.tpl` dispatch + `authup.server.configEnv` / `secretEnv` |
| `REDIS` (bool or full URL; there is NO `REDIS_URL`) | `secret-redis.yaml` / `valkey/secret.yaml` connection-string key |
| `SMTP` (URL form; per-field SMTP is config-file-only) | `secret-smtp.yaml` |
| `PUBLIC_URL`, `TRUSTED_ORIGINS`, `TRUST_PROXY` (app default trusts every hop; chart pins "1") | `_urls.tpl` + `authup.server.configEnv` |
| `REGISTRATION_ENABLED`, `PASSWORD_RECOVERY_ENABLED`, `EMAIL_VERIFICATION_ENABLED`, `MFA_ENABLED`, `MFA_REQUIRED` (strict booleans: unparsable value crashes boot) | `server.features.*` / `server.mfa.*`, always quoted |
| `ACCOUNT_CONSOLE_ENABLED` (beta.62, default true): serves the `/account` self-service SPA off the IdP origin | `server.features.accountConsole` |
| `THEME_DIRECTORY_PATH` / `THEME_FRAGMENTS_ENABLED` (beta.59, EXPERIMENTAL): operator theme for the two served consoles; manifest at `<root>/theme.json`, HTTP mount root is `<root>/assets` only | `server.theme.*` (the chart composes theme.json) |
| `AUTH_CONSOLE_PATH` / `ACCOUNT_CONSOLE_PATH`: substitute a whole console package, boot-asserted `CONTRACT_VERSION` | deliberately NOT first-class; `server.config` + `extraVolumes` escape hatch |
| `USER_ADMIN_PASSWORD(_RESET)`, `CLIENT_SYSTEM_ENABLED/SECRET(_RESET)` | `auth.*` values + chart-managed secret |
| `SECRETS_ENCRYPTION_KEY` (base64 32 bytes; write-once, removal with wrapped rows fails loud) | `auth.secretsEncryptionKey(+Enabled)`, never generated, never optional |
| Cross-field boot validations (throttle needs event log, mfaRequired needs mfaEnabled, KEK length) | mirrored as render-time guards in `templates/validations.yaml` |
| `TRUSTED_ORIGINS` rejects `**` in a host at boot since beta.59 (`config/origins.ts`, `patternHasGlobstarInAuthority`); a single `*` is a supported host wildcard | `authup.assertTrustedOrigin` in `_urls.tpl`, asserted after tpl rendering |

Config file: `authup.server.core.conf` in the process cwd
(`app/modules/config/read/fs.ts`; env always wins) -> `server.configuration` /
`server.existingConfigmap` mount. Provisioning files:
`<writable>/provisioning/*` scanned at boot, fail-closed
(`app/modules/provisioning/module.ts`) -> `server.provisioning.*` mount.

## client-admin-console env surface

Runtime config only (prebuilt Nitro bundle; bare `API_URL` etc. are build-time
and dead): `apps/client-admin-console/nuxt.config.ts`,
`docs/src/guide/deployment/configuration-client-admin-console.md`.
`NUXT_PUBLIC_API_URL` (browser-reachable server URL), `NUXT_PUBLIC_PUBLIC_URL`,
`NUXT_API_URL` (SSR-side override), `NUXT_PUBLIC_COOKIE_DOMAIN` (deliberately
never set by the chart: sharing a cookie domain with the server origin is
unsupported per `.agents/architecture.md` in the monorepo),
`NUXT_PUBLIC_CLIENT_ID` (beta.59+, defaults to the per-realm built-in
`admin-console` client; fork-only override, reachable via
`adminConsole.config`). Chart counterpart: `_admin-console-env.tpl`.

## Operational contract

- `GET /` = anonymous status endpoint `{version, date, features}`
  (`adapters/http/controllers/workflows/status/`) -> liveness/readiness for
  server-core; client-admin-console uses its SSR `/`.
- server-core auto-runs migrations + provisioning at boot
  (`app/modules/database/module.ts`; no off-switch) -> generous startupProbe;
  optional pre-upgrade migration Job for multi-replica DDL serialization.
- Replicas > 1 without redis: per-process MemoryCache breaks auth codes,
  revocations, MFA challenges (`app/modules/cache/module.ts`) -> hard
  validation in the chart.
- `GET /metrics` is unauthenticated (`middlewarePrometheus` default on) ->
  ServiceMonitor targets the Service; ingress warning in values/NOTES.
- In-process cron sweepers (oauth2-cleaner, event-cleaner) are idempotent
  deletes; no leader election needed.
- Reserved client names: `admin-console` and `account-console` are provisioned
  as built-in system clients in EVERY realm and take over a pre-existing client
  of that name (beta.59). The shared per-realm `web` client was removed in the
  same release; `TRUSTED_ORIGINS` now feeds the system clients' redirect
  allowlists. NOTES warns against declaring either name in
  `server.provisioning`.
- beta.60 ships a heavy migration (140 indexes, MySQL `varchar(36)` ->
  `varchar(255)` table rewrites, three dropped tables) and beta.62 adds a
  unique constraint on `auth_identity_provider_accounts` that ABORTS the boot
  on pre-existing duplicates. Both are arguments for
  `server.migration.enabled` on an upgrade, not just for multi-replica.
