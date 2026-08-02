# goauthentik/helm

Repo: https://github.com/goauthentik/helm (chart `charts/authentik`).
Analyzed at chart 2026.5.6 (2026-08-02) including full git history. The
closest architectural cohort (multi-role deployment of one env-configured
auth server).

## Adopted from here

| Their piece | This repo |
|---|---|
| Per-role template directories, duplication accepted (they built and REVERTED the DRY role-loop in #163: "takes DRY maybe a bit too far") | `templates/server/` + `templates/ui/` |
| Self-contained chart, no library dependency (their k8s-at-home common era died upstream) | zero `dependencies:` in Chart.yaml |
| ct lint + kind `ct install` gated by `ct list-changed`, `ci/*-values.yaml` scenario matrix, `ci/manifests/` fixtures | `.github/workflows/lint-test.yaml` |
| helm-docs drift gate (`git diff` fail step) | hardened variant in CI |
| chart-releaser + OCI push loop over `.cr-release-packages/` | `.github/workflows/release.yaml` |
| `deprectations.yaml` fail-loud tripwires for moved values | the tripwire section of `templates/validations.yaml` |
| `additionalObjects` templated escape hatch | `extraDeploy` + `extra-list.yaml` |
| Blueprint-mount shape (list of ConfigMap/Secret names mounted under one discovery dir) | `server.provisioning.*` |

## Deliberately NOT adopted

- Their recursive config->env serializer (`authentik.env` over the whole
  `authentik:` values subtree). Elegant zero-maintenance surface, but chart
  control keys leak into env (`AUTHENTIK_ENABLED` renders into their Secret)
  and everything (including plain config) lands in one Secret. This chart
  uses explicit first-class values + `server.config` for the long tail.
- Chart version == appVersion (CalVer): strands chart-only fixes unreleased
  until the next app bump (observed live on their main). This chart versions
  independently via release-please.
- Their pre-install migration Job era: reverted in #163 because hook Jobs run
  before the DB subchart exists. This chart's migration Job is pre-upgrade
  only.
- Vendored full copies of bitnami postgresql/redis (their 2023 era, abandoned
  within a year). This chart vendors ~150-line minimal StatefulSets it fully
  owns instead.
- Their post-Broadcom bitnami-postgresql arrangement (subchart kept, image
  overridden to `docker.io/library/postgres` + `global.security.allowInsecureImages: true`):
  evidence for why no bitnami dependency exists here at all.
