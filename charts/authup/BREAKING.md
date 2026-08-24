# Breaking changes

This chart uses `0.major.minor` versioning while below 1.0.0: breaking changes
land on the middle digit. Every entry lists the value migrations required.

## Next release (unreleased)

- Setting BOTH `server.configuration` and `server.existingConfigmap` now fails
  the render. It never worked: the existing ConfigMap is the one that gets
  mounted, so the inline content was silently dropped, and that content is
  typically where `db.ssl` / `socketPath` / `replication` live, i.e. how the
  server pods and the pre-upgrade migration hook connect to the database. Move
  the inline content into the referenced ConfigMap, or drop
  `server.existingConfigmap`.
- The writable directory moves from `/usr/src/app/writable` to `/var/lib/authup`,
  following the image (authup/authup#3474, shipped in v1.0.0-beta.63). The chart
  mounts an emptyDir there, so nothing persists across the change; only a
  `server.extraVolumeMounts` / `server.extraVolumes` entry aimed at the old path
  needs updating, along with anything reading the container's log files by path.
- The chart now SETS `WRITABLE_DIRECTORY_PATH` to the path it mounts instead of
  inheriting the image default, so it works with a pinned older `image.tag` too.
  As a consequence `server.config.WRITABLE_DIRECTORY_PATH` now fails the render:
  it would have emitted a duplicate ConfigMap key and pointed the server at a
  path the chart mounts nothing at, which fails silently (production logs on the
  container layer, file provisioning scanning a directory that does not exist).
  To move the directory anyway, set it through `server.extraEnvVars` and mount
  the same path with `server.extraVolumeMounts`; `server.provisioning` then needs
  its source (ConfigMap or Secret) re-mounted at `<new path>/provisioning` by
  hand, because the chart's own provisioning mount stays where the chart puts it.

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
