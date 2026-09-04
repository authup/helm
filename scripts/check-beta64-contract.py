#!/usr/bin/env python3
"""Assert the Authup beta.64 runtime contract against rendered manifests."""

import subprocess
import sys
import tempfile
from pathlib import Path

import yaml


chart = Path(sys.argv[1] if len(sys.argv) > 1 else "charts/authup")
case = sys.argv[2] if len(sys.argv) > 2 else "all"


def render(values=None, *args):
    command = ["helm", "template", "test", str(chart)]
    if isinstance(values, (str, Path)):
        result = subprocess.run(
            [*command, "-f", str(values), *args],
            check=True,
            capture_output=True,
            text=True,
        )
    elif values is not None:
        with tempfile.NamedTemporaryFile("w", suffix=".yaml") as handle:
            yaml.safe_dump(values, handle)
            handle.flush()
            result = subprocess.run(
                [*command, "-f", handle.name, *args],
                check=True,
                capture_output=True,
                text=True,
            )
    else:
        result = subprocess.run(
            [*command, *args],
            check=True,
            capture_output=True,
            text=True,
        )
    return [document for document in yaml.safe_load_all(result.stdout) if document]


def one(documents, kind, component, suffix=None):
    matches = [
        document for document in documents
        if document.get("kind") == kind
        and document.get("metadata", {}).get("labels", {}).get(
            "app.kubernetes.io/component"
        ) == component
        and (suffix is None or document["metadata"]["name"].endswith(suffix))
    ]
    assert len(matches) == 1, (
        f"expected one {kind} for component {component!r}, got "
        f"{[item['metadata']['name'] for item in matches]}"
    )
    return matches[0]


def container(workload):
    return workload["spec"]["template"]["spec"]["containers"][0]


def container_mounts(workload):
    return {
        mount["name"]: (mount["mountPath"], mount.get("subPath"))
        for mount in container(workload).get("volumeMounts", [])
    }


def env_value(workload_container, name):
    for entry in workload_container.get("env", []):
        if entry["name"] == name:
            return entry.get("value")
    return None


def env_config(workload, documents):
    reference = container(workload)["envFrom"][0]["configMapRef"]["name"]
    matches = [
        document for document in documents
        if document.get("kind") == "ConfigMap"
        and document["metadata"]["name"] == reference
    ]
    assert len(matches) == 1, f"missing env ConfigMap {reference}"
    return matches[0]["data"]


def effective_env(workload, documents):
    values = {}
    for source in container(workload).get("envFrom", []):
        reference = source.get("configMapRef")
        if reference:
            matches = [
                document for document in documents
                if document.get("kind") == "ConfigMap"
                and document["metadata"]["name"] == reference["name"]
            ]
            if matches:
                values.update(matches[0].get("data", {}))
    for entry in container(workload).get("env", []):
        values[entry["name"]] = entry.get("value", "<valueFrom>")
    return values


def component_deployments(documents):
    return {
        document["metadata"]["labels"]["app.kubernetes.io/component"]: document
        for document in documents
        if document.get("kind") == "Deployment"
        and document.get("metadata", {}).get("labels", {}).get(
            "app.kubernetes.io/component"
        )
    }


def ingress_paths(ingress):
    return ingress["spec"]["rules"][0]["http"]["paths"]


def exact_backend(ingress, path):
    matches = [item for item in ingress_paths(ingress) if item["path"] == path]
    assert len(matches) == 1, f"expected one ingress path {path}, got {matches}"
    assert matches[0]["pathType"] == "Exact"
    return matches[0]["backend"]["service"]["name"]


def peer_components(policy, direction):
    components = set()
    peer_key = "from" if direction == "ingress" else "to"
    for rule in policy["spec"].get(direction, []):
        for peer in rule.get(peer_key, []):
            component = peer.get("podSelector", {}).get("matchLabels", {}).get(
                "app.kubernetes.io/component"
            )
            if component:
                components.add(component)
    return components


