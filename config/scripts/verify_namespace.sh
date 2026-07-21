#!/bin/bash
# Verification script for namespace creation
# This script validates that a specific action was completed successfully

set -e

NAMESPACE="${NAMESPACE:-test-ns}"

echo "Verifying namespace: $NAMESPACE"

# Check if namespace exists
if oc get namespace "$NAMESPACE" &>/dev/null; then
    echo "SUCCESS: Namespace $NAMESPACE exists"
    exit 0
else
    echo "FAILURE: Namespace $NAMESPACE does not exist"
    exit 1
fi
