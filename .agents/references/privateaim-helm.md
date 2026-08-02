# PrivateAIM/helm

Repo: https://github.com/PrivateAIM/helm. Two prior authup deployments live
there; this chart supersedes the standalone one. Analyzed 2026-08-02 (branch
`hub-013`, which was ahead of master).

## charts/third-party/authup (the predecessor standalone chart)

Deploys server-core ONLY (no admin UI), hardcoded
`{{ .Release.Name }}-authup-server-core` names with dead default helpers,
`authup/authup:latest` + `pullPolicy: Always`, `start123` defaults, busybox
`nc` wait initContainers, no escape hatches. Treated as the negative print in
`DESIGN.md`; the pieces worth keeping were kept:

| Their piece | This chart |
|---|---|
| `provisioning.{enabled,mountPath,existingConfigMap,files}` ConfigMap mount | `server.provisioning.*` (+ checksum annotation they lacked, + `existingSecret` variant) |
| tpl-rendered wiring values + `required` fail-louds | universal `authup.tplvalues.render` |
| `trustedOrigins` list-or-string normalization | `authup.server.trustedOrigins` |
| Startup probe sized for boot migration (60 x 5s) | `server.startupProbe` defaults |
| Proxy-buffer ingress annotations for token-heavy responses (16k-256k) | documented in `server.ingress.annotations` comment / README |
| Secret keys `authup-admin-password`, `authup-client-secret` | renamed (`admin-password`, `system-client-secret`); migrating consumers map via `auth.existingSecret` + `auth.secretKeys` |

Their `ROBOT_ADMIN_ENABLED=true` env is dead (robots removed from authup in
PR #3275); never copy it.

## charts/flame-hub (umbrella consumer patterns)

- Lookup-reuse-generate shared Secret with `helm.sh/resource-policy: keep` and
  pre-built `*-connection-string` keys: upstream of this chart's
  `authup.secret.rawValue` + valkey single-secret composition.
- Cross-chart config under `global.*` + helpers that evaluate in subchart
  context; the "existingSecret cannot be templated, unfortunately" comment is
  why every name-ish value here is tpl-rendered.
- Consumer contract for apps embedding authup: in-cluster URL
  `http://<release>-authup-server-core:3000/`, `CLIENT_ID=system` +
  `CLIENT_SYSTEM_SECRET` from the shared secret, `REALM=master`. This chart's
  equivalents: the server Service name, `auth.systemClientEnabled` +
  `auth.secretKeys.systemClientSecretKey`, NOTES retrieval one-liner.
- Their develop-branch PR #161 (merged 2026-07-29) replaced bitnami postgresql
  with a vendored ~150-line StatefulSet on `postgres:17` - the same model as
  this chart's `templates/postgresql/`.

## Repo automation

`release-please-config.json` with `release-type: helm` + `linked-versions` +
the `extra-files` yaml jsonpath trick (bumping a dependency pin inside a
consumer's Chart.yaml in the same release PR) - reusable here if this repo
ever grows a chart that depends on another.
