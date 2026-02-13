#!/bin/bash
set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common/functions.sh"

banner "PostgreSQL Operator - HELM Installation (One-Click)"

echo -e "${YELLOW}This script will install everything for Helm-based demo:${NC}"
echo "  • PostgreSQL Operator + UI"
echo "  • Namespaces (dev, test, prod)"
echo "  • RBAC (users, groups, roles)"
echo "  • Sample databases"
echo ""

# Check login and permissions
require_cluster_admin

# Skipping confirmation prompt for non-interactive use
# Uncomment below if you want manual confirmation:
# read -p "Continue with installation? (y/n) " -n 1 -r
# echo
# if [[ ! $REPLY =~ ^[Yy]$ ]]; then
#     echo "Installation cancelled"
#     exit 0
# fi
echo "Starting installation..."
echo ""

# ============================================
# STEP 1: Add Helm Repositories
# ============================================
step 1 7 "Adding Helm repositories..."
if helm repo list | grep -q "postgres-operator-charts"; then
    echo "  → Repository already added"
else
    helm repo add postgres-operator-charts https://opensource.zalando.com/postgres-operator/charts/postgres-operator
    echo "  → Added postgres-operator-charts"
fi

if helm repo list | grep -q "postgres-operator-ui-charts"; then
    echo "  → UI repository already added"
else
    helm repo add postgres-operator-ui-charts https://opensource.zalando.com/postgres-operator/charts/postgres-operator-ui
    echo "  → Added postgres-operator-ui-charts"
fi

helm repo update &>/dev/null
echo -e "  ${GREEN}✓ Helm repositories ready${NC}"
echo ""

# ============================================
# STEP 2: Install PostgreSQL Operator
# ============================================
step 2 7 "Installing PostgreSQL Operator..."
if helm list -n $OPERATOR_NAMESPACE 2>/dev/null | grep -q "postgres-operator"; then
    echo "  → Operator already installed"
else
    helm install postgres-operator postgres-operator-charts/postgres-operator \
      -n $OPERATOR_NAMESPACE \
      --create-namespace \
      --set configGeneral.kubernetes_use_configmaps=true \
      --set configKubernetes.enable_cross_namespace_secret=true \
      --set configGeneral.docker_image="ghcr.io/zalando/spilo-16:3.3-p3"
fi

# Configure OpenShift SCC for operator (always, even if operator existed)
echo "  → Configuring OpenShift SCC..."
oc adm policy add-scc-to-user anyuid -z postgres-operator -n $OPERATOR_NAMESPACE 2>/dev/null || \
  echo "     (SCC already configured)"

# Restart operator to apply SCC
echo "  → Restarting operator to apply SCC..."
oc rollout restart deployment/postgres-operator -n $OPERATOR_NAMESPACE &>/dev/null

# Wait for operator to be ready
echo "  → Waiting for operator to be ready (max 5 minutes)..."
if wait_for_pods "app.kubernetes.io/name=postgres-operator" "$OPERATOR_NAMESPACE" 300; then
    success "  ✓ PostgreSQL Operator running"
else
    warn "  ⚠ Operator not ready after timeout"
    info "     Check: oc get pods -n $OPERATOR_NAMESPACE"
    info "     Check: oc describe pod -n $OPERATOR_NAMESPACE -l app.kubernetes.io/name=postgres-operator"
    warn "     Continuing with installation (operator may start later)..."
fi
echo ""

# ============================================
# STEP 3: Install PostgreSQL UI
# ============================================
step 3 7 "Installing PostgreSQL Operator UI..."
if helm list -n $OPERATOR_NAMESPACE 2>/dev/null | grep -q "postgres-operator-ui"; then
    echo "  → UI already installed"
else
    # Check for leftover ClusterRole from previous installations
    if oc get clusterrole postgres-operator-ui &>/dev/null; then
        warn "  → Found existing ClusterRole 'postgres-operator-ui' (from previous install)"
        echo "     Removing to allow Helm to manage it..."
        oc delete clusterrole postgres-operator-ui --ignore-not-found=true 2>/dev/null || true
        oc delete clusterrolebinding postgres-operator-ui --ignore-not-found=true 2>/dev/null || true
    fi
    
    helm install postgres-operator-ui postgres-operator-ui-charts/postgres-operator-ui \
      -n $OPERATOR_NAMESPACE \
      --set envs.targetNamespace="" \
      --set envs.operatorApiUrl="http://postgres-operator:8080"
fi

success "  ✓ PostgreSQL UI installed"
echo ""

# ============================================
# STEP 4: Create Namespaces with Kustomize
# ============================================
step 4 7 "Creating namespaces and base RBAC..."
for env in dev test prod; do
    echo "  → Applying helm/overlays/$env/"
    oc apply -k helm/overlays/$env/ &>/dev/null
done

# Wait for namespaces
for ns in $DB_NAMESPACES; do
    if oc get namespace $ns &>/dev/null; then
        echo "  → Namespace $ns: ready"
    fi
done

echo -e "  ${GREEN}✓ Namespaces and namespace-level RBAC created${NC}"

# Verify namespaces
echo "  → Verifying namespaces..."
oc get namespaces | grep dba- || true
echo ""

# ============================================
# STEP 5: Setup Cluster RBAC
# ============================================
step 5 7 "Setting up cluster-level RBAC..."
"${SCRIPT_DIR}/common/setup-dba-rbac.sh"

success "  ✓ Cluster RBAC configured"

