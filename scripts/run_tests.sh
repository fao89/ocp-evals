#!/usr/bin/env bash
# Test runner script for ocp-evals
#
# This script:
# 1. Extracts OPENAI_API_KEY from cluster secret
# 2. Creates API token for OLS authentication
# 3. Configures API endpoint
# 4. Runs tests

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}OCP Evaluation Tests${NC}"
echo -e "${GREEN}=====================================${NC}"
echo

# Check if we're in a Kubernetes cluster
if ! command -v oc &> /dev/null; then
    echo -e "${RED}Error: oc command not found${NC}"
    echo "Please install the OpenShift CLI (oc)"
    exit 1
fi

# Check cluster connection
if ! oc whoami &> /dev/null; then
    echo -e "${RED}Error: Not connected to an OpenShift cluster${NC}"
    echo "Please login with: oc login <cluster-url>"
    exit 1
fi

echo -e "${YELLOW}1. Retrieving OPENAI_API_KEY from cluster secret...${NC}"
if ! oc get secret openai-api-keys -n openshift-lightspeed &> /dev/null; then
    echo -e "${RED}Error: Secret 'openai-api-keys' not found in openshift-lightspeed namespace${NC}"
    echo "Please ensure the secret exists"
    exit 1
fi

export OPENAI_API_KEY=$(oc get secret openai-api-keys -n openshift-lightspeed -o jsonpath='{.data.apitoken}' | base64 -d)
echo -e "${GREEN}✓ OPENAI_API_KEY retrieved (${#OPENAI_API_KEY} chars)${NC}"

echo -e "${YELLOW}2. Creating API token for cluster access...${NC}"
if ! oc get sa ocp-eval-user -n openshift-lightspeed &> /dev/null; then
    echo -e "${YELLOW}Warning: ServiceAccount 'ocp-eval-user' not found${NC}"
    echo "Evaluation tests may fail if API mode is enabled"
else
    export API_KEY=$(oc create token ocp-eval-user -n openshift-lightspeed --duration=24h)
    echo -e "${GREEN}✓ API_KEY created (${#API_KEY} chars)${NC}"
fi

echo -e "${YELLOW}3. Configuring API endpoint...${NC}"
# Get the lightspeed-app-server service URL
if oc get svc lightspeed-app-server -n openshift-lightspeed &> /dev/null; then
    CLUSTER_IP=$(oc get svc lightspeed-app-server -n openshift-lightspeed -o jsonpath='{.spec.clusterIP}')
    PORT=$(oc get svc lightspeed-app-server -n openshift-lightspeed -o jsonpath='{.spec.ports[0].port}')
    export API_BASE_URL="https://${CLUSTER_IP}:${PORT}"
    echo -e "${GREEN}✓ API endpoint: ${API_BASE_URL}${NC}"
else
    echo -e "${YELLOW}Warning: lightspeed-app-server service not found${NC}"
    echo "Using default localhost:8080 from config"
fi

# Parse command line arguments
TEST_TYPE="${1:-basic}"

echo
echo -e "${YELLOW}4. Running tests...${NC}"
echo

case "$TEST_TYPE" in
    basic)
        echo -e "${GREEN}Running basic validation tests only...${NC}"
        pytest tests/test_basic.py -v
        ;;
    e2e)
        echo -e "${GREEN}Running end-to-end evaluation tests...${NC}"
        pytest tests/e2e/ -v
        ;;
    critical)
        echo -e "${GREEN}Running critical tests only...${NC}"
        pytest tests/ -v -m critical
        ;;
    all)
        echo -e "${GREEN}Running all tests...${NC}"
        pytest tests/ -v
        ;;
    cov)
        echo -e "${GREEN}Running tests with coverage...${NC}"
        pytest tests/ -v --cov=. --cov-report=term-missing --cov-report=html
        ;;
    *)
        echo -e "${RED}Unknown test type: $TEST_TYPE${NC}"
        echo
        echo "Usage: $0 [basic|e2e|critical|all|cov]"
        echo
        echo "Options:"
        echo "  basic     - Run basic validation tests only (default)"
        echo "  e2e       - Run end-to-end evaluation tests"
        echo "  critical  - Run tests marked as critical"
        echo "  all       - Run all tests"
        echo "  cov       - Run all tests with coverage report"
        exit 1
        ;;
esac

TEST_EXIT_CODE=$?

echo
if [ $TEST_EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}=====================================${NC}"
    echo -e "${GREEN}✓ Tests completed successfully!${NC}"
    echo -e "${GREEN}=====================================${NC}"
else
    echo -e "${RED}=====================================${NC}"
    echo -e "${RED}✗ Tests failed!${NC}"
    echo -e "${RED}=====================================${NC}"
fi

exit $TEST_EXIT_CODE
