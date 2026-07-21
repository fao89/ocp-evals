#!/usr/bin/env bash
# Common utilities for ocp-evals test execution
#
# This script provides helper functions for test orchestration,
# matching the pattern from lightspeed-service/tests/scripts/utils.sh

set -eo pipefail

# Colors for output
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Validate required environment variables
validate_env() {
    local required_vars=("$@")
    local missing_vars=()

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            missing_vars+=("$var")
        fi
    done

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables:"
        for var in "${missing_vars[@]}"; do
            log_error "  - $var"
        done
        return 1
    fi

    return 0
}

# Check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Validate cluster connection
validate_cluster_connection() {
    if ! command_exists oc; then
        log_error "oc command not found. Please install OpenShift CLI."
        return 1
    fi

    if ! oc whoami &> /dev/null; then
        log_error "Not connected to OpenShift cluster. Run: oc login <cluster-url>"
        return 1
    fi

    log_success "Connected to cluster: $(oc whoami --show-server)"
    return 0
}

# Extract OPENAI_API_KEY from cluster secret
get_openai_key_from_cluster() {
    local namespace="${1:-openshift-lightspeed}"
    local secret_name="${2:-openai-api-keys}"
    local key_field="${3:-apitoken}"

    log_info "Retrieving OPENAI_API_KEY from cluster secret..."

    if ! oc get secret "$secret_name" -n "$namespace" &> /dev/null; then
        log_error "Secret '$secret_name' not found in namespace '$namespace'"
        return 1
    fi

    local api_key
    api_key=$(oc get secret "$secret_name" -n "$namespace" -o jsonpath="{.data.$key_field}" | base64 -d)

    if [[ -z "$api_key" ]]; then
        log_error "Failed to extract API key from secret"
        return 1
    fi

    export OPENAI_API_KEY="$api_key"
    log_success "OPENAI_API_KEY retrieved (${#OPENAI_API_KEY} chars)"
    return 0
}

# Create service account token for API access
create_api_token() {
    local namespace="${1:-openshift-lightspeed}"
    local service_account="${2:-ocp-eval-user}"
    local duration="${3:-24h}"

    log_info "Creating API token for ServiceAccount '$service_account'..."

    if ! oc get sa "$service_account" -n "$namespace" &> /dev/null; then
        log_warning "ServiceAccount '$service_account' not found in namespace '$namespace'"
        log_warning "Tests may fail if API mode is enabled"
        return 1
    fi

    local token
    token=$(oc create token "$service_account" -n "$namespace" --duration="$duration" 2>&1)

    if [[ $? -ne 0 ]]; then
        log_error "Failed to create token: $token"
        return 1
    fi

    export API_KEY="$token"
    log_success "API_KEY created (${#API_KEY} chars, valid for $duration)"
    return 0
}

# Get API endpoint from cluster service
get_api_endpoint() {
    local namespace="${1:-openshift-lightspeed}"
    local service_name="${2:-lightspeed-app-server}"

    log_info "Resolving API endpoint from service '$service_name'..."

    if ! oc get svc "$service_name" -n "$namespace" &> /dev/null; then
        log_warning "Service '$service_name' not found in namespace '$namespace'"
        log_warning "Using default endpoint from config"
        return 1
    fi

    local cluster_ip port
    cluster_ip=$(oc get svc "$service_name" -n "$namespace" -o jsonpath='{.spec.clusterIP}')
    port=$(oc get svc "$service_name" -n "$namespace" -o jsonpath='{.spec.ports[0].port}')

    export API_BASE_URL="https://${cluster_ip}:${port}"
    log_success "API endpoint: $API_BASE_URL"
    return 0
}

# Setup environment for cluster-updates tests
setup_cluster_updates_env() {
    log_info "Setting up cluster-updates test environment..."

    # Validate cluster connection
    validate_cluster_connection || return 1

    # Get OPENAI_API_KEY from cluster secret
    get_openai_key_from_cluster "openshift-lightspeed" "openai-api-keys" "apitoken" || return 1

    # Create API token (optional, may fail if SA doesn't exist)
    create_api_token "openshift-lightspeed" "ocp-eval-user" "24h" || log_warning "Continuing without API_KEY"

    # Get API endpoint (optional)
    get_api_endpoint "openshift-lightspeed" "lightspeed-app-server" || log_warning "Using default API endpoint"

    log_success "Environment setup complete"
    return 0
}

