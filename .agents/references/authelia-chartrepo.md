# authelia/chartrepo

Repo: https://github.com/authelia/chartrepo (chart `charts/authelia`).
Analyzed at chart 0.11.6 / appVersion 4.39.20 (2026-08-02). The repo-infra
template for this repository; also the source of several documented traps.

## Adopted from here

| Their piece | This repo |
|---|---|
| `charts/<name>/` + `ci/` values + Makefile targets identical locally and in CI | repo layout + `Makefile` |
| helm-docs (`# --` + `README.md.gotmpl`) and dadav/helm-schema (`# @schema`) with git-diff drift gates | `make docs` / `make schema` + CI gates (hardened to `git status --porcelain`) |
| `# yaml-language-server: $schema=values.schema.json` header | `values.yaml` line 1 |
| Render-nothing `validations.*.check.yaml` fail-fast guards | `templates/validations.yaml` |
| Lookup-based generate-if-absent secrets with the GitOps caveat | `authup.secret.rawValue` (env secretKeyRef delivery instead of their file mounts) |
| `enabled.X` vs `generate.X` helper split backing every existingX value | `authup.auth.createSecret` etc. |
| Checksum-restart annotations with an opt-out flag | `disableRestartOnChanges` |
| 0.major.minor pre-1.0 versioning + BREAKING.md ledger | `charts/authup/BREAKING.md` |
| Dual publish: gh-pages index + OCI ghcr | `.github/workflows/release.yaml` |

## Documented traps observed there (do not reintroduce)

- Strict generated schema + values/template drift makes features silently
  unusable (their HPA metrics, `service.externalIPs`, ... are dead code). This
  repo's countermeasure: `scripts/check-values-coverage.py` in CI.
- 714-line hand-templated config file with ~30 `semverCompare` version gates:
  a chart PR per app release. authup is env-configured; never mirror its
  config schema.
- Lint-only CI (no install test) is why their containerPort drift and HPA/PDB
  copy-paste bugs shipped. This repo runs a kind install matrix.
- DB/redis subcharts were added and then removed in 0.11.0 in favor of
  operators/external services.
- `nameOverride` behaving like `fullnameOverride` confuses bitnami-trained
  users; this repo uses the bitnami key names.
