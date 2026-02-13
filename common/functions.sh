#!/bin/bash
# Shared functions for PostgreSQL Operator scripts

# ==============================================
# COLOR DEFINITIONS
# ==============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Simple ASCII symbols for verification scripts
OK="${GREEN}[OK]${NC}"
FAIL="${RED}[FAIL]${NC}"
WARN="${YELLOW}[WARN]${NC}"
INFO="${CYAN}[INFO]${NC}"

# ==============================================
# CONFIGURATION
# ==============================================
DB_NAMESPACES="${DB_NAMESPACES:-dba-dev dba-test dba-prod}"
OPERATOR_NAMESPACE="${OPERATOR_NAMESPACE:-postgres-operator}"
ALL_NAMESPACES="$OPERATOR_NAMESPACE $DB_NAMESPACES"
DBA_PASSWORD="${DBA_PASSWORD:-Redhat123p@ssword}"

# ArgoCD application names managed by this project
ARGOCD_INFRA_APPS="postgres-operator postgres-ui rbac-cluster"
ARGOCD_META_APPS="team-namespaces cluster-config"

# CRDs installed by the operator
OPERATOR_CRDS="postgresqls.acid.zalan.do operatorconfigurations.acid.zalan.do postgresteams.acid.zalan.do"

# Cluster RBAC resources
CLUSTER_ROLES="postgres-user-role postgres-pod postgres-operator postgres-monitor dba-namespace-manager"
CLUSTER_ROLE_BINDINGS="postgres-operator postgres-operator-ui dba-master-postgres-user dba-master-namespace-manager secops-postgres-monitoring secops-postgres-read dba-users-postgres-read dba-users-view"

# ==============================================
# LOGGING FUNCTIONS
# ==============================================

# Print error message and exit
# Usage: die "Error message"
die() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

# Print warning message
# Usage: warn "Warning message"
warn() {
    echo -e "${YELLOW}Warning: $1${NC}" >&2
}

# Print info message
# Usage: info "Info message"
info() {
    echo -e "${CYAN}$1${NC}"
}

# Print success message
# Usage: success "Success message"
success() {
    echo -e "${GREEN}$1${NC}"
}

# Print section header
# Usage: section_header "Section Title"
section_header() {
    echo ""
    echo -e "${CYAN}$1${NC}"
}

# Print step with number
# Usage: step 1 5 "Installing operator"
step() {
    local current=$1
    local total=$2
    local message=$3
    echo -e "${CYAN}[$current/$total] $message${NC}"
}

# ==============================================
# OPENSHIFT CONNECTION CHECKS
# ==============================================

# Check if logged into OpenShift
# Usage: check_oc_login
check_oc_login() {
    if ! oc whoami &>/dev/null; then
        die "Not logged in to OpenShift. Run 'oc login' first."
    fi
}

# Get current OpenShift user
# Usage: CURRENT_USER=$(get_current_user)
get_current_user() {
    oc whoami 2>/dev/null || echo ""
}

# Check if user has cluster-admin privileges
# Usage: if has_cluster_admin; then ...
has_cluster_admin() {
    oc auth can-i '*' '*' &>/dev/null
}

# Check if user can delete namespaces (cleanup requirement)
# Usage: if can_delete_namespaces; then ...
can_delete_namespaces() {
    oc auth can-i delete namespaces --all-namespaces &>/dev/null
}

# Require cluster-admin or exit
# Usage: require_cluster_admin
require_cluster_admin() {
    check_oc_login
    
    local current_user
    current_user=$(get_current_user)
    echo -e "Logged in as: ${BOLD}${current_user}${NC}"
    echo ""
    
    if ! has_cluster_admin; then
        die "This script requires cluster-admin privileges"
    fi
}

# ==============================================
# RESOURCE WAIT FUNCTIONS
# ==============================================

# Wait for namespace to exist
# Usage: wait_for_namespace "my-namespace" 300
wait_for_namespace() {
    local namespace=$1
    local timeout=${2:-300}
    
    echo -n "  → Waiting for namespace $namespace..."
    
    local elapsed=0
    local interval=5
    
    while [ $elapsed -lt $timeout ]; do
        if oc wait --for=jsonpath='{.status.phase}'=Active namespace/"$namespace" --timeout=1s &>/dev/null; then
            echo -e " ${GREEN}ready${NC} (${elapsed}s)"
            return 0
        fi
        
        # Show progress every 10 seconds for long waits
        if [ $((elapsed % 10)) -eq 0 ] && [ $elapsed -gt 0 ]; then
            echo -n " [${elapsed}s]"
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    echo -e " ${RED}timeout${NC} (${elapsed}s)"
    return 1
}