# Install evaluation framework dependencies
install_dependencies() {
    local use_uv="${1:-false}"

    log_info "Installing dependencies..."

    if [[ "$use_uv" == "true" ]]; then
        if ! command_exists uv; then
            log_error "uv command not found. Install with: pip install uv"
            return 1
        fi

        log_info "Installing with uv..."
        uv sync --extra lseval || return 1
    else
        log_info "Installing with pip..."
        pip install -r requirements.txt || return 1
    fi

    log_success "Dependencies installed"
    return 0
}

# Run cluster-updates evaluation tests
run_cluster_updates_tests() {
    local marker="${1:-cluster_updates}"
    local output_dir="${2:-./test_results}"
    local extra_args="${3:-}"

    log_info "Running cluster-updates tests..."

    # Ensure output directory exists
    mkdir -p "$output_dir"

    # Build pytest command
    local pytest_cmd="pytest tests/e2e/evaluation -vv -s -m $marker"

    # Add junit XML output if output_dir is set
    if [[ -n "$output_dir" ]]; then
        pytest_cmd="$pytest_cmd --junit-xml=$output_dir/junit_e2e_cluster_updates.xml"
    fi

    # Add any extra arguments
    if [[ -n "$extra_args" ]]; then
        pytest_cmd="$pytest_cmd $extra_args"
    fi

    log_info "Command: $pytest_cmd"

    # Run tests
    eval "$pytest_cmd"
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_success "Tests passed"
    else
        log_error "Tests failed with exit code $exit_code"
    fi

    return $exit_code
}

