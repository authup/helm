# Conventions

## Commits & versioning

- Conventional Commits with the chart name as scope: `feat(authup): ...`,
  `fix(authup): ...`, `chore(authup): ...`. Repo-level changes (CI, docs,
  Makefile) use no scope or `ci:` / `docs:`.
- release-please (`release-type: helm`, config at `release-please-config.json`)
  owns `Chart.yaml` `version`, `CHANGELOG.md` and
  `.release-please-manifest.json`. Never hand-edit them. `feat` bumps minor
  (pre-major: patch via `bump-patch-for-minor-pre-major`), `fix` bumps patch,
  `feat!`/`fix!` bumps the middle digit (0.x breaking convention).
- Do NOT add `Co-Authored-By: Claude ...` or any AI-attribution trailer to
  commits, issue or PR text. This overrides default agent-tooling guidance.
- Update the `artifacthub.io/changes` annotation in `Chart.yaml` for
  user-visible chart changes (`ah lint` validates the format in CI).

## Releases & publishing

- chart-releaser runs on every master push and publishes when `Chart.yaml`'s
  version has no release yet: GitHub release `authup-<version>`, `index.yaml`
  on `gh-pages`, then an OCI push to `oci://ghcr.io/authup/helm`.
- The publish job is deliberately UNGATED on release-please outputs: the chart
  package uses `skip-github-release`, so `releases_created` never fires for it
  (gating on it would make publishing unreachable). chart-releaser is
  idempotent via `CR_SKIP_EXISTING`.
- chart-releaser detects "changed charts" by diffing against the latest
  `authup-*` tag (falling back to the root commit), so a release only triggers
  when a commit touches `charts/`.
- Migration to hevi (tada5hi's own releaser) is planned and tracked by
  tada5hi/hevi#52, a chart-releaser parity checklist. Do not switch the
  publish tooling before that issue is closed; when working on it, keep the
  `authup-<version>` tag format stable (release-please's baseline).
- Breaking value changes: document the migration in `charts/authup/BREAKING.md`
  AND add a fail-loud tripwire for the old key in `templates/validations.yaml`.

## Generated files

- `charts/authup/README.md` (helm-docs) and `charts/authup/values.schema.json`
  (dadav/helm-schema) are compiler output. Edit `values.yaml` comments /
  `README.md.gotmpl`, run `make docs schema`, commit the regeneration. CI
  drift gates use `git status --porcelain` so untracked output counts too.
- Comment layout per value: optional `# @schema ... # @schema` block first,
  then the `# --` helm-docs line, directly above the key.

## Writing style

- Avoid the em dash in docs, comments and commit text; use a colon, a
  hyphen, parentheses or two sentences.
- Keep values doc comments short and declarative: what the field does and
  what an empty value means.

## References

External project mappings live in `.agents/references/`, one file per
project. When consulting a referenced project's source, record the mapping
(their file/function, this repo's counterpart, behavioral differences) so the
next task does not re-search:

- [authup.md](references/authup.md) - the authup monorepo (the application this chart deploys)
- [privateaim-helm.md](references/privateaim-helm.md) - PrivateAIM/helm (predecessor chart + umbrella consumer)
- [authelia-chartrepo.md](references/authelia-chartrepo.md) - Authelia chart repo (repo-infra template)
- [goauthentik-helm.md](references/goauthentik-helm.md) - authentik chart (architecture cohort)
