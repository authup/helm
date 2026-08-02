# Authup Helm Charts

Helm charts for [Authup](https://authup.org) — an authentication &
authorization system.

## Usage

```bash
helm repo add authup https://authup.github.io/helm
helm repo update
helm install authup authup/authup
```

Charts are also published as OCI artifacts:

```bash
helm install authup oci://ghcr.io/authup/helm-charts/authup
```

## Charts

| Chart | Description |
|---|---|
| [authup](./charts/authup) | server-core (IdP/API) + client-web (admin UI), optional built-in PostgreSQL / MySQL / Valkey |

## Development

See [CONTRIBUTING.md](./CONTRIBUTING.md). Releases are automated with
release-please (conventional commits drive chart versions) and published via
chart-releaser to the `gh-pages` index and to GHCR (OCI).

## License

MIT