# Collect test artifacts
collect_artifacts() {
    local source_dir="${1:-.}"
    local artifact_dir="${2:-./artifacts}"

    log_info "Collecting test artifacts..."

    mkdir -p "$artifact_dir"

    # Copy evaluation outputs
    if [[ -d "$source_dir/eval_output" ]]; then
        log_info "Copying eval_output to artifacts..."
        cp -r "$source_dir/eval_output"/* "$artifact_dir/" 2>/dev/null || true
    fi

    # Copy pytest results
    if [[ -f "$source_dir/test_results/junit_e2e_cluster_updates.xml" ]]; then
        log_info "Copying junit XML to artifacts..."
        cp "$source_dir/test_results/junit_e2e_cluster_updates.xml" "$artifact_dir/" 2>/dev/null || true
    fi

    # Copy any CSV/JSON results
    find "$source_dir" -name "*.csv" -o -name "*_summary.json" | while read -r file; do
        log_info "Copying $(basename "$file") to artifacts..."
        cp "$file" "$artifact_dir/" 2>/dev/null || true
    done

    log_success "Artifacts collected to $artifact_dir"
    return 0
}

# Apply RBAC configuration
apply_rbac() {
    local rbac_file="${1:-config/rbac-ocp-evals.yaml}"

    log_info "Applying RBAC configuration..."

    if [[ ! -f "$rbac_file" ]]; then
        log_error "RBAC file not found: $rbac_file"
        return 1
    fi

    oc apply -f "$rbac_file" || return 1

    log_success "RBAC configuration applied"
    return 0
}

# Cleanup RBAC configuration
cleanup_rbac() {
    local rbac_file="${1:-config/rbac-ocp-evals.yaml}"

    log_info "Cleaning up RBAC configuration..."

    if [[ ! -f "$rbac_file" ]]; then
        log_warning "RBAC file not found: $rbac_file (skipping cleanup)"
        return 0
    fi

    oc delete -f "$rbac_file" --ignore-not-found=true || log_warning "Failed to delete RBAC resources"

    log_success "RBAC cleanup complete"
    return 0
}

# ============================================================
# OLS Deployment Functions
# ============================================================

OC_RETRY_COUNT=120
OC_RETRY_DELAY=5
OPERATOR_SDK_VERSION="v1.36.1"
DEFAULT_BUNDLE_IMAGE="quay.io/openshift-lightspeed/lightspeed-operator-bundle:latest"
OLS_NAMESPACE="openshift-lightspeed"

install_operator_sdk() {
    log_info "Installing operator-sdk ${OPERATOR_SDK_VERSION}..."

    local arch os
    arch=$(case $(uname -m) in x86_64) echo -n amd64 ;; aarch64) echo -n arm64 ;; *) echo -n "$(uname -m)" ;; esac)
    os=$(uname | awk '{print tolower($0)}')
    local dl_url="https://github.com/operator-framework/operator-sdk/releases/download/${OPERATOR_SDK_VERSION}"

    curl -LO "${dl_url}/operator-sdk_${os}_${arch}" || return 1
    mkdir -p "$HOME/.local/bin"
    chmod +x "operator-sdk_${os}_${arch}"
    mv "operator-sdk_${os}_${arch}" "$HOME/.local/bin/operator-sdk"
    export PATH="$HOME/.local/bin:$PATH"

    operator-sdk version || return 1
    log_success "operator-sdk installed"
}

dump_ols_debug() {
    log_warning "=== OLS Debug Dump ==="
    for label_args in \
        "OLSConfig:get olsconfig cluster -o yaml" \
        "Deployments:get deployments -n ${OLS_NAMESPACE}" \
        "CSV:get csv -n ${OLS_NAMESPACE} -o wide" \
        "Pods:get pods -n ${OLS_NAMESPACE} -o wide" \
        "Pod Details:get pods -n ${OLS_NAMESPACE} -o yaml" \
        "Pod Descriptions:describe pods -n ${OLS_NAMESPACE}" \
        "CatalogSources:get catalogsource -n ${OLS_NAMESPACE} -o yaml" \
        "InstallPlans:get installplan -n ${OLS_NAMESPACE} -o yaml" \
        "Subscriptions:get subscription -n ${OLS_NAMESPACE} -o yaml" \
        "Events:get events -n ${OLS_NAMESPACE} --sort-by=.lastTimestamp -o wide"; do
        local label="${label_args%%:*}"
        local args="${label_args#*:}"
        log_info "--- ${label} ---"
        oc ${args} 2>&1 || true
    done

    log_info "--- Pod Logs ---"
    local pods
    pods=$(oc get pods -n "$OLS_NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    for pod in $pods; do
        local containers
        containers=$(oc get pod "$pod" -n "$OLS_NAMESPACE" -o jsonpath='{.spec.containers[*].name}' 2>/dev/null || echo "")
        for container in $containers; do
            log_info "--- Logs: ${pod}/${container} ---"
            oc logs "$pod" -c "$container" -n "$OLS_NAMESPACE" --tail=100 2>&1 || true
        done
        local init_containers
        init_containers=$(oc get pod "$pod" -n "$OLS_NAMESPACE" -o jsonpath='{.spec.initContainers[*].name}' 2>/dev/null || echo "")
        for container in $init_containers; do
            log_info "--- Init Logs: ${pod}/${container} ---"
            oc logs "$pod" -c "$container" -n "$OLS_NAMESPACE" --tail=50 2>&1 || true
        done
    done
}

wait_for_csv() {
    log_info "Waiting for ClusterServiceVersion to succeed..."
    local retries=0
    while [[ $retries -lt $OC_RETRY_COUNT ]]; do
        local phase
        phase=$(oc get clusterserviceversion -n "$OLS_NAMESPACE" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
        if [[ "$phase" == "Succeeded" ]]; then
            log_success "CSV phase: Succeeded"
            return 0
        fi
        retries=$((retries + 1))
        log_info "CSV phase: ${phase:-unknown} (attempt $retries/$OC_RETRY_COUNT)"
        sleep 10
    done
    log_error "Timed out waiting for CSV to succeed"
    dump_ols_debug
    return 1
}

wait_for_operator_controller_ready() {
    log_info "Waiting for operator controller manager to be ready..."
    local retries=0
    while [[ $retries -lt 12 ]]; do
        local ready_statuses
        ready_statuses=$(oc get pods -l control-plane=controller-manager -n "$OLS_NAMESPACE" \
            -o jsonpath='{.items[0].status.containerStatuses[*].ready}' 2>/dev/null || echo "")
        if [[ -n "$ready_statuses" ]] && ! echo "$ready_statuses" | grep -q "false"; then
            log_success "Operator controller manager is ready"
            return 0
        fi
        retries=$((retries + 1))
        sleep 5
    done
    log_error "Timed out waiting for operator controller manager"
    return 1
}

wait_for_deployment() {
    log_info "Waiting for lightspeed-app-server deployment..."
    local retries=0
    while [[ $retries -lt $OC_RETRY_COUNT ]]; do
        local name
        name=$(oc get deployment lightspeed-app-server --ignore-not-found -o name -n "$OLS_NAMESPACE" 2>/dev/null || echo "")
        if [[ -n "$name" ]]; then
            log_success "lightspeed-app-server deployment exists"
            return 0
        fi
        retries=$((retries + 1))
        sleep $OC_RETRY_DELAY
    done
    log_error "Timed out waiting for lightspeed-app-server deployment"
    dump_ols_debug
    return 1
}

wait_for_ols_pod() {
    local field_selector="${1:-}"
    log_info "Waiting for OLS pod${field_selector:+ ($field_selector)}..."
    local retries=0
    while [[ $retries -lt $OC_RETRY_COUNT ]]; do
        local pods
        if [[ -n "$field_selector" ]]; then
            pods=$(oc get pods --field-selector="$field_selector" -n "$OLS_NAMESPACE" \
                -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
        else
            pods=$(oc get pods -n "$OLS_NAMESPACE" \
                -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
        fi
        local matched=""
        for pod in $pods; do
            if [[ "$pod" == lightspeed-app-server-* ]]; then
                matched="$pod"
                break
            fi
        done
        if [[ -n "$matched" ]]; then
            log_success "OLS pod found: $matched"
            return 0
        fi
        retries=$((retries + 1))
        sleep $OC_RETRY_DELAY
    done
    log_error "Timed out waiting for OLS pod"
    dump_ols_debug
    return 1
}

wait_for_ols_containers_ready() {
    log_info "Waiting for OLS pod containers to be ready..."
    local retries=0
    while [[ $retries -lt $OC_RETRY_COUNT ]]; do
        local ready_statuses
        ready_statuses=$(oc get pods -n "$OLS_NAMESPACE" \
            -o jsonpath='{range .items[*]}{.metadata.name}{" "}{range .status.containerStatuses[*]}{.ready}{" "}{end}{"\n"}{end}' \
            2>/dev/null || echo "")
        local found=false
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local pod_name
            pod_name=$(echo "$line" | awk '{print $1}')
            if [[ "$pod_name" == lightspeed-app-server-* ]]; then
                local all_ready=true
                for status in $(echo "$line" | awk '{for(i=2;i<=NF;i++) print $i}'); do
                    if [[ "$status" != "true" ]]; then
                        all_ready=false
                        break
                    fi
                done
                if [[ "$all_ready" == "true" ]]; then
                    log_success "All containers ready in pod $pod_name"
                    return 0
                fi
                found=true
                log_info "Pod $pod_name containers not all ready yet (attempt $((retries+1))/$OC_RETRY_COUNT)"
            fi
        done <<< "$ready_statuses"
        if [[ "$found" == "false" ]]; then
            log_info "No lightspeed-app-server pod found yet (attempt $((retries+1))/$OC_RETRY_COUNT)"
        fi
        retries=$((retries + 1))
        sleep $OC_RETRY_DELAY
    done
    log_error "Timed out waiting for OLS containers to be ready"
    dump_ols_debug
    return 1
}

wait_for_ols_http() {
    local url="$1"
    log_info "Waiting for OLS HTTP readiness at ${url}..."
    local retries=0
    while [[ $retries -lt 30 ]]; do
        local code
        code=$(curl -sk "${url}/readiness" -o /dev/null -w '%{http_code}' 2>/dev/null || echo "000")
        if [[ "$code" == "200" ]]; then
            log_success "OLS is ready (HTTP 200)"
            return 0
        fi
        retries=$((retries + 1))
        log_info "OLS readiness: HTTP $code (attempt $retries/30)"
        sleep 10
    done
    log_error "Timed out waiting for OLS HTTP readiness"
    return 1
}

replace_ols_image() {
    local ols_image="$1"
    log_info "Replacing OLS image with: $ols_image"

    log_info "Waiting for operator controller manager pod to be gone..."
    local retries=0
    while [[ $retries -lt $OC_RETRY_COUNT ]]; do
        local cm_pods
        cm_pods=$(oc get pods -l control-plane=controller-manager -n "$OLS_NAMESPACE" \
            -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
        if [[ -z "$cm_pods" ]]; then
            break
        fi
        retries=$((retries + 1))
        sleep $OC_RETRY_DELAY
    done

    oc scale deployment/lightspeed-app-server --replicas=0 -n "$OLS_NAMESPACE"

    log_info "Waiting for OLS pod to be scaled down..."
    retries=0
    while [[ $retries -lt $OC_RETRY_COUNT ]]; do
        local pods
        pods=$(oc get pods -n "$OLS_NAMESPACE" \
            -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep '^lightspeed-app-server-' || echo "")
        if [[ -z "$pods" ]]; then
            break
        fi
        retries=$((retries + 1))
        sleep $OC_RETRY_DELAY
    done

    oc patch deployment/lightspeed-app-server --type=json \
        -p "[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/image\",\"value\":\"${ols_image}\"}]" \
        -n "$OLS_NAMESPACE"
    log_success "OLS image replaced"
}

update_olsconfig_configmap() {
    log_info "Updating olsconfig configmap..."

    local configmap_yaml
    configmap_yaml=$(oc get cm/olsconfig -n "$OLS_NAMESPACE" -o yaml)

    local updated_yaml
    updated_yaml=$(echo "$configmap_yaml" | python3 -c "
import sys, yaml

cm = yaml.safe_load(sys.stdin)
config_key = 'olsconfig.yaml'
if config_key not in cm.get('data', {}):
    for k in cm.get('data', {}):
        if k.endswith('.yaml'):
            config_key = k
            break

olsconfig = yaml.safe_load(cm['data'][config_key])

if 'logging_config' not in olsconfig.get('ols_config', {}):
    olsconfig.setdefault('ols_config', {})['logging_config'] = {}
olsconfig['ols_config']['logging_config']['lib_log_level'] = 'INFO'

olsconfig['ols_config'].pop('reference_content', None)

cm['data'][config_key] = yaml.dump(olsconfig)
print(yaml.dump(cm))
") || return 1

    oc delete configmap olsconfig -n "$OLS_NAMESPACE"
    echo "$updated_yaml" | oc apply -f - -n "$OLS_NAMESPACE"
    log_success "olsconfig configmap updated"
}

deploy_ols() {
    local provider="${1:?provider required}"
    local provider_key_path="${2:?provider_key_path required}"
    local bundle_image="${BUNDLE_IMAGE:-$DEFAULT_BUNDLE_IMAGE}"
    local ols_image="${OLS_IMAGE:-}"
    local config_dir="${CONFIG_DIR:-tests/config/ols_deploy}"

    log_info "=========================================="
    log_info "Deploying OLS"
    log_info "  Provider: $provider"
    log_info "  Bundle: $bundle_image"
    log_info "  OLS Image: ${ols_image:-<default from operator>}"
    log_info "=========================================="

    log_info "--- Cluster Info ---"
    oc version 2>&1 || true
    log_info "--- Node Status ---"
    oc get nodes -o wide 2>&1 || true

    install_operator_sdk || return 1

    log_info "--- operator-sdk version ---"
    operator-sdk version 2>&1 || true

    log_info "Creating namespace ${OLS_NAMESPACE}..."
    oc create namespace "$OLS_NAMESPACE" --dry-run=client -o yaml | oc apply -f - || return 1
    oc project "$OLS_NAMESPACE" || return 1

    log_info "Applying ImageDigestMirrorSet..."
    oc apply -f "${config_dir}/imagedigestmirrorset.yaml" || return 1

    log_info "Installing OLS operator from bundle..."
    operator-sdk run bundle --timeout=20m --security-context-config=restricted -n "$OLS_NAMESPACE" "$bundle_image" --verbose || {
        log_error "operator-sdk run bundle failed"
        dump_ols_debug
        return 1
    }

    wait_for_csv || return 1

    log_info "Scaling down operator controller before CRD is fully established..."
    oc scale deployment/lightspeed-operator-controller-manager --replicas=0 -n "$OLS_NAMESPACE" || return 1

    log_info "Waiting for OLSConfig CRD to be fully established..."
    oc wait --for condition=Established crd olsconfigs.ols.openshift.io --timeout=120s || return 1

    log_info "Waiting for OLSConfig API to be discoverable by the API server..."
    local api_retries=0
    while [[ $api_retries -lt 60 ]]; do
        if oc api-resources --api-group=ols.openshift.io 2>/dev/null | grep -q OLSConfig; then
            log_success "OLSConfig API is discoverable"
            break
        fi
        api_retries=$((api_retries + 1))
        log_info "OLSConfig API not yet discoverable (attempt $api_retries/60)"
        sleep 5
    done
    if [[ $api_retries -ge 60 ]]; then
        log_error "OLSConfig API never became discoverable"
        dump_ols_debug
        return 1
    fi

    log_info "Creating llmcreds secret..."
    oc delete secret llmcreds -n "$OLS_NAMESPACE" --ignore-not-found
    oc create secret generic llmcreds --from-file=apitoken="$provider_key_path" -n "$OLS_NAMESPACE" || return 1

    log_info "Applying OLSConfig for provider ${provider}..."
    local crd_file="${config_dir}/olsconfig.crd.${provider}_cluster_updates.yaml"
    if [[ ! -f "$crd_file" ]]; then
        log_error "OLSConfig CRD file not found: $crd_file"
        return 1
    fi
    oc delete olsconfig cluster --ignore-not-found --wait 2>/dev/null || true
    oc create -f "$crd_file" || return 1

    oc scale deployment/lightspeed-operator-controller-manager --replicas=1 -n "$OLS_NAMESPACE" || return 1
    wait_for_operator_controller_ready || return 1

    log_info "Waiting for operator to reconcile and create lightspeed-app-server deployment..."
    local deploy_retries=0
    local deploy_found=false
    while [[ $deploy_retries -lt 3 ]]; do
        local inner=0
        while [[ $inner -lt 24 ]]; do
            local name
            name=$(oc get deployment lightspeed-app-server --ignore-not-found -o name -n "$OLS_NAMESPACE" 2>/dev/null || echo "")
            if [[ -n "$name" ]]; then
                deploy_found=true
                break 2
            fi
            inner=$((inner + 1))
            sleep 5
        done
        deploy_retries=$((deploy_retries + 1))
        if [[ $deploy_retries -lt 3 ]]; then
            log_warning "Deployment not created after 2 minutes, restarting operator controller (attempt $((deploy_retries+1))/3)..."
            oc delete pod -l control-plane=controller-manager -n "$OLS_NAMESPACE" --force --grace-period=0 2>/dev/null || true
            wait_for_operator_controller_ready || return 1
        fi
    done
    if [[ "$deploy_found" != "true" ]]; then
        log_error "Timed out waiting for lightspeed-app-server deployment after operator restarts"
        dump_ols_debug
        return 1
    fi
    log_success "lightspeed-app-server deployment exists"

    wait_for_ols_pod || return 1

    log_info "Scaling down operator controller manager..."
    oc scale deployment/lightspeed-operator-controller-manager --replicas=0 -n "$OLS_NAMESPACE"

    if [[ -n "$ols_image" ]]; then
        replace_ols_image "$ols_image"
    fi

    oc scale deployment/lightspeed-app-server --replicas=0 -n "$OLS_NAMESPACE" || return 1
    update_olsconfig_configmap || log_warning "Failed to update configmap, continuing..."
    oc scale deployment/lightspeed-app-server --replicas=1 -n "$OLS_NAMESPACE" || return 1

    log_info "Waiting for OLS pod containers to be ready..."
    wait_for_ols_containers_ready || return 1

    log_info "Creating route..."
    oc delete route ols -n "$OLS_NAMESPACE" --ignore-not-found
    oc create -f "${config_dir}/route.yaml" -n "$OLS_NAMESPACE"

    local route_host
    route_host=$(oc get route ols -n "$OLS_NAMESPACE" -o jsonpath='{.spec.host}')
    local ols_url="https://${route_host}"

    wait_for_ols_http "$ols_url" || return 1

    log_info "Sending warmup queries to OLS until a successful response..."
    local warmup_retries=0
    local warmup_max=30
    while [[ $warmup_retries -lt $warmup_max ]]; do
        local warmup_code
        warmup_code=$(curl -sk -X POST "${ols_url}/v1/query" \
            -H "Content-Type: application/json" \
            -d '{"query": "hello"}' \
            -o /dev/null -w '%{http_code}' 2>/dev/null || echo "000")
        if [[ "$warmup_code" == "200" ]]; then
            log_success "OLS warmup query succeeded (HTTP 200)"
            break
        fi
        warmup_retries=$((warmup_retries + 1))
        log_info "OLS warmup: HTTP $warmup_code (attempt $warmup_retries/$warmup_max)"
        sleep 10
    done
    if [[ $warmup_retries -ge $warmup_max ]]; then
        log_warning "OLS warmup did not get HTTP 200 after $warmup_max attempts, proceeding anyway"
    fi

    export API_BASE_URL="$ols_url"
    log_success "=========================================="
    log_success "OLS deployed successfully"
    log_success "  API URL: $API_BASE_URL"
    log_success "=========================================="
}

cleanup_ols_operator() {
    log_info "Cleaning up OLS operator..."

    oc scale deployment/lightspeed-operator-controller-manager --replicas=1 -n "$OLS_NAMESPACE" 2>/dev/null || true
    sleep 5

    oc delete olsconfig cluster --ignore-not-found --wait 2>/dev/null || true

    if command_exists operator-sdk; then
        operator-sdk cleanup lightspeed-operator -n "$OLS_NAMESPACE" 2>/dev/null || true
    fi

    oc delete ns "$OLS_NAMESPACE" --ignore-not-found --wait 2>/dev/null || true
    oc delete imagedigestmirrorset openshift-lightspeed-prod-to-ci --ignore-not-found 2>/dev/null || true

    log_success "OLS cleanup complete"
}

# Main orchestration function for cluster-updates test suite
run_suite() {
    local suite_id="${1:-cluster_updates}"
    local use_uv="${2:-false}"
    local artifact_dir="${3:-./test_results}"

    log_info "=========================================="
    log_info "Running test suite: $suite_id"
    log_info "=========================================="

    # Setup environment
    setup_cluster_updates_env || return 1

    # Apply RBAC if needed
    apply_rbac "config/rbac-ocp-evals.yaml" || log_warning "RBAC setup failed, continuing..."

    # Install dependencies
    install_dependencies "$use_uv" || return 1

    # Run tests
    run_cluster_updates_tests "cluster_updates" "$artifact_dir" || {
        local exit_code=$?
        log_error "Test suite failed"
        collect_artifacts "." "$artifact_dir"
        return $exit_code
    }

    # Collect artifacts
    collect_artifacts "." "$artifact_dir"

    log_success "=========================================="
    log_success "Test suite completed successfully"
    log_success "=========================================="

    return 0
}

# Export functions for use in other scripts
export -f log_info log_success log_warning log_error
export -f validate_env command_exists validate_cluster_connection
export -f get_openai_key_from_cluster create_api_token get_api_endpoint
export -f setup_cluster_updates_env install_dependencies
export -f run_cluster_updates_tests collect_artifacts
export -f apply_rbac cleanup_rbac run_suite
export -f install_operator_sdk deploy_ols cleanup_ols_operator
export -f dump_ols_debug wait_for_csv wait_for_operator_controller_ready
export -f wait_for_deployment wait_for_ols_pod wait_for_ols_containers_ready wait_for_ols_http
export -f replace_ols_image update_olsconfig_configmap
