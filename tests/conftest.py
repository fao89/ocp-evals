"""Pytest configuration for OCP evaluation tests."""

import pytest


def pytest_configure(config):
    """Register custom markers."""
    config.addinivalue_line(
        "markers",
        "cluster_updates: mark test as a cluster updates evaluation test",
    )
