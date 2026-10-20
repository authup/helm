# authup application mapping

Repository: https://github.com/authup/authup. A local checkout commonly exists
at `/opt/projects/authup/authup`. This mapping is pinned to v1.0.0-beta.71, the
chart `appVersion`.

Verified against tag commit `55c8818635e7e1002ad8db074ff6d46de2a6f585`.
beta.70 to beta.71 changed no image entrypoint, CLI role, port or
environment-variable contract the chart owns: `Dockerfile` and `entrypoint.sh`
are unchanged, `apps/authup/src` and `packages/server-config/src` changed only
a comment and a trailing newline, and no database migration was added.
`docs/src/guide/deployment/upgrading.md` gains no operator action.
Deployment-facing facts, none of which needs a chart value:

- `apps/server-auth-console/src/render.ts`: the auth console's API client keeps
  the public `apiUrl` as its base URL and only dials `apiInternalUrl` at the
  transport, so identity provider links no longer leak the in-cluster
  `INTERNAL_URL` the chart sets on split consoles (#3753).
- `@node-rs/bcrypt` moved from 1.10.9 to 2.0.0 (dependency bump, no chart impact).

## Previous deployment changes

beta.69 to beta.70 changed no image entrypoint, CLI role, port or
environment-variable contract the chart owns: `Dockerfile`, `entrypoint.sh`,
`apps/authup/src` and `packages/server-config/src` are unchanged, and no
database migration was added. Deployment-facing facts
(`docs/src/guide/deployment/upgrading.md`, "Next release (after
v1.0.0-beta.69)"), none of which needs a chart value:

- Single-record permission checks name the record's realm. `realm_update` /
  `realm_delete` at `own` reach manage only the actor's realm; self-manage
  grants at `realmScope: none` stop permitting self-edits. Relevant to
  operator-supplied `server.provisioning` files only; the chart ships none.
- A token lacking the `global` scope is evaluated with its identity and
  without its grants (previously the identity was withheld).
- Server adapters verify through vouchly/jose: RSA signature keys must be
  >= 2048 bits and `POST /keys` refuses shorter imports. Generated keys are
  2048 bits.
- `apps/server-core/src/app/modules/components/module.ts` now stops every
  component schedule, then awaits in-flight passes before the database tears
  down. Shutdown therefore waits for a running sweep; a pass that outlasts
  `worker.terminationGracePeriodSeconds` (30) is still cut off by SIGKILL, as
  before. Worker health and `WORKER_PORT` are unchanged.

beta.68 to beta.69 changed no image entrypoint, CLI role, port or
environment-variable contract the chart owns: `Dockerfile`, `entrypoint.sh`
and `apps/authup/src` are unchanged. It is a security-hardening release
(`docs/src/guide/deployment/upgrading.md`, "Next release (after
v1.0.0-beta.68)"). Deployment-facing facts:

- Migrations `1790579515549-DigestUserWorkflowCodes` (activation and reset
  codes stored as SHA-256 digests) and `1790600000000-RealmAdminRolePermissionReach`
  run on PostgreSQL and MySQL through the pre-upgrade Job or a server boot.
  Codes an older replica writes during a rolling upgrade stop working.
- Tokens are bound to their realm. On a Redis cache the `oauth2_token_claims*`
  keys should be dropped once after the upgrade, or tokens verified before it
  skip the new key check until they expire. The migration Job deliberately has
  no Redis access, so this stays an operator action (README upgrade note).
- Rate limiting runs in two stages
  (`apps/server-core/src/adapters/http/middleware/built-in/rate-limit.ts`):
  300 failed authentications a minute per address before authentication, then
  per-identity budgets after it. New env `RATE_LIMIT_ANONYMOUS_MAX` (1200),
  `RATE_LIMIT_USER_MAX` (6000), `RATE_LIMIT_CLIENT_MAX` (300000) in
  `packages/server-config/src/sections/core/schema.ts`, reachable through
  `server.config`. Only loopback sources are skipped, so in split mode every
  anonymous auth-console render reaches core from the console pod address via
  `INTERNAL_URL` and shares that pod's anonymous budget (unchanged in effect
  from beta.68, but now tunable). The console stops forwarding visitor tokens
  after 100 refusals a minute to stay below the first stage
  (`apps/server-auth-console/src/session.ts`).
- `USER_ADMIN_ENABLED` now uses the strict boolean reader and `false`
  deactivates an existing admin. The chart sets no such variable; a
  `server.config` value is quoted like every carrier.
- SMTP verifies the relay certificate. Through the chart's `SMTP` connection
  string the only opt-out is `?tls.rejectUnauthorized=false`; the file form
  `smtp.rejectUnauthorized` goes in `server.configuration`.
