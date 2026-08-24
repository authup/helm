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
| ct install (CI) | kind cluster, per `ci/*-values.yaml`: install, plus two upgrades | real boot: DB provisioning, probes, migrations, and pre-upgrade hooks |

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
helm template t charts/authup --set server.config.WRITABLE_DIRECTORY_PATH=/x  # ditto; the chart pins this one to the path it mounts
helm template t charts/authup --set 'server.route.enabled=yes'               # flag that is neither true nor false
helm template t charts/authup --set adminConsole.enabled=false --set adminConsole.route.enabled=yes  # ditto: validated even with the component off
helm template t charts/authup --set 'server.configuration=logger: true' --set server.existingConfigmap=cm  # both config carriers
helm template t charts/authup --set server.theme.enabled=true               # theme with no carrier
helm template t charts/authup --set server.theme.enabled=true --set server.theme.title=X --set server.theme.existingConfigMap=cm  # manifest + existing CM
helm template t charts/authup --set server.theme.enabled=true --set server.theme.logo=logo.svg          # asset outside assets/
helm template t charts/authup --set server.theme.enabled=true --set server.theme.logo=assets/logo.svg   # asset missing from files
helm template t charts/authup --set server.theme.enabled=true --set 'server.theme.tokens.--authup-bg=url(x)'  # token value authup rejects
helm template t charts/authup --set 'server.trustedOrigins[0]=https://**.x'  # globstar host
helm template t charts/authup --set server.route.enabled=true --set server.publicUrl=https://h.x/auth   # sub-path route without matches
helm template t charts/authup --set server.route.enabled=true --set server.ingress.enabled=true \
  --set server.ingress.hostname=h.x --set server.ingress.path=/auth                                     # same, via the derived URL
```

The route guard reads the public URL AFTER derivation, so the ingress-derived
case needs its own line: only the origin reaches the HTTPRoute hostname, and the
dropped path is exactly what turns the rule into a catch-all. Adding
`--set 'server.route.matches[0].path.value=/auth'` must make both RENDER.

`server.route.enabled` / `adminConsole.route.enabled` accept a tpl-rendered
string, so an umbrella can drive them from one of its own switches. `--set-string`
cannot carry `{{ }}` (helm fails parsing on the closing brace), so both directions
go through a values file, and BOTH are needed: a rendered `"false"` is a non-empty
string, which a Go template `if` reads as true.

```bash
printf 'global:\n  gw:\n    enabled: false\nserver:\n  route:\n    enabled: "{{ .Values.global.gw.enabled }}"\n' \
  | helm template t charts/authup -f - | grep -c 'kind: HTTPRoute'   # must be 0
printf 'global:\n  gw:\n    enabled: true\nserver:\n  publicUrl: https://auth.example.com\n  route:\n    enabled: "{{ .Values.global.gw.enabled }}"\n    parentRefs:\n    - name: gw\n' \
  | helm template t charts/authup -f - | grep -c 'kind: HTTPRoute'   # must be 1
```

The sub-path catch-all guard and the NOTES path-prefix warning read the same
flag, so all six read sites convert together: leave one raw and an umbrella-driven
route renders unguarded. `ci/default-values.yaml` carries the false direction as
the in-repo regression guard.

The pre-upgrade migration Job must stay narrower than the Deployment. Helm
applies a hook before the release manifest, so anything the Job references has
to exist from the previous release:

```bash
helm template t charts/authup --set server.migration.enabled=true \
  --set valkey.enabled=true --set smtp.connectionString=smtp://u:p@mail:25 \
  --set auth.systemClientEnabled=true \
  --set server.provisioning.enabled=true --set 'server.provisioning.files.realms\.json=[]' \
  --set 'server.configuration=db: {ssl: true}' \
  -s templates/server/migration-job.yaml