def check_base():
    documents = render()
    deployments = component_deployments(documents)
    assert not ({"auth-console", "admin-console", "account-console"} & set(deployments))
    server = one(documents, "Deployment", "server")
    assert container(server)["args"] == ["start"]
    assert env_value(container(server), "WORKER_ENABLED") is None
    assert env_value(container(server), "MIGRATION_ENABLED") is None
    assert server["metadata"]["labels"]["app.kubernetes.io/version"] == "1.0.0-beta.64"

    configured_values = {
        "server": {
            "configuration": "core:\n  trustProxy: '1'\n",
            "provisioning": {
                "enabled": True,
                "files": {"realms.yaml": "[]\n"},
            },
        }
    }
    configured = render(configured_values)
    configuration = one(
        configured, "ConfigMap", "server", suffix="-configuration"
    )
    assert set(configuration["data"]) == {"authup.yml"}
    server = one(configured, "Deployment", "server")
    mounts = container_mounts(server)
    assert mounts["configuration"] == ("/etc/authup/authup.yml", "authup.yml")
    assert mounts["provisioning"][0] == "/etc/authup/provisioning"
    assert mounts["logs"][0] == "/var/log/authup"
    environment = env_config(server, configured)
    assert environment["PROVISIONING_DIRECTORY_PATH"] == "/etc/authup/provisioning"
    assert environment["LOG_DIRECTORY_PATH"] == "/var/log/authup"
    assert "WRITABLE_DIRECTORY_PATH" not in environment

    migration_values = {
        "server": {
            "configuration": "core:\n  trustProxy: '1'\n",
            "migration": {"enabled": True},
        }
    }
    migration_documents = render(migration_values)
    migration = one(migration_documents, "Job", "migration")
    assert container(migration)["args"] == ["migration", "run"]
    migration_mounts = container_mounts(migration)
    assert migration_mounts["configuration"] == (
        "/etc/authup/authup.yml",
        "authup.yml",
    )
    assert migration_mounts["logs"][0] == "/var/log/authup"


def check_split():
    documents = render(chart / "ci" / "split-values.yaml")
    deployments = component_deployments(documents)
    expected = {
        "server": ["start", "core"],
        "auth-console": ["start", "console", "auth"],
        "admin-console": ["start", "console", "admin"],
        "account-console": ["start", "console", "account"],
    }
    assert {
        component: container(deployments[component])["args"]
        for component in expected
    } == expected

    expected_ports = {
        "auth-console": 3020,
        "admin-console": 3021,
        "account-console": 3022,
    }
    for component, port in expected_ports.items():
        ports = container(deployments[component])["ports"]
        assert ports == [{"name": "http", "containerPort": port, "protocol": "TCP"}]
        environment = effective_env(deployments[component], documents)
        assert environment["PUBLIC_URL"] == "https://auth.example.com"
        assert environment["INTERNAL_URL"] == "http://test-authup-server:3000"
        assert not (
            {"DB_PASSWORD", "REDIS", "SMTP", "USER_ADMIN_PASSWORD", "CLIENT_SYSTEM_SECRET"}
            & set(environment)
        )

    worker = one(documents, "Deployment", "worker")
    worker_container = container(worker)
    assert worker_container["args"] == ["start", "worker"]
    assert "ports" not in worker_container
    assert not (
        {"startupProbe", "livenessProbe", "readinessProbe"}
        & set(worker_container)
    )
    worker_env = effective_env(worker, documents)
    assert worker_env["WORKER_ENABLED"] == "true"
    assert effective_env(deployments["server"], documents)["WORKER_ENABLED"] == "false"
    assert "DB_PASSWORD" in worker_env
    assert "REDIS" in worker_env
    assert "SMTP" not in worker_env
    assert "USER_ADMIN_PASSWORD" not in worker_env
    assert "CLIENT_SYSTEM_SECRET" not in worker_env
    assert "MIGRATION_ENABLED" not in worker_env

    upgrade = render(chart / "ci" / "split-values.yaml", "--is-upgrade")
    upgrade_server = one(upgrade, "Deployment", "server")
    assert effective_env(upgrade_server, upgrade)["MIGRATION_ENABLED"] == "false"
    assert "MIGRATION_ENABLED" not in effective_env(deployments["server"], documents)


