from pathlib import Path

import pytest

from fabric_sre.config import ConfigurationError, load_config

ROOT = Path(__file__).parents[1]


def test_example_configuration_is_valid(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("AZURE_TENANT_ID", "00000000-0000-0000-0000-000000000001")
    monkeypatch.setenv("AZURE_SUBSCRIPTION_ID", "00000000-0000-0000-0000-000000000002")
    monkeypatch.setenv("AZURE_FOUNDRY_SUBSCRIPTION_ID", "00000000-0000-0000-0000-000000000003")
    monkeypatch.setenv("FOUNDRY_RESOURCE_GROUP", "rg-agent")
    monkeypatch.setenv("FOUNDRY_AGENT_NAME", "fabric-agent")
    monkeypatch.setenv("FABRIC_ADMIN_MCP_APP_NAME", "fabric-admin-mcp")
    monkeypatch.setenv("FABRIC_ADMIN_MCP_ENVIRONMENT_NAME", "fabric-tools")
    monkeypatch.setenv("FABRIC_ADMIN_MANAGED_IDENTITY_NAME", "fabric-agent-identity")
    monkeypatch.setenv("FABRIC_ADMIN_MCP_REGISTRY_NAME", "fabrictoolsacr")
    monkeypatch.setenv("FABRIC_ADMIN_SERVICE_PRINCIPAL_NAME", "fabric-admin-reader")
    monkeypatch.setenv("FABRIC_ADMIN_API_SECURITY_GROUP_NAME", "fabric-admin-readers")
    monkeypatch.setenv("AZURE_LOCATION", "canadacentral")
    config = load_config(
        ROOT / "config" / "client.parameters.example.yaml",
        ROOT / "config" / "client.parameters.schema.json",
    )
    assert config["fabric"]["historyDays"] >= 60
    assert config["azure"]["subscriptionIds"][0].endswith("0002")
    assert config["approvals"]["allowedActions"] == []


def test_missing_environment_variable_is_explicit(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("AZURE_TENANT_ID", raising=False)
    monkeypatch.setenv("AZURE_SUBSCRIPTION_ID", "sub")
    monkeypatch.setenv("AZURE_FOUNDRY_SUBSCRIPTION_ID", "foundry-sub")
    monkeypatch.setenv("FOUNDRY_RESOURCE_GROUP", "rg-agent")
    monkeypatch.setenv("FOUNDRY_AGENT_NAME", "fabric-agent")
    with pytest.raises(ConfigurationError, match="AZURE_TENANT_ID"):
        load_config(
            ROOT / "config" / "client.parameters.example.yaml",
            ROOT / "config" / "client.parameters.schema.json",
        )


def _example_with_actions(tmp_path: Path, actions: str) -> Path:
    source = (ROOT / "config" / "client.parameters.example.yaml").read_text(encoding="utf-8")
    assert "allowedActions: []" in source
    target = tmp_path / "client.parameters.yaml"
    target.write_text(
        source.replace("allowedActions: []", f"allowedActions: {actions}"),
        encoding="utf-8",
    )
    return target


def _set_example_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    for name in (
        "AZURE_TENANT_ID",
        "AZURE_SUBSCRIPTION_ID",
        "AZURE_FOUNDRY_SUBSCRIPTION_ID",
        "FOUNDRY_RESOURCE_GROUP",
        "FOUNDRY_AGENT_NAME",
        "FABRIC_ADMIN_MCP_APP_NAME",
        "FABRIC_ADMIN_MCP_ENVIRONMENT_NAME",
        "FABRIC_ADMIN_MANAGED_IDENTITY_NAME",
        "FABRIC_ADMIN_MCP_REGISTRY_NAME",
        "FABRIC_ADMIN_SERVICE_PRINCIPAL_NAME",
        "FABRIC_ADMIN_API_SECURITY_GROUP_NAME",
        "AZURE_LOCATION",
    ):
        monkeypatch.setenv(name, "contoso")


def test_operator_can_opt_in_to_supported_actions(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    _set_example_environment(monkeypatch)
    config = load_config(
        _example_with_actions(tmp_path, '["capacity.resume", "capacity.suspend"]'),
        ROOT / "config" / "client.parameters.schema.json",
    )
    assert config["approvals"]["allowedActions"] == ["capacity.resume", "capacity.suspend"]


def test_unknown_action_is_rejected_by_schema(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    _set_example_environment(monkeypatch)
    with pytest.raises(ConfigurationError, match="approvals.allowedActions"):
        load_config(
            _example_with_actions(tmp_path, '["workspace.delete"]'),
            ROOT / "config" / "client.parameters.schema.json",
        )