# authup application mapping

Repository: https://github.com/authup/authup. A local checkout commonly exists
at `/opt/projects/authup/authup`. This mapping is pinned to v1.0.0-beta.64, the
chart `appVersion`.

## Image and CLI

| Authup contract | Upstream source | Chart counterpart |
|---|---|---|
| One `authup/authup` image with direct CLI args | `Dockerfile`, `entrypoint.sh` | `authup.appImage`; every application Deployment |
| Combined service: `start` | `apps/authup/src/commands/start.ts` | `server/deployment.yaml` default |
| API only: `start core` | `apps/authup/src/module.ts`, command tests | server when `server.splitConsoles=true` |
| Split consoles: `start console auth|admin|account` | `apps/authup/src/console/`, `apps/server-*-console/` | the three console directories |
| Background worker: `start worker` | `apps/authup/src/module.ts`, `apps/server-core/src/app/modules/components/module.ts` | `worker/deployment.yaml` |
| Migration: `migration run` | `apps/server-core/src/cli/commands/migration.ts` | `server/migration-job.yaml` |
| Core port 3000; console ports 3020/3021/3022 | `packages/server-config/src/sections/*/schema.ts`, `Dockerfile` | role `containerPorts` and Services |

Do not use the pre-beta.64 prefixes `server/core` and
`client/admin-console`. A worker has no HTTP listener; it must not gain a
Service or HTTP probes.

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
| `AUTH_CONSOLE_PORT`, `ADMIN_CONSOLE_PORT`, `ACCOUNT_CONSOLE_PORT` | console section schemas | `_console-env.tpl` |
| database, Redis, SMTP and strict feature flags | section schemas and `constants.ts` | `_server-env.tpl`, `_database.tpl`, Secrets |

Environment values win over file values. File-only database options still make
the config mount load-bearing for `migration run`.

## Role boundaries

- `start` combines core, enabled consoles and worker behavior in one process.
- `start core` serves the API only. If a dedicated worker exists, the API must
  receive `WORKER_ENABLED=false`.
- `start worker` requires `WORKER_ENABLED=true` and database/cache config. It
  does not need SMTP, bootstrap identity secrets, HTTP probes, or migrations.
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