def check_routing():
    documents = render(chart / "ci" / "split-values.yaml")
    for component, name in (
        ("auth-console", "auth"),
        ("admin-console", "admin"),
        ("account-console", "account"),
    ):
        ingress = one(documents, "Ingress", component)
        annotations = ingress["metadata"]["annotations"]
        assert annotations["nginx.ingress.kubernetes.io/use-regex"] == "true"
        assert annotations["nginx.ingress.kubernetes.io/rewrite-target"] == "/$2"
        assert ingress_paths(ingress)[0]["path"] == f"/console/{name}(/|$)(.*)"
        assert ingress_paths(ingress)[0]["pathType"] == "ImplementationSpecific"

    server_ingress = one(documents, "Ingress", "server")
    for path in (
        "/console/admin/login/start",
        "/console/admin/callback",
        "/console/account/login/start",
        "/console/account/callback",
    ):
        assert exact_backend(server_ingress, path) == "test-authup-server"

    route_values = {
        "server": {
            "publicUrl": "https://auth.example.com",
            "splitConsoles": True,
            "route": {"enabled": True, "parentRefs": [{"name": "gateway"}]},
        },
        "authConsole": {"route": {"enabled": True}},
        "adminConsole": {"route": {"enabled": True}},
        "accountConsole": {"route": {"enabled": True}},
    }
    routes = render(route_values)
    for component, name in (
        ("auth-console", "auth"),
        ("admin-console", "admin"),
        ("account-console", "account"),
    ):
        route = one(routes, "HTTPRoute", component)
        rule = route["spec"]["rules"][0]
        assert rule["matches"] == [
            {"path": {"type": "PathPrefix", "value": f"/console/{name}"}}
        ]
        assert rule["filters"] == [
            {
                "type": "URLRewrite",
                "urlRewrite": {
                    "path": {
                        "type": "ReplacePrefixMatch",
                        "replacePrefixMatch": "/",
                    }
                },
            }
        ]

    server_route = one(routes, "HTTPRoute", "server")
    rules = server_route["spec"]["rules"]
    expected_paths = [
        "/console/admin/login/start",
        "/console/admin/callback",
        "/console/account/login/start",
        "/console/account/callback",
    ]
    assert [rule["matches"][0]["path"]["value"] for rule in rules[:4]] == expected_paths
    assert all(rule["matches"][0]["path"]["type"] == "Exact" for rule in rules[:4])


def check_policy():
    documents = render(chart / "ci" / "split-values.yaml")
    migration = one(documents, "NetworkPolicy", "migration")
    assert migration["spec"]["podSelector"]["matchLabels"][
        "app.kubernetes.io/component"
    ] == "migration"
    annotations = migration["metadata"]["annotations"]
    assert annotations["helm.sh/hook"] == "pre-upgrade"
    assert annotations["helm.sh/hook-weight"] == "-5"
    assert migration["spec"]["policyTypes"] == ["Egress"]

    worker = one(documents, "NetworkPolicy", "worker")
    assert worker["spec"]["policyTypes"] == ["Egress"]

    for component in ("auth-console", "admin-console", "account-console"):
        policy = one(documents, "NetworkPolicy", component)
        assert peer_components(policy, "egress") == {"server"}

    server = one(documents, "NetworkPolicy", "server")
    assert {
        "auth-console",
        "admin-console",
        "account-console",
    } <= peer_components(server, "ingress")

    argocd_documents = render(
        chart / "ci" / "split-values.yaml",
        "--set",
        "useHelmHooks=false",
    )
    argocd = one(argocd_documents, "NetworkPolicy", "migration")
    annotations = argocd["metadata"]["annotations"]
    assert annotations["argocd.argoproj.io/hook"] == "PreSync"
    assert annotations["argocd.argoproj.io/sync-wave"] == "-5"
    assert "helm.sh/hook" not in annotations


checks = {
    "base": check_base,
    "split": check_split,
    "routing": check_routing,
    "policy": check_policy,
    "all": lambda: (check_base(), check_split(), check_routing(), check_policy()),
}

if case not in checks:
    raise SystemExit(f"unknown contract case {case!r}: choose {', '.join(checks)}")

checks[case]()
print(f"beta.64 {case} contract OK")
