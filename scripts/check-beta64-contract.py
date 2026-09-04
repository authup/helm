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


checks = {
    "base": check_base,
    "split": check_split,
    "all": lambda: (check_base(), check_split()),
}

if case not in checks:
    raise SystemExit(f"unknown contract case {case!r}: choose {', '.join(checks)}")

checks[case]()
print(f"beta.64 {case} contract OK")