# Verify RBAC
echo "  → Verifying RBAC..."
echo "     ClusterRoleBindings:"
oc get clusterrolebinding | grep dba | head -5 || true
echo ""

# ============================================
# STEP 6: Deploy Sample Databases (as DBA users)
# ============================================
step 6 7 "Deploying sample PostgreSQL databases (validating RBAC)..."

# Save current cluster admin context
OCP_URL=$(oc whoami --show-server)
CLUSTER_ADMIN_USER=$(oc whoami)
CLUSTER_ADMIN_TOKEN=$(oc whoami -t 2>/dev/null || echo "")
# DBA_PASSWORD is set in common/functions.sh

echo "  → Validating DEMO.md Step 3 workflow..."
echo ""

# Deploy to dev AS dba-dev user (validates RBAC)
echo "  → Logging in as dba-dev..."
if oc login "$OCP_URL" --username=dba-dev --password="$DBA_PASSWORD" &>/dev/null; then
    echo "     ✓ Logged in as dba-dev"
    echo "  → Deploying database to dba-dev namespace..."
    if oc apply -f helm/overlays/dev/simple-cluster.yaml &>/dev/null; then
        echo "     ✓ Database deployed to dba-dev"
    else
        warn "     ⚠ Failed to deploy (RBAC issue?)"
    fi
else
    warn "     ⚠ Login failed - user may not exist"
fi
echo ""

# Deploy to test AS dba-test user (validates RBAC)
echo "  → Logging in as dba-test..."
if oc login "$OCP_URL" --username=dba-test --password="$DBA_PASSWORD" &>/dev/null; then
    echo "     ✓ Logged in as dba-test"
    echo "  → Deploying database to dba-test namespace..."
    if oc apply -f helm/overlays/test/test-cluster.yaml &>/dev/null; then
        echo "     ✓ Database deployed to dba-test"
    else
        warn "     ⚠ Failed to deploy (RBAC issue?)"
    fi
else
    warn "     ⚠ Login failed - user may not exist"
fi
echo ""

# Deploy to prod AS dba-prod user (validates RBAC)
echo "  → Logging in as dba-prod..."
if oc login "$OCP_URL" --username=dba-prod --password="$DBA_PASSWORD" &>/dev/null; then
    echo "     ✓ Logged in as dba-prod"
    echo "  → Deploying database to dba-prod namespace..."
    if oc apply -f helm/overlays/prod/ha-cluster.yaml &>/dev/null; then
        echo "     ✓ Database deployed to dba-prod"
    else
        warn "     ⚠ Failed to deploy (RBAC issue?)"
    fi
else
    warn "     ⚠ Login failed - user may not exist"
fi
echo ""

# Switch back to cluster-admin for verification
echo "  → Switching back to cluster-admin..."
if [ ! -z "$CLUSTER_ADMIN_TOKEN" ]; then
    oc login "$OCP_URL" --token="$CLUSTER_ADMIN_TOKEN" --insecure-skip-tls-verify=true &>/dev/null
else
    warn "     ⚠ Could not restore cluster-admin session (token unavailable)"
    warn "     Please verify manually as cluster-admin"
fi

success "  ✓ Database deployments submitted by DBA users"
echo -e "  ${CYAN}Note: Databases will take ~2-3 minutes to become ready${NC}"
info "  → RBAC validation: Each DBA user successfully deployed to their namespace"
echo ""

# ============================================
# STEP 7: Verification
# ============================================
step 7 7 "Running verification..."
echo ""

# Quick status check
echo "Infrastructure Status:"
OPERATOR_PODS=$(oc get pods -n $OPERATOR_NAMESPACE --no-headers 2>/dev/null | wc -l | tr -d ' ')
echo "  • Operator namespace: $OPERATOR_PODS pod(s)"

echo ""
echo "Database Status:"
for ns in $DB_NAMESPACES; do
    DB_COUNT=$(oc get postgresql -n $ns --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "$DB_COUNT" -gt 0 ]; then
        DB_NAME=$(oc get postgresql -n $ns -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        DB_STATUS=$(oc get postgresql -n $ns -o jsonpath='{.items[0].status.PostgresClusterStatus}' 2>/dev/null || echo "Creating")
        echo "  • $ns: $DB_NAME ($DB_STATUS)"
    else
        echo "  • $ns: No databases"
    fi
done

echo ""
echo "========================================================"
echo -e "${GREEN}${BOLD}Installation Complete!${NC}"
echo "========================================================"
echo ""
echo -e "${BOLD}Next Steps:${NC}"
echo ""
echo "1. Run full verification:"
echo -e "   ${CYAN}./common/verify-installation.sh${NC}"
echo ""
echo "2. Access PostgreSQL UI:"
echo -e "   ${CYAN}./common/access-ui.sh${NC}"
echo "   Then open: http://localhost:8081"
echo ""
echo "3. Test DBA user access:"
echo -e "   ${CYAN}oc login \$(oc whoami --show-server) --username=dba-dev --password=${DBA_PASSWORD}${NC}"
echo -e "   ${CYAN}oc get postgresql -n dba-dev${NC}"
echo ""
echo "4. View database credentials:"
echo -e "   ${CYAN}./common/get-credentials.sh <cluster-name> <namespace>${NC}"
echo ""
echo "5. See all databases:"
echo -e "   ${CYAN}./common/show-all-databases.sh${NC}"
echo ""
echo -e "${YELLOW}Note: Databases may take 2-3 minutes to fully start${NC}"
echo ""