```

The Job's only secret-backed env must be `DB_PASSWORD` (plus
`SECRETS_ENCRYPTION_KEY` when the KEK is set): no `REDIS`, no `SMTP`, no
`USER_ADMIN_PASSWORD`, no `CLIENT_SYSTEM_SECRET`. Volumes `writable` / `tmp` /
`configuration` but NO `provisioning`; and the configuration volume must name
`<fullname>-server-migration-configuration`
(the hook-scoped copy at weight -5), never `<fullname>-server-configuration`. The
server Deployment in the same render must still carry all of them. Dropping the
config file from the Job is NOT a valid simplification: `migration run` reads it
and its file-only db keys (`ssl`, `socketPath`, `extensions`) govern the
connection, so a missing mount migrates over a plaintext connection instead of
failing.

Names have two ceilings, not one (rule 9). 63 applies to a Service (DNS-1035
label) and to a Job (its name becomes a `job-name` label value); 253 applies to
ConfigMaps and Secrets. Audit every rendered name at the longest release name
helm accepts:

```bash
helm template $(python3 -c "print('n'*53)") charts/authup \
  --set valkey.enabled=true --set server.migration.enabled=true | python3 -c "
import sys, yaml
for d in yaml.safe_load_all(sys.stdin):
    if d and d['kind'] in ('Service','Job') and len(d['metadata']['name']) > 63:
        print('OVER 63:', d['kind'], d['metadata']['name'])
"
```

Must print nothing. The stronger property, and the one to assert whenever the
budget in `authup.component.fullname` changes, is that **no name changes for a
release that could already install**: render every release-name length 3..53 on
both `origin/master` and the branch, and check that the two name sets differ only
at lengths where master already emitted an over-63 Service or Job. Widening the
budget silently renames resources, and a renamed `resource-policy: keep` Secret
regenerates the admin password.

`useHelmHooks=false` must print the Flux/plain-helm warning in NOTES.txt, and
must not print it with hooks on. NOTES is not reachable through `helm template`,
and `.Files.Get "templates/NOTES.txt"` does NOT work either (helm excludes
`templates/` from `.Files`, so the wrapper renders empty and BOTH directions
"pass"). Inline the raw template text into a generated template instead:

```bash
cp -r charts/authup /tmp/nc
{ printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: notes\ndata:\n  notes: |\n'; \
  sed 's/^/    /' /tmp/nc/templates/NOTES.txt; } > /tmp/nc/templates/zz-notes.yaml
helm template t /tmp/nc --set server.migration.enabled=true --set useHelmHooks=false \
  -s templates/zz-notes.yaml | grep -c 'useHelmHooks=false'   # must be >0
helm template t /tmp/nc --set server.migration.enabled=true \
  -s templates/zz-notes.yaml | grep -c 'useHelmHooks=false'   # must be 0
```

Umbrella use is part of the contract: `global` must stay open. Render a throwaway
parent chart with authup in `charts/` and an unrelated global (`global.myOrgKey`)
whenever the schema generation changes; `ci/default-values.yaml` carries a stray
global key as the cheap in-repo version of that check.

A single `*` host wildcard (`https://*.example.com`) must still RENDER: authup
supports it, only `**` is the allow-any-origin trap.

The `server.theme` manifest guards assert the value AFTER `tpl` rendering, so
both directions need a case: a templated token or asset path must RENDER, and
one whose rendered result is illegal must FAIL. Validating the raw value gets
this backwards in a way that looks correct (every `{{ ... }}` contains `}`, so
the forbidden-character check rejects it for the wrong reason).

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
- `upgrade: true` (in `.github/configs/ct.yaml`) is what puts the pre-upgrade
  migration Job on a real cluster at all: a plain `helm install` skips
  `pre-upgrade` hooks entirely, so without it the Job and its hook-scoped
  ConfigMap are render-tested only. Per values file ct then runs the chart on
  `master` and upgrades to this revision, then installs this revision and
  upgrades it to itself. The first leg is skipped once a release bumps the
  middle digit, because ct reads that as a breaking change for a 0.x chart
  (`~0.x.y` constraint); the self-upgrade leg always runs. Budget roughly 3x
  the install-only runtime.
- `--timeout 600s` is passed to install AND upgrade (ct hands `helm-extra-args`
  to both), so it also has to cover hook execution. It accounts for first-pull
  of the authup image plus boot-time migrations; server-core's startupProbe budget (60 x 5s) covers create-db +
  migrate + provision on first boot.
