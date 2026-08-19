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

- `tada5hi/hevi@v2` runs on every master push and publishes when `Chart.yaml`'s
  version has no release yet: GitHub release `authup-<version>`, `index.yaml`
  on `gh-pages`, then an OCI push to `oci://ghcr.io/authup/helm`. hevi drives
  `cr` under the hood, so the `authup-<version>` release-name template
  (release-please's baseline) stays stable.
- The publish job is deliberately UNGATED on release-please outputs. Gating
  would cost the `workflow_dispatch` recovery path below, which runs without
  release-please and would therefore see empty outputs. Re-runs are safe
  because hevi skips existing releases (`cr --skip-existing`) and existing OCI
  tags (`push-skip-existing`). Every run packages every chart under `charts/`,
  so "did this commit touch the chart" is not a precondition. Note the
  `releases_created` output reports the ROOT release, never the chart, which
  sets `skip-github-release`.
- The workflow also accepts a `workflow_dispatch`, which skips release-please
  and publishes whatever `Chart.yaml` holds at the dispatched ref. This is the
  recovery path when a publish fails on its own after the version bump has
  already merged, since publishing is otherwise reachable only from a push.
- **The `root` package is load-bearing, not decoration.** `charts/authup` sets
  `skip-github-release` (chart-releaser owns `authup-<version>`, because
  `cr upload --skip-existing` skips an existing release wholesale and would
  leave the `.tgz` unattached and the `index.yaml` URL dangling). release-please
  only clears a merged release PR's `autorelease: pending` label inside the
  release step, so with every package skipped it created zero releases, never
  cleared the label, and from then on aborted PR creation with `There are
  untagged, merged release PRs outstanding` while exiting 0: green workflow,
  no release PR ever again. The `.` package (`release-type: simple`, component
  `root`) creates one real release per cycle, which restores the label swap and
  makes `releases_created` meaningful. Never give it `skip-github-release`, and
  never make it the only package either. Same shape as PrivateAIM/helm.
- `linked-versions` keeps `root` and `authup` on one version and merges them
  into a single `chore: release master` PR. A package with no commits of its
  own still gets bumped: the plugin injects a synthetic
  `chore(<component>): Synchronize global versions` commit carrying
  `Release-As`, so a repo-level `fix:` still moves `Chart.yaml`.
- `bootstrap-sha` bounds history for packages with NO release yet, which is
  what `root` was on adoption. It is pinned at the `authup-0.2.0` commit so
  root did not inherit the earlier `refactor(authup)!:`, which would have made
  root 0.3.0 and dragged the chart along through `linked-versions`. It goes
  inert once a `root-<version>` release exists.
- Requires hevi >= v2.0.2. Earlier versions called `cr upload` without
  `--commit`, so GitHub rejected every newly created release with
  `422 Invalid target_commitish parameter` (tada5hi/hevi#60).
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
