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
- The publish job is deliberately UNGATED on release-please outputs: the chart
  package uses `skip-github-release`, so `releases_created` never fires for it
  (gating on it would make publishing unreachable). Re-runs are safe because
  hevi skips existing releases (`cr --skip-existing`) and existing OCI tags
  (`push-skip-existing`). Every run packages every chart under `charts/`, so
  "did this commit touch the chart" is not a precondition.
- The workflow also accepts a `workflow_dispatch`, which skips release-please
  and publishes whatever `Chart.yaml` holds at the dispatched ref. This is the
  recovery path when a publish fails on its own after the version bump has
  already merged, since publishing is otherwise reachable only from a push.
- `skip-github-release` costs release-please its own PR bookkeeping, so the
  publish job closes that loop by hand. release-please labels a release PR
  `autorelease: pending` when it opens it and only clears the label in the
  release step, which is exactly the step being skipped. A merged release PR
  therefore keeps the label forever, and from then on every run aborts PR
  creation with `There are untagged, merged release PRs outstanding` while
  exiting 0, so the workflow stays green while no release PR is ever opened
  again. The `Clear the release-please pending label` step is the fix; a single
  merged PR still carrying the label deadlocks every future release PR.
  The step exists only because chart-releaser owns releases: `cr upload
  --skip-existing` skips an existing release wholesale (no asset upload), so a
  release-please-created release would leave the chart `.tgz` unattached and
  the `index.yaml` download URL dangling. If hevi ever learns to attach assets
  to an existing release, drop `skip-github-release` and delete the step:
  release-please then handles the whole cycle on its own.
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
