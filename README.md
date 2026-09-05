<div align="center">

[<img src="./assets/icon.svg" width="120" alt="Authup logo">](https://authup.org)

# Authup Helm Charts

Deploy [Authup](https://authup.org), an authentication & authorization system,
on Kubernetes.

[![lint-test](https://github.com/authup/helm/actions/workflows/lint-test.yaml/badge.svg)](https://github.com/authup/helm/actions/workflows/lint-test.yaml)
[![release](https://img.shields.io/github/v/release/authup/helm?style=flat-square)](https://github.com/authup/helm/releases)
[![license](https://img.shields.io/github/license/authup/helm?style=flat-square)](./LICENSE)
[![Conventional Commits](https://img.shields.io/badge/Conventional%20Commits-1.0.0-%23FE5196?logo=conventionalcommits&logoColor=white)](https://conventionalcommits.org)

</div>

**Table of Contents**

- [Highlights](#highlights)
- [Installation](#installation)
- [Quickstart](#quickstart)
- [Charts](#charts)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)

## Highlights

- 🔐 **Complete deployment** - the Authup IdP/API (OAuth2 / OpenID Connect,
  hosted login & consent pages) with its auth, admin and account consoles, as
  one combined server or as split workloads plus a background worker
- 🗄️ **Hybrid database model** - built-in PostgreSQL **or** MySQL for a
  one-command start, or bring your own external database
- ⚡ **Optional Valkey cache** - built-in instance or external Redis; required
  and enforced for multi-replica deployments
- 🧭 **Derived wiring** - `PUBLIC_URL` is derived from your ingress hostname and
  shared by every role, so logins work on the first install
- 🔑 **Secret management** - generate-once credentials that survive upgrades,
  `existingSecret` support on every credential, nothing ever rendered as a
  plain env value
- 🛡️ **Fail-fast guards** - misconfigurations (missing database, replicas
  without a cache, scheme-less URLs, conflicting secrets) fail at render time
  with actionable messages, not at CrashLoopBackOff
- 📦 **Zero chart dependencies** - built-in services are vendored templates on
  docker-official images; no third-party library or subchart risk

## Installation

```bash
helm repo add authup https://helm.authup.org
helm install authup authup/authup
```

Charts are also published as OCI artifacts:

```bash
helm install authup oci://ghcr.io/authup/helm/authup
```

The default install brings up one combined Authup server (API plus the auth,
admin and account consoles) and a built-in PostgreSQL. Retrieve the generated admin password:

```bash
kubectl get secret authup -o jsonpath='{.data.admin-password}' | base64 -d
```

## Quickstart

A typical production setup with one hostname and an external database:

```yaml
server:
  ingress:
    enabled: true
    hostname: auth.example.com
    tls: true

postgresql:
  enabled: false
externalDatabase:
  host: postgres.example.internal
  user: authup
  database: authup
  existingSecret: my-db-secret

valkey:
  enabled: true
```

Set `server.splitConsoles=true` to run the consoles as separate workloads and
`worker.enabled=true` for a dedicated background worker.

See the [chart README](./charts/authup/README.md) for every parameter and the
operational notes (GitOps caveats, scaling rules, the write-once encryption
key).

## Charts

| Chart | Description |
|---|---|
| [authup](./charts/authup) | Authup API and consoles (combined or split), optional worker, optional built-in PostgreSQL / MySQL / Valkey |

## Documentation

- [Chart parameters & operational notes](./charts/authup/README.md)
- [Design record](./DESIGN.md) - the architecture decisions behind this
  repository and the evidence they rest on
- [Authup documentation](https://authup.org)

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md). Releases are automated with
release-please (conventional commits drive chart versions) and published via
chart-releaser to `https://helm.authup.org` and to GHCR (OCI).

## License

[Apache-2.0](./LICENSE)
