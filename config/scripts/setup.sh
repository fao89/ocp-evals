#!/bin/bash
# Setup script for OCP evaluation
# This script runs before conversation evaluation to set up the test environment

set -e

echo "Setting up OCP evaluation test environment..."

# Example: Create test resources, set up RBAC, configure cluster state
# Customize based on your specific test requirements

# Example RBAC setup for MCP server access
# oc apply -f config/rbac-ocp-evals.yaml

# Example: Create test namespace
# oc create namespace test-cluster-updates || true

# Example: Label nodes for testing
# oc label node worker-0 test=cluster-updates --overwrite

echo "Setup complete"
