# Testing

The safety net is layered rendering plus chart-testing installs on kind.

## Local layers

| Layer | Command | Coverage |
|---|---|---|
| Helm and ct lint | `make lint` | schema, YAML and chart metadata |
| CI render matrix | `make template` | every `ci/*-values.yaml` permutation |
| Values coverage | `make lint-values-coverage` | template paths missing from values.yaml |
| beta.64 contract | `make lint-beta64-contract` | roles, env, mounts, routing, policies and guards |
| Full local suite | `make test` | all four layers above |
| Generated drift | `make docs schema` | README.md and values.schema.json |

The contract script uses real `helm template` output and PyYAML. Prefer adding
a focused assertion there over brittle text grep when changing the application
boundary.

## Useful renders

```bash
helm template test charts/authup
helm template test charts/authup -f charts/authup/ci/split-values.yaml
helm template test charts/authup -f charts/authup/ci/valkey-values.yaml --is-upgrade
python3 scripts/check-beta64-contract.py charts/authup all
```

The split fixture is the high-value beta.64 scenario: separate core/auth/admin/
account roles, a worker, migration hooks, one-origin routing, built-in database
and cache, plus restrictive NetworkPolicies.

## Negative contracts

`templates/validations.yaml` must fail these classes of input:

- no database, both built-in databases, or an unknown external database type
- API replicas/HPA without Redis
- MFA required while MFA is disabled
- inline and existing-secret auth carriers set together
- scheme-less public URLs or an Ingress without a hostname
- a `server.config` key owned by a first-class value
- both inline and existing configuration ConfigMaps
- invalid route flags, including flags on disabled roles
- an HTTPRoute catch-all created accidentally from a sub-path public URL
- `server.splitConsoles=true` without the server or auth console, and a worker
  enabled without its shared server configuration
- non-empty `server.features.accountConsole`, which moved to
  `accountConsole.enabled`
- invalid theme manifests or dangerous trusted-origin globstars

The beta.64 contract script exercises the moved value, split dependencies,
route flags and reserved role env variables directly.

## Hook checks

The pre-upgrade migration Job must stay narrower than the server Deployment:

- args are exactly `migration run`
- only database password and an optional encryption key are secret-backed
- no Redis, SMTP, bootstrap identity secret, or provisioning mount
- `authup.yml` comes from the hook-scoped configuration ConfigMap
- logs mount at `/var/log/authup`
- the migration NetworkPolicy selects component `migration`, uses the same hook
  family, and runs at weight or wave -5 before the Job at 0
- fresh-install server env has no `MIGRATION_ENABLED`; upgrade server env has
  `MIGRATION_ENABLED=false` when the Job is enabled and the database persists,
  but leaves startup migration enabled for non-persistent built-in databases;
  with `useHelmHooks=false` every render counts as an upgrade because PreSync
  precedes each sync

Run both Helm and ArgoCD annotation paths:

```bash
helm template t charts/authup -f charts/authup/ci/split-values.yaml --is-upgrade
helm template t charts/authup -f charts/authup/ci/split-values.yaml \
  --set useHelmHooks=false --is-upgrade
```

## Name safety

Service names and label values stop at 63 characters. Whenever the component
fullname budget changes, render release-name lengths 3 through 53 on both
`origin/master` and the branch. No name may change for a release that previously
produced valid resources. This is stricter than checking only maximum length:
renaming a kept Secret can rotate credentials.

## Generated-schema checks

After values changes, run `make docs schema`. The schema must reject typos such
as `server.replicaCountt` while allowing annotated free-form maps such as
`server.config` and resource limits. Keep the stray global key in the default CI
fixture because it covers umbrella-chart schema behavior.

## ct install specifics

- Every `charts/authup/ci/*-values.yaml` file must be installable on kind with
  small resources and persistence disabled.
- `ci/manifests/` is pre-applied for the external-database fixture.
- `upgrade: true` runs native pre-upgrade hooks. A plain install never runs them.
- The first master-to-branch upgrade may be skipped for a breaking 0.x release;
  the self-upgrade still runs.
- The 600-second timeout includes image pulls, database startup, migrations and
  the server startup-probe budget.