- On an https public URL at the origin root the console session cookie becomes
  `__Host-authup_session`. The split-mode root-URL rule means every chart
  topology on https gets the new name: console users sign in once more.
- Authup does not send `Strict-Transport-Security`; the proxy should
  (`docs/src/guide/deployment/nginx.md`). ingress-nginx does so for TLS hosts by
  default; Gateway API routes need a gateway-side policy.
- `CLIENT_SYSTEM_ENABLED` now sets the system client's `active` on every boot,
  in both directions. The chart renders it only when
  `auth.systemClientEnabled=true`, so turning that value off leaves the
  client's current state alone rather than deactivating it.

Beta.68 added the worker health listener:

- `apps/server-core/src/app/modules/components/health.ts` serves `GET /` and
  `HEAD /` with 200/503; other paths return 404. `app/factory.ts` includes this
  module only for the worker role, after database schema verification.
- `packages/server-config/src/sections/core/schema.ts` reads `WORKER_PORT`
  (`core.worker.port`), falling back to `PORT` when unset. The listener binds
  `core.host`. The chart sets `WORKER_PORT` from `worker.containerPorts.http`
  so the listener and named readiness port agree even with shared config.
- `components/module.ts` reports a sweep overdue after five minutes without a
  successful pass (including the startup allowance), or after a running pass
  exceeds 30 minutes. `docs/src/guide/deployment/worker.md` recommends readiness
  only: database outages should not trigger liveness restarts.
- The image and CLI healthchecks still follow `PORT`, not `WORKER_PORT`.
  Kubernetes uses the chart's explicit readiness probe instead.
- CLI role args, database ownership and worker secret requirements are unchanged.
  The chart enables the dedicated worker by default; `worker.enabled=false`
  preserves in-process sweeps. Fresh-install workers can restart until the
  server initializes the schema; the optional migration Job orders upgrades.

beta.66 to beta.67 changed no image entrypoint, CLI role, port or
environment-variable contract the chart owns: `Dockerfile`, `entrypoint.sh`
and `packages/client-auth-console` are unchanged, and `apps/authup/src` only
adds `authup api <entity> stats` beside the unchanged `start` tree.
Deployment-facing facts, none of which needs a chart value
(`docs/src/guide/deployment/upgrading.md`):

- Migration `1789930726252-PathsAndEventAggregates` (folders for users and
  clients, daily event rollups) runs on PostgreSQL and MySQL. The pre-upgrade
  migration Job or a server boot with `MIGRATION_ENABLED` applies it.
- Boot-time migrations now take a database lock, so replicas starting together
  with `MIGRATION_ENABLED` on no longer race. A waiting replica fails its boot
  after 60 seconds and is restarted. The chart's migration Job ownership is
  unchanged.
- Database sessions are pinned to UTC (`TimeZone` on PostgreSQL, `time_zone`
  on MySQL). The built-in PostgreSQL and MySQL images run in UTC and the chart
  sets no driver timezone option. A driver option that contradicts the pin (a
  MySQL `timezone` other than UTC, `dateStrings`, `typeCast`, a PostgreSQL
  `TimeZone` in the startup `options`) or a MySQL replication setup, passed
  through `server.config`, now stops the boot.
- The new config field `eventLogAggregateRetentionDays`
  (`EVENT_LOG_AGGREGATE_RETENTION_DAYS`, default 0 = forever,
  `packages/server-config/src/sections/core/schema.ts`) is reachable through
  the long tail (`server.config.EVENT_LOG_AGGREGATE_RETENTION_DAYS`). The
  rollup task runs wherever the worker sweeps run: the `start` process, or
  the `start worker` Deployment when `worker.enabled=true`.
- Earlier deployment facts still hold: the device authorization grant rides
  the server catch-all and the `/console/auth` prefix (beta.66), and a bundle
  substituted through `AUTH_CONSOLE_PATH` must match auth console render
  contract version 5.

## Image and CLI

| Authup contract | Upstream source | Chart counterpart |
|---|---|---|
| One `authup/authup` image with direct CLI args | `Dockerfile`, `entrypoint.sh` | `authup.appImage`; every application Deployment |
| Combined service: `start` | `apps/authup/src/commands/start.ts` | `server/deployment.yaml` default |
| API only: `start core` | `apps/authup/src/module.ts`, command tests | server when `server.splitConsoles=true` |
| Split consoles: `start console auth`, `start console admin`, `start console account` | `apps/authup/src/console/`, `apps/server-*-console/` | the three console directories |
| Background worker: `start worker` | `apps/authup/src/module.ts`, `apps/server-core/src/app/modules/components/module.ts` | `worker/deployment.yaml` |
| Migration: `migration run` | `apps/server-core/src/cli/commands/migration.ts` | `server/migration-job.yaml` |
| Core port 3000; console ports 3020/3021/3022 | `packages/server-config/src/sections/*/schema.ts`, `Dockerfile` | role `containerPorts` and Services |
| Worker health port, default 3000 | `sections/core/schema.ts`, `components/health.ts` | `worker.containerPorts.http`, readiness probe; no Service |

