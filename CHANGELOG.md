# Changelog

## [0.4.1](https://github.com/authup/helm/compare/root-0.4.0...root-0.4.1) (2026-09-08)


### Features

* **authup:** track authup 1.0.0-beta.65 ([95852c0](https://github.com/authup/helm/commit/95852c0c4a79a62803f6c17bf996e6376115d0fb))


### Bug Fixes

* **authup:** order the migration Job after its own inputs under ArgoCD ([#34](https://github.com/authup/helm/issues/34)) ([c29945d](https://github.com/authup/helm/commit/c29945d9252374ad57043c18418c4b9139a26a6a))

## [0.4.0](https://github.com/authup/helm/compare/root-0.3.0...root-0.4.0) (2026-09-05)


### ⚠ BREAKING CHANGES

* **authup:** Authup beta.64 changes CLI arguments, configuration paths, console topology, and several values. See charts/authup/BREAKING.md for migration steps.

### Features

* **authup:** support the beta.64 runtime topology ([#29](https://github.com/authup/helm/issues/29)) ([226f784](https://github.com/authup/helm/commit/226f784745d34f12454c54ea9b31f05d0d4339c3))

## [0.3.0](https://github.com/authup/helm/compare/root-0.2.2...root-0.3.0) (2026-08-24)


### ⚠ BREAKING CHANGES

* **authup:** the writable directory moves from /usr/src/app/writable to /var/lib/authup, and server.config.WRITABLE_DIRECTORY_PATH now fails the render instead of being honored. A server.extraVolumeMounts entry aimed at the old path no longer overlays the writable directory. Migration: charts/authup/BREAKING.md.

### Features

* **authup:** writable directory moves to /var/lib/authup, and route.enabled accepts a template ([#16](https://github.com/authup/helm/issues/16)) ([52e42f3](https://github.com/authup/helm/commit/52e42f3968b67a9c8f223c5ae9dd7c0e01346e23))


### Bug Fixes

* **authup:** give the migration hook only what a hook can see, and scope useHelmHooks to ArgoCD ([#20](https://github.com/authup/helm/issues/20)) ([bddbb7f](https://github.com/authup/helm/commit/bddbb7faa8aaaeea711f58139b70e3d0a228a194))

## [0.2.2](https://github.com/authup/helm/compare/root-0.2.1...root-0.2.2) (2026-08-19)


### Features

* **authup:** open the global schema node and let HTTPRoute rules carry matches/filters ([#13](https://github.com/authup/helm/issues/13)) ([a3ca5d5](https://github.com/authup/helm/commit/a3ca5d520cff62a5c658238090b977e325fd1d57))

## [0.2.1](https://github.com/authup/helm/compare/root-0.2.0...root-0.2.1) (2026-08-19)


### Features

* **authup:** track authup 1.0.0-beta.62 and compose theme.json from values ([#8](https://github.com/authup/helm/issues/8)) ([696ea13](https://github.com/authup/helm/commit/696ea13e868421d882bf3b7a57fc13b33c4c0dca))


### Bug Fixes

* let release-please own a root release so release PRs resume ([3a8df19](https://github.com/authup/helm/commit/3a8df19a536e1aec28d794262db83d13d46978d6))
