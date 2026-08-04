# Breaking changes

This chart uses `0.major.minor` versioning while below 1.0.0: breaking changes
land on the middle digit. Every entry lists the value migrations required.

## 0.2.0 (unreleased)

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
