#!/usr/bin/env bash
# Cluster Updates Evaluation Test Suite
#
# This script runs the full cluster-updates evaluation test suite.
# It matches the pattern from lightspeed-service/tests/scripts/test-cluster-updates.sh
#
# Usage:
#   ./tests/scripts/test-cluster-updates.sh [OPTIONS]
#
# Options:
#   --use-uv              Use uv package manager instead of pip
#   --artifact-dir DIR    Output directory for test artifacts (default: ./test_results)
#   --skip-rbac           Skip RBAC setup (use if already configured)
#   --cleanup             Cleanup RBAC after tests
#   --help                Show this help message
#
# Environment Variables:
#   OPENAI_API_KEY        Judge LLM API key (auto-retrieved from cluster if not set)
#   API_KEY               OLS API authentication token (auto-created if not set)
#   API_BASE_URL          OLS API endpoint (auto-detected from cluster if not set)
#   ARTIFACT_DIR          Output directory override (default: ./test_results)
#   PROVIDER              LLM provider for OLS (openai, watsonx, google_vertex, google_vertex_anthropic)
#   PROVIDER_KEY_PATH     Path to provider credentials file
#   OLS_IMAGE             OLS container image to deploy (from CI dependency)
#   BUNDLE_IMAGE          Operator bundle image (default: quay.io/openshift-lightspeed/lightspeed-operator-bundle:latest)

set -eo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source utilities
source "$SCRIPT_DIR/utils.sh"

# Default values
USE_UV=false
ARTIFACT_DIR="${ARTIFACT_DIR:-./test_results}"
SKIP_RBAC=false
CLEANUP_RBAC=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --use-uv)
            USE_UV=true
            shift
            ;;
        --artifact-dir)
            ARTIFACT_DIR="$2"
            shift 2
            ;;
        --skip-rbac)
            SKIP_RBAC=true
            shift
            ;;
        --cleanup)
            CLEANUP_RBAC=true
            shift
            ;;
        --help)
            grep '^#' "$0" | grep -v '#!/usr/bin/env' | sed 's/^# //'
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Run with --help for usage information"
            exit 1
            ;;
    esac
done

# Change to project root
cd "$PROJECT_ROOT"

log_info "=========================================="
log_info "Cluster Updates Evaluation Test Suite"
log_info "=========================================="
log_info "Project root: $PROJECT_ROOT"
log_info "Artifact directory: $ARTIFACT_DIR"
log_info "Using uv: $USE_UV"
log_info "Provider: ${PROVIDER:-<not set, skipping OLS deployment>}"
log_info ""

# Trap to ensure cleanup on exit
TESTS_PASSED=false

cleanup_on_exit() {
    local exit_code=$?

    if [[ $exit_code -ne 0 && -n "${PROVIDER:-}" ]]; then
        log_error "Test suite failed with exit code $exit_code"
        log_info "Dumping OLS diagnostics to ${ARTIFACT_DIR}/ols-debug-dump.txt ..."
        mkdir -p "$ARTIFACT_DIR"
        dump_ols_debug 2>&1 | tee "${ARTIFACT_DIR}/ols-debug-dump.txt" || true
        log_info "Skipping OLS cleanup to preserve namespace for gather-must-gather"
        log_info "Namespace ${OLS_NAMESPACE:-openshift-lightspeed} left intact for debugging"
    fi

    if [[ "$CLEANUP_RBAC" == "true" ]]; then
        log_info "Performing RBAC cleanup..."
        cleanup_rbac "$PROJECT_ROOT/config/rbac-ocp-evals.yaml"
    fi

    if [[ "$TESTS_PASSED" == "true" && -n "${PROVIDER:-}" ]]; then
        log_info "Performing OLS cleanup..."
        cleanup_ols_operator || true
    fi

    if [[ $exit_code -ne 0 ]]; then
        log_info "Check artifacts in: $ARTIFACT_DIR"
    fi

    exit $exit_code
}

trap cleanup_on_exit EXIT

# Step 1: Validate cluster connection
log_info "Step 1: Validating cluster connection..."
validate_cluster_connection || {
    log_error "Cluster validation failed"
    exit 1
}

