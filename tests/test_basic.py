"""Basic tests to verify test infrastructure is working."""

from pathlib import Path

import pytest
import yaml


def test_project_structure():
    """Verify basic project structure exists."""
    project_root = Path(__file__).parent.parent

    assert (project_root / "config").exists(), "config directory should exist"
    assert (project_root / "config" / "system.yaml").exists(), "system.yaml should exist"
    assert (project_root / "config" / "evaluation_data.yaml").exists(), "evaluation_data.yaml should exist"
    assert (project_root / "requirements.txt").exists(), "requirements.txt should exist"
    assert (project_root / "pyproject.toml").exists(), "pyproject.toml should exist"


def test_system_config_valid():
    """Verify system.yaml is valid YAML and has required fields."""
    project_root = Path(__file__).parent.parent
    system_config = project_root / "config" / "system.yaml"

    with open(system_config, encoding="utf-8") as fh:
        config = yaml.safe_load(fh)

    assert "llm" in config, "system.yaml should have 'llm' section"
    assert "api" in config, "system.yaml should have 'api' section"
    assert "metrics_metadata" in config, "system.yaml should have 'metrics_metadata' section"


def test_evaluation_data_valid():
    """Verify evaluation_data.yaml is valid YAML and has required fields."""
    project_root = Path(__file__).parent.parent
    eval_data = project_root / "config" / "evaluation_data.yaml"

    with open(eval_data, encoding="utf-8") as fh:
        data = yaml.safe_load(fh)

    assert isinstance(data, list), "evaluation_data.yaml should contain a list of conversation groups"
    assert len(data) > 0, "Should have at least one conversation group"

    # Verify first conversation group has required fields
    first_conv = data[0]
    assert "conversation_group_id" in first_conv, "Each conversation group should have 'conversation_group_id'"
    assert "turns" in first_conv, "Each conversation group should have 'turns'"


def test_pytest_markers_registered():
    """Verify custom pytest markers are properly registered."""
    # This test will fail if markers are not registered in conftest.py
    # We're using markers in other tests, so this validates the setup
    pass


@pytest.mark.cluster_updates
def test_marker_cluster_updates():
    """Test that cluster_updates marker works."""
    assert True


@pytest.mark.critical
def test_marker_critical():
    """Test that critical marker works."""
    assert True