# Wait for deployment to be ready
# Usage: wait_for_deployment "my-deploy" "my-namespace" 600
wait_for_deployment() {
    local deployment=$1
    local namespace=$2
    local timeout=${3:-600}
    
    echo -n "  → Waiting for deployment $deployment..."
    
    local elapsed=0
    local interval=5
    
    while [ $elapsed -lt $timeout ]; do
        if oc wait --for=condition=available deployment/"$deployment" -n "$namespace" --timeout=1s &>/dev/null; then
            echo -e " ${GREEN}ready${NC} (${elapsed}s)"
            return 0
        fi
        
        # Show progress every 15 seconds for long waits
        if [ $((elapsed % 15)) -eq 0 ] && [ $elapsed -gt 0 ]; then
            local ready
            ready=$(oc get deployment "$deployment" -n "$namespace" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
            local desired
            desired=$(oc get deployment "$deployment" -n "$namespace" -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0")
            echo -n " [${elapsed}s: ${ready:-0}/${desired:-0} ready]"
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    echo -e " ${RED}timeout${NC} (${elapsed}s)"
    return 1
}

# Wait for pods with label selector
# Usage: wait_for_pods "app=myapp" "my-namespace" 300
wait_for_pods() {
    local label=$1
    local namespace=$2
    local timeout=${3:-300}
    
    echo -n "  → Waiting for pods with label $label..."
    
    local elapsed=0
    local interval=5
    
    while [ $elapsed -lt $timeout ]; do
        if oc wait --for=condition=ready pod -l "$label" -n "$namespace" --timeout=1s &>/dev/null 2>&1; then
            echo -e " ${GREEN}ready${NC} (${elapsed}s)"
            return 0
        fi
        
        # Show progress every 15 seconds for long waits
        if [ $((elapsed % 15)) -eq 0 ] && [ $elapsed -gt 0 ]; then
            local pod_count
            pod_count=$(oc get pods -l "$label" -n "$namespace" --no-headers 2>/dev/null | wc -l | tr -d ' ')
            local ready_count
            ready_count=$(oc get pods -l "$label" -n "$namespace" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
            if [ "$pod_count" -gt 0 ]; then
                echo -n " [${elapsed}s: ${ready_count}/${pod_count} running]"
            else
                echo -n " [${elapsed}s: no pods yet]"
            fi
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    echo -e " ${RED}timeout${NC} (${elapsed}s)"
    return 1
}

# Wait for ArgoCD application to sync
# Usage: wait_for_argocd_app "my-app" "openshift-gitops" 300
wait_for_argocd_app() {
    local app=$1
    local namespace=${2:-openshift-gitops}
    local timeout=${3:-300}
    
    echo -n "  → Waiting for ArgoCD app $app to sync..."
    
    local elapsed=0
    local interval=5
    
    while [ $elapsed -lt $timeout ]; do
        local sync_status
        sync_status=$(oc get application "$app" -n "$namespace" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "")
        local health_status
        health_status=$(oc get application "$app" -n "$namespace" -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")
        
        if [ "$sync_status" = "Synced" ] && [ "$health_status" = "Healthy" ]; then
            echo -e " ${GREEN}ready${NC}"
            return 0
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    echo -e " ${RED}timeout${NC}"
    return 1
}

# ==============================================
# RESOURCE CHECK FUNCTIONS
# ==============================================

# Check if namespace exists
# Usage: if namespace_exists "my-namespace"; then ...
namespace_exists() {
    local namespace=$1
    oc get namespace "$namespace" &>/dev/null
}

# Check if resource exists
# Usage: if resource_exists "deployment" "my-deploy" "my-namespace"; then ...
resource_exists() {
    local type=$1
    local name=$2
    local namespace=${3:-""}
    
    if [ -z "$namespace" ]; then
        oc get "$type" "$name" &>/dev/null
    else
        oc get "$type" "$name" -n "$namespace" &>/dev/null
    fi
}

# Get deployment status
# Usage: get_deployment_status "my-deploy" "my-namespace"
# Returns: "ready_count/desired_count"
get_deployment_status() {
    local deployment=$1
    local namespace=$2
    
    local ready
    ready=$(oc get deployment "$deployment" -n "$namespace" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    local desired
    desired=$(oc get deployment "$deployment" -n "$namespace" -o jsonpath='{.status.replicas}' 2>/dev/null)
    
    # Default to 0 if empty
    ready=${ready:-0}
    desired=${desired:-0}
    
    echo "$ready/$desired"
}

# Check if deployment is ready
# Usage: if is_deployment_ready "my-deploy" "my-namespace"; then ...
is_deployment_ready() {
    local deployment=$1
    local namespace=$2
    
    local status
    status=$(get_deployment_status "$deployment" "$namespace")
    local ready
    ready=$(echo "$status" | cut -d'/' -f1)
    local desired
    desired=$(echo "$status" | cut -d'/' -f2)
    
    [ "$ready" -gt 0 ] && [ "$ready" -eq "$desired" ]
}

# ==============================================
# CLEANUP FUNCTIONS
# ==============================================

# Remove finalizers from resource
# Usage: remove_finalizers "postgresql" "my-db" "my-namespace"
# Usage: remove_finalizers "crd" "postgresqls.acid.zalan.do"  (cluster-scoped)
remove_finalizers() {
    local type=$1
    local name=$2
    local namespace=${3:-""}
    
    if [ -n "$namespace" ]; then
        oc patch "$type" "$name" -n "$namespace" \
            --type merge -p '{"metadata":{"finalizers":[]}}' \
            &>/dev/null || true
    else
        oc patch "$type" "$name" \
            --type merge -p '{"metadata":{"finalizers":[]}}' \
            &>/dev/null || true
    fi
}

# Remove finalizers from all resources of type in a namespace
# Usage: remove_all_finalizers "postgresql" "my-namespace"
remove_all_finalizers() {
    local type=$1
    local namespace=$2
    
    local resources
    resources=$(oc get "$type" -n "$namespace" -o name 2>/dev/null || echo "")
    
    if [ -n "$resources" ]; then
        echo "$resources" | while read -r resource; do
            oc patch "$resource" -n "$namespace" \
                --type merge -p '{"metadata":{"finalizers":[]}}' \
                &>/dev/null || true
        done
    fi
}

# ==============================================
# PRINT HELPERS
# ==============================================

# Print a separator line
# Usage: separator
separator() {
    echo "========================================================"
}

# Print banner with title
# Usage: banner "My Script Title"
banner() {
    separator
    echo "$1"
    separator
    echo ""
}