Do not use the pre-beta.64 prefixes `server/core` and
`client/admin-console`. The worker listener serves health only; do not route
API traffic to it or use its sweep-health status for liveness.

## Unified configuration

The single schema is in `packages/server-config/src/`. Every service reads one
`authup.yml`; each role selects its relevant sections.

| Authup setting | Upstream source | Chart counterpart |
|---|---|---|
| config file `authup.yml` | `packages/server-config/src/read/fs.ts` | `/etc/authup/authup.yml`, key `authup.yml` |
| `PUBLIC_URL`, `INTERNAL_URL` | `sections/root/schema.ts`, `helpers/public-url.ts` | `_urls.tpl`, `_console-env.tpl` |
| `LOG_DIRECTORY_PATH` | `sections/core/schema.ts`, Dockerfile | `/var/log/authup` log emptyDir |
| `PROVISIONING_DIRECTORY_PATH` | `sections/core/schema.ts`, Dockerfile | `/etc/authup/provisioning` |
| `WORKER_ENABLED`, `MIGRATION_ENABLED` | `sections/core/schema.ts` | explicit role ownership in Deployments |
| `WORKER_PORT` | `sections/core/schema.ts` | worker health listener and readiness probe |
| `AUTH_CONSOLE_PORT`, `ADMIN_CONSOLE_PORT`, `ACCOUNT_CONSOLE_PORT` | console section schemas | `_console-env.tpl` |
| database, Redis, SMTP and strict feature flags | section schemas and `constants.ts` | `_server-env.tpl`, `_database.tpl`, Secrets |

Environment values win over file values. File-only database options still make
the config mount load-bearing for `migration run`.

## Role boundaries

- `start` combines core, enabled consoles and worker behavior in one process.
- `start core` serves the API with optional in-process sweeps. If a dedicated worker exists, the API must
  receive `WORKER_ENABLED=false`.
- `start worker` requires `WORKER_ENABLED=true` and database/cache config. It
  does not need SMTP or bootstrap identity secrets, and runs no migrations.
  Its health listener is used for readiness only.
- Split consoles use the deployment-wide `PUBLIC_URL`. Server-side console
  calls use `INTERNAL_URL`, which the chart points at the core Service.
- `ACCOUNT_CONSOLE_ENABLED` and `ADMIN_CONSOLE_ENABLED` describe whether those
  surfaces are available. The chart maps them from the top-level console
  `enabled` values in both combined and split modes.

## Migrations and provisioning

Core startup can initialize and migrate the database. The chart therefore lets
fresh installs boot normally after built-in backing services are created. The
optional migration Job is pre-upgrade only and sets `MIGRATION_ENABLED=false`
on upgrade server pods so ownership is not duplicated.

The migration command constructs configuration, logger and database modules.
It does not need provisioning, Redis, SMTP, HTTP, or bootstrap identity data.
It does need database credentials and `authup.yml`; the chart gives it a
hook-scoped config copy because pre-upgrade hooks run before regular release
resources.

Provisioning files are read from `PROVISIONING_DIRECTORY_PATH` at core startup.
The chart mounts them read-only at `/etc/authup/provisioning`. Reserved client
names `admin-console` and `account-console` remain application-owned system
clients and must not be declared as user provisioning entries.

## Security and availability facts

- The production image cannot use SQLite, so a real database is mandatory.
- `REDIS` is the connection variable; `REDIS_URL` is not part of the contract.
- More than one API replica needs shared Redis for authorization codes,
  revocations and MFA challenges.
- `SECRETS_ENCRYPTION_KEY` is a base64 32-byte write-once key. Loss or rotation
  makes wrapped MFA and signing material unreadable.
- `GET /` is the anonymous core health endpoint. `/metrics` is unauthenticated
  when enabled.
- Split console prefixes must be removed before requests reach their listeners.
  Admin/account login start and callback endpoints are core API routes, not
  console asset routes.
- Paths outside `/console` belong to the API set: the hosted page GETs
  (`/authorize`, `/register`, `/activate`, `/password-forgot`,
  `/password-reset`, `/logout`, `/device`), which answer with a redirect into
  the auth console, and the endpoints behind them (`/token`,
  `/device_authorization`). The chart's server catch-all carries them, so a new
  hosted page needs no chart change while that catch-all exists.
