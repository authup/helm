# Testing

No unit-test framework (cohort norm: neither authelia nor authentik ship
helm-unittest). The safety net is layered rendering plus a kind install
matrix.

## Layers

| Layer | Command | What it catches |
|---|---|---|
| helm lint + ct lint | `make lint` | schema violations, yamllint, Chart.yaml shape |
| Render matrix | `make template` | template errors across every `ci/*-values.yaml` |
| Values coverage | `make lint-values-coverage` | `.Values.*` paths missing from values.yaml (strict-schema dead features) |
| Drift gates (CI) | `make docs` / `make schema` + `git status --porcelain` | uncommitted regenerations of README.md / values.schema.json |
| ct install (CI) | kind cluster, one install per `ci/*-values.yaml` | real boot: DB provisioning, probes, migrations |

`make test` runs lint + template + coverage locally.

## Rendering permutations by hand

```bash
helm template test charts/authup                                   # defaults (built-in postgres)
helm template test charts/authup -f charts/authup/ci/valkey-values.yaml
helm template test charts/authup --set server.ingress.enabled=true \
  --set server.ingress.hostname=auth.example.com --set server.ingress.tls=true \
  --set adminConsole.ingress.enabled=true --set adminConsole.ingress.hostname=app.example.com --set adminConsole.ingress.tls=true
```

When verifying env wiring, grep the rendered ConfigMaps/Deployments for
`PUBLIC_URL`, `TRUSTED_ORIGINS`, `NUXT_PUBLIC_API_URL`, `DB_*`, `REDIS`,
`SMTP`, and check every `secretKeyRef` points at a Secret the same render
actually creates.

## Negative tests are part of the contract

`templates/validations.yaml` guards must FAIL these renders; when touching
validations or the values they read, re-run the battery:

```bash
helm template t charts/authup --set postgresql.enabled=false                 # no db
helm template t charts/authup --set mysql.enabled=true                       # both dbs
helm template t charts/authup --set server.replicaCount=2                    # replicas w/o cache
helm template t charts/authup --set server.mfa.required=true                 # mfa.required w/o enabled
helm template t charts/authup --set auth.existingSecret=x --set auth.adminPassword=y
helm template t charts/authup --set server.publicUrl=auth.example.com        # scheme-less URL
helm template t charts/authup --set postgresql.enabled=false --set externalDatabase.host=db  # extdb w/o password
helm template t charts/authup --set server.ingress.enabled=true              # ingress w/o hostname
helm template t charts/authup --set server.config.PUBLIC_URL=http://x        # first-class collision
```

The generated `values.schema.json` must keep catching typos
(`--set server.replicaCountt=3` fails) while free-form maps stay open
(`--set server.config.X=y`, `--set server.resources.limits.cpu=1` succeed).

## ct install specifics

- Scenario matrix = `charts/authup/ci/*-values.yaml`; each file must make the
  chart actually installable on kind (persistence off, small resources,
  explicit fixtures).
- `ci/manifests/` is pre-applied into the test namespace before `ct install`
  (the external-db scenario's throwaway postgres + secrets live there).
- The kind job only runs when `ct list-changed` reports chart changes, so
  docs-only PRs stay fast.
- `--timeout 600s` accounts for first-pull of the authup image plus boot-time
  migrations; server-core's startupProbe budget (60 x 5s) covers create-db +
  migrate + provision on first boot.
