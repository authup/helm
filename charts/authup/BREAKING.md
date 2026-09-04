# Breaking changes

This chart uses `0.major.minor` versioning while below 1.0.0: breaking changes
land on the middle digit. Every entry lists the value migrations required.

## Next release (unreleased)

- The chart now requires the Authup v1.0.0-beta.64 CLI. Default server args are
  `start`; split API args are `start core`; console args are
  `start console auth|admin|account`; migration args are `migration run`.
  Overrides containing `server/core` or `client/admin-console` must be removed.
- The default topology is one combined server. The old standalone admin
  workload is no longer created merely by `adminConsole.enabled=true`. Set
  `server.splitConsoles=true` to deploy separate API and console workloads.
  Split mode requires `authConsole.enabled=true`; the admin and account consoles
  remain independently optional.
- `server.features.accountConsole` moves to `accountConsole.enabled`. Any
  non-empty old value now fails the render with the replacement key.
- `adminConsole.publicUrl`, `adminConsole.apiUrl` and
  `server.trustedOriginsAppendAdminConsole` are removed. All roles share
  `server.publicUrl`; split console server-side requests use the generated
  in-cluster `INTERNAL_URL`.
- The configuration file is now `authup.yml`, mounted at
  `/etc/authup/authup.yml`. Provisioning moves to `/etc/authup/provisioning` and
  logs to `/var/log/authup`. Remove overrides for `WRITABLE_DIRECTORY_PATH`,
  `/var/lib/authup`, or `authup.server.core.conf`.
- Split consoles share the Authup origin under `/console/auth`,
  `/console/admin` and `/console/account`. The generated Ingress rules require
  ingress-nginx because they use regex prefix stripping. Gateway API users get
  portable `URLRewrite` filters. Exact admin/account login and callback paths
  continue to route to the API.
- `worker.enabled=true` creates the beta.64 background worker and sets
  `WORKER_ENABLED=false` on the API. The worker has no Service or HTTP probes.
- When `server.networkPolicy.enabled=true`, the chart also creates hook-scoped
  migration egress policy. Restrictive split deployments get role-specific
  console and worker policies; use `extraEgress` for external databases or
  caches.

## 0.2.0

Follows the upstream rename of the admin UI app (authup/authup#3370) and its
dedicated OAuth2 client (authup/authup#3371).

- Values section `ui.*` -> `adminConsole.*`. Every key moves unchanged, e.g.
  `ui.enabled` -> `adminConsole.enabled`, `ui.ingress.hostname` ->
  `adminConsole.ingress.hostname`.
- `server.trustedOriginsAppendUI` -> `server.trustedOriginsAppendAdminConsole`.
- Rendered resource names change suffix `-ui` -> `-admin-console`
  (Deployment, Service, Ingress, ...). Helm re-creates them on upgrade;
  expect a brief admin-UI rollout and update anything referencing the old
  Service name directly.
- The pod container is renamed `ui` -> `admin-console`, matching the `server`
  and `migration` containers. Update any `kubectl logs -c ui` / `exec -c ui`
  invocation and any log pipeline selecting on the container name.
- The admin UI container now starts with `client/admin-console start` and
  logs in against the per-realm `admin-console` OAuth2 client. Requires an
  authup image containing authup/authup#3370 + #3371; older images only know
  `client/web` and would crash-loop. Ship this chart version together with
  the `appVersion` bump to that release.
