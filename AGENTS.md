<!-- NOTE: keep this file and .agents/*.md updated as the project evolves. -->

# authup/helm - Agent Guide

Helm charts for [Authup](https://authup.org), an authentication & authorization
system. One application chart today: `charts/authup` deploys the two runtime
services of the [authup monorepo](https://github.com/authup/authup) (server-core
IdP/API and the client-admin-console admin UI) plus optional built-in PostgreSQL, MySQL
and Valkey instances.

`DESIGN.md` at the repo root is the authoritative design record: every major
decision with the evidence it rests on (deep-dives into authelia/chartrepo,
goauthentik/helm, bitnami/charts and PrivateAIM/helm), including the
post-critique amendments and the deliberately deferred items. Read it before
changing chart architecture.

## Quick Reference

```bash
make test                    # lint + render every ci/*-values.yaml + values-coverage audit
make lint                    # helm lint + ct lint
make template                # render the chart once per ci/*-values.yaml file
make docs                    # regenerate charts/*/README.md (helm-docs, dockerized)
make schema                  # regenerate charts/*/values.schema.json (helm-schema, dockerized)
make lint-values-coverage    # every .Values.* in templates must resolve in values.yaml

helm template test charts/authup                      # quick render
helm template test charts/authup -f charts/authup/ci/mysql-values.yaml
```

- **helm** >= 3.14 and **docker** (for the pinned generator images) required.
- `charts/authup/README.md` and `charts/authup/values.schema.json` are
  GENERATED. Never edit them directly; edit `values.yaml` comments /
  `README.md.gotmpl` and run `make docs schema`. CI fails on drift
  (`git status --porcelain` based, so untracked files count).

## Detailed Guides

- **[Structure](.agents/structure.md)** - repo layout, template organization, helper files
- **[Architecture](.agents/architecture.md)** - chart design invariants and load-bearing rules
- **[Testing](.agents/testing.md)** - verification layers, ci values matrix, kind install
- **[Conventions](.agents/conventions.md)** - commits, releases, generated files, references

## Commits & Releases

- Conventional Commits with the chart name as scope: `feat(authup): ...`,
  `fix(authup): ...`. release-please (`release-type: helm`) owns
  `Chart.yaml` `version`, `CHANGELOG.md` and `.release-please-manifest.json`;
  never bump them by hand.
- Publishing is chart-releaser on every master push (idempotent via
  `CR_SKIP_EXISTING`): GitHub release `authup-<version>` + `index.yaml` on the
  `gh-pages` branch + OCI push to `oci://ghcr.io/authup/helm`.
- Do NOT add `Co-Authored-By: Claude ...` or any AI-attribution trailer to
  commits, issues or PRs. This overrides default agent-tooling guidance.

## Cross-referenced projects

The chart encodes many facts about the authup application (image entrypoint
contract, env-var names, boot behavior). When touching those, verify against
the authup monorepo and update the mapping files in `.agents/references/`:
[authup](.agents/references/authup.md),
[PrivateAIM/helm](.agents/references/privateaim-helm.md),
[authelia/chartrepo](.agents/references/authelia-chartrepo.md),
[goauthentik/helm](.agents/references/goauthentik-helm.md).