# Step 2: Install dependencies (before OLS deployment so PyYAML is available)
log_info "Step 2: Installing dependencies..."
install_dependencies "$USE_UV" || {
    log_error "Failed to install dependencies"
    exit 1
}

# Verify lightspeed-eval is installed
if ! command_exists lightspeed-eval; then
    log_error "lightspeed-eval command not found after installation"
    log_error "Check that the evaluation framework was installed correctly"
    exit 1
fi

log_success "lightspeed-eval found: $(which lightspeed-eval)"

# Step 3: Deploy OLS (if PROVIDER is set — CI mode)
if [[ -n "${PROVIDER:-}" ]]; then
    log_info "Step 3: Deploying OLS..."
    if [[ -z "${PROVIDER_KEY_PATH:-}" ]]; then
        log_error "PROVIDER_KEY_PATH must be set when PROVIDER is set"
        exit 1
    fi
    deploy_ols "$PROVIDER" "$PROVIDER_KEY_PATH" || {
        log_error "OLS deployment failed"
        exit 1
    }
else
    log_info "Step 3: Skipping OLS deployment (PROVIDER not set)"
fi

# Step 4: Apply RBAC configuration
if [[ "$SKIP_RBAC" == "false" ]]; then
    log_info "Step 4: Applying RBAC configuration..."
    apply_rbac "$PROJECT_ROOT/config/rbac-ocp-evals.yaml" || {
        log_warning "RBAC setup failed, continuing anyway"
        log_warning "Tests may fail if permissions are insufficient"
    }
else
    log_info "Step 4: Skipping RBAC setup (--skip-rbac flag)"
fi

# Step 5: Setup environment (get secrets from cluster)
log_info "Step 5: Setting up environment..."

# Get OPENAI_API_KEY from cluster if not already set
if [[ -z "$OPENAI_API_KEY" ]]; then
    get_openai_key_from_cluster "openshift-lightspeed" "openai-api-keys" "apitoken" || {
        log_error "Failed to retrieve OPENAI_API_KEY from cluster"
        log_error "Please set OPENAI_API_KEY environment variable manually"
        exit 1
    }
else
    log_info "Using OPENAI_API_KEY from environment (${#OPENAI_API_KEY} chars)"
fi

# Create API token if not already set
if [[ -z "${API_KEY:-}" ]]; then
    create_api_token "openshift-lightspeed" "ocp-eval-user" "24h" || {
        log_warning "Failed to create API token, continuing without it"
        log_warning "Tests may fail if API mode is enabled in config"
    }
else
    log_info "Using API_KEY from environment (${#API_KEY} chars)"
fi

# Get API endpoint if not already set (deploy_ols sets API_BASE_URL)
if [[ -z "${API_BASE_URL:-}" ]]; then
    get_api_endpoint "openshift-lightspeed" "lightspeed-app-server" || {
        log_warning "Failed to detect API endpoint, using default from config"
    }
else
    log_info "Using API_BASE_URL from environment: $API_BASE_URL"
fi

# Step 6: Run tests
log_info "Step 6: Running cluster-updates tests..."
log_info ""

mkdir -p "$ARTIFACT_DIR"

EXTRA_PYTEST_ARGS=""
if [[ -n "${EVAL_TAG:-}" ]]; then
    EXTRA_PYTEST_ARGS="-k $EVAL_TAG"
    log_info "Filtering tests by tag: $EVAL_TAG"
fi

run_cluster_updates_tests "cluster_updates" "$ARTIFACT_DIR" "$EXTRA_PYTEST_ARGS" || {
    TEST_EXIT_CODE=$?
    log_error "Tests failed with exit code $TEST_EXIT_CODE"

    # Still collect artifacts even on failure
    log_info "Collecting artifacts from failed test run..."
    collect_artifacts "$PROJECT_ROOT" "$ARTIFACT_DIR"

    exit $TEST_EXIT_CODE
}

# Step 7: Collect artifacts
log_info "Step 7: Collecting test artifacts..."
collect_artifacts "$PROJECT_ROOT" "$ARTIFACT_DIR"

TESTS_PASSED=true

# Success!
log_success "=========================================="
log_success "Test suite completed successfully!"
log_success "=========================================="
log_success "Results available in: $ARTIFACT_DIR"
log_success ""

exit 0
