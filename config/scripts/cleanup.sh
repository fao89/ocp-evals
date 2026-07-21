#!/bin/bash
# Cleanup script for OCP evaluation
# This script runs after conversation evaluation to clean up test resources

set -e

echo "Cleaning up OCP evaluation test environment..."

# Example: Remove test resources
# Customize based on your specific test requirements

# Example: Delete test namespace
# oc delete namespace test-cluster-updates --ignore-not-found=true

# Example: Remove node labels
# oc label node worker-0 test-

# Example: Clean up test deployments
# oc delete deployment test-app -n test-cluster-updates --ignore-not-found=true

echo "Cleanup complete"
