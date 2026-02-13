#!/bin/bash
set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common/functions.sh"

banner "PostgreSQL Operator - GitOps Installation (One-Click)"

echo -e "${YELLOW}This script will install everything for GitOps-based demo:${NC}"
echo "  • OpenShift GitOps (ArgoCD)"
echo "  • ArgoCD OAuth configuration"
echo "  • PostgreSQL Operator + UI (via ArgoCD)"
echo "  • Namespaces (dba-dev, dba-test, dba-prod)"
echo "  • RBAC (users, groups, roles)"
echo "  • Sample databases + frontend web app (via ArgoCD)"
echo "  • GitHub webhook (instant sync)"
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
# STEP 1: Install OpenShift GitOps
# ============================================
step 1 7 "Installing OpenShift GitOps (ArgoCD)..."
if oc get namespace openshift-gitops &>/dev/null; then
    echo "  → OpenShift GitOps already installed"
else
    "${SCRIPT_DIR}/common/install-openshift-gitops.sh"
fi

# Wait for ArgoCD to be fully ready
echo "  → Waiting for ArgoCD server to be ready..."
wait_for_pods "app.kubernetes.io/name=openshift-gitops-server" "openshift-gitops" 300

if is_deployment_ready "openshift-gitops-server" "openshift-gitops"; then
    success "  ✓ OpenShift GitOps running"
else
    warn "  ⚠ ArgoCD not ready yet (continuing anyway)"
fi
echo ""

# ============================================
# STEP 2: Configure ArgoCD OAuth
# ============================================
step 2 7 "Configuring ArgoCD OAuth (OpenShift SSO)..."
"${SCRIPT_DIR}/common/configure-argocd-oauth.sh"

# Get ArgoCD URL
ARGOCD_ROUTE=$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}' 2>/dev/null || echo "pending")
echo "  → ArgoCD URL: https://$ARGOCD_ROUTE"
success "  ✓ OAuth configured"
echo ""

# ============================================
# STEP 3: Setup Group (Prerequisites)
# ============================================
step 3 7 "Setting up dba-users group..."
if oc get group dba-users &>/dev/null; then
    echo "  → Group already exists"
else
    echo "  → Creating dba-users group..."
    oc adm groups new dba-users 2>/dev/null || echo "  → Group exists"
fi

echo "  → Registering users with group..."
oc adm groups add-users dba-users dba dba-dev dba-test dba-prod 2>/dev/null || true

# Verify group membership
GROUP_USERS=$(oc get group dba-users -o jsonpath='{.users}' 2>/dev/null || echo "[]")
echo "  → Group members: $GROUP_USERS"
success "  ✓ Group configured"
echo ""

# ============================================
# STEP 4: Deploy Infrastructure (App of Apps)
# ============================================
step 4 7 "Deploying infrastructure via GitOps..."

echo "  → Creating ArgoCD AppProjects (prerequisites)..."
oc apply -f gitops/cluster-config/argocd-projects.yaml &>/dev/null
echo "  → AppProjects created"

echo "  → Applying app-of-apps.yaml..."
oc apply -f gitops/cluster-config/app-of-apps.yaml &>/dev/null

echo "  → Waiting for ArgoCD Applications to be created..."
sleep 5

# Wait for cluster-config application to be healthy
echo "  → Waiting for cluster-config application..."
wait_for_argocd_app "cluster-config" "openshift-gitops" 300 || warn "  ⚠ cluster-config not fully healthy yet"

# CRITICAL: Wait for rbac-cluster to sync (contains SCC for operator)
echo "  → Waiting for rbac-cluster to apply SCC permissions..."
wait_for_argocd_app "rbac-cluster" "openshift-gitops" 120 || warn "  ⚠ rbac-cluster not synced yet"

# Verify SCC RoleBinding exists
if oc get rolebinding postgres-operator-anyuid -n postgres-operator &>/dev/null; then
    echo "  → SCC RoleBinding confirmed"
else
    echo "  → SCC RoleBinding not found, applying manually..."
    oc apply -f gitops/cluster-config/rbac-cluster/operator-scc-rolebinding.yaml &>/dev/null || true
fi

success "  ✓ Infrastructure applications deployed"
echo ""

# ============================================
# STEP 5: Wait for PostgreSQL Operator
# ============================================
step 5 7 "Waiting for PostgreSQL Operator to be ready..."

# Wait for namespace to be created by ArgoCD
if ! wait_for_namespace "$OPERATOR_NAMESPACE" 180; then
    die "Timeout waiting for namespace $OPERATOR_NAMESPACE. Check: oc get application -n openshift-gitops"
fi

# Wait for operator deployment
echo "  → Waiting for operator deployment (max 10 minutes)..."
if wait_for_deployment "postgres-operator" "$OPERATOR_NAMESPACE" 600; then
    : # Success message already printed
else
    warn "  ⚠ Operator still starting"
    info "     Check ArgoCD applications: oc get application -n openshift-gitops"
    info "     Check operator pods: oc get pods -n $OPERATOR_NAMESPACE"
fi

# Wait for database namespaces
echo "  → Waiting for database namespaces..."
for ns in $DB_NAMESPACES; do
    if wait_for_namespace "$ns" 180; then
        : # Success message already printed
    else
        warn "    • $ns: timeout"
    fi
done

success "  ✓ Namespace check complete"
echo ""

# ============================================
# STEP 6: Deploy Database Applications
# ============================================
step 6 7 "Deploying database applications..."

# Check if team applications are already deployed
if oc get application dev-postgres -n dba-dev &>/dev/null; then
    echo "  → Database applications already deployed"
else
    echo "  → Deploying dev-postgres..."
    oc apply -f gitops/cluster-config/team-dev-app.yaml &>/dev/null
    
    echo "  → Deploying test-postgres..."
    oc apply -f gitops/cluster-config/team-test-app.yaml &>/dev/null
    
    echo "  → Deploying prod-postgres..."
    oc apply -f gitops/cluster-config/team-prod-app.yaml &>/dev/null
fi

echo "  → ArgoCD will sync databases and frontend app automatically"
echo -e "  ${GREEN}✓ Database and frontend applications submitted to ArgoCD${NC}"
echo ""

# ============================================
# STEP 7: Setup GitHub Webhook
# ============================================
step 7 7 "Setting up GitHub webhook for instant sync..."

ARGOCD_ROUTE=$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}' 2>/dev/null)
WEBHOOK_URL="https://$ARGOCD_ROUTE/api/webhook"

if ! command -v gh &>/dev/null; then
    warn "  ⚠ GitHub CLI (gh) not installed - skipping webhook"
    info "     Install from: https://cli.github.com"
    info "     Then run: ./common/setup-github-webhook.sh"
elif ! gh auth status &>/dev/null 2>&1; then
    warn "  ⚠ GitHub CLI not authenticated - skipping webhook"
    info "     Run: gh auth login"
    info "     Then run: ./common/setup-github-webhook.sh"
else
    # Get repo from git remote
    if git remote get-url origin &>/dev/null; then
        GIT_REMOTE=$(git remote get-url origin)
        REPO=$(echo "$GIT_REMOTE" | sed -E 's|.*github.com[:/]||' | sed 's|\.git$||')
        echo "  → Repository: $REPO"
        echo "  → Webhook URL: $WEBHOOK_URL"

        # Check if webhook already exists
        EXISTING_WEBHOOK=$(gh api "repos/$REPO/hooks" 2>/dev/null | jq -r ".[] | select(.config.url == \"$WEBHOOK_URL\") | .id" || echo "")

        if [ -n "$EXISTING_WEBHOOK" ]; then
            echo "  → Webhook already exists (ID: $EXISTING_WEBHOOK)"
            success "  ✓ Webhook configured"
        else
            echo "  → Creating webhook..."
            RESULT=$(gh api "repos/$REPO/hooks" \
                -X POST \
                -f name=web \
                -f "config[url]=$WEBHOOK_URL" \
                -f "config[content_type]=json" \
                -f "config[insecure_ssl]=0" \
                -f "events[]=push" \
                -F active=true 2>&1)

            WEBHOOK_ID=$(echo "$RESULT" | jq -r '.id' 2>/dev/null)

            if [ -n "$WEBHOOK_ID" ] && [ "$WEBHOOK_ID" != "null" ]; then
                success "  ✓ Webhook created (ID: $WEBHOOK_ID)"
            else
                warn "  ⚠ Failed to create webhook"
                info "     Run manually: ./common/setup-github-webhook.sh"
            fi
        fi
    else
        warn "  ⚠ No git remote found - skipping webhook"
        info "     Run manually: ./common/setup-github-webhook.sh"
    fi
fi
echo ""

# ============================================
# Quick Status Check
# ============================================
echo "========================================================"
echo "Checking ArgoCD Application Status..."
echo "========================================================"
echo ""

# List all applications
APPS=$(oc get application -n openshift-gitops --no-headers 2>/dev/null | awk '{print $1}')
for app in $APPS; do
    HEALTH=$(oc get application $app -n openshift-gitops -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
    SYNC=$(oc get application $app -n openshift-gitops -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    
    # Color code status
    if [ "$HEALTH" = "Healthy" ]; then
        HEALTH_COLOR="${GREEN}"
    elif [ "$HEALTH" = "Progressing" ]; then
        HEALTH_COLOR="${YELLOW}"
    else
        HEALTH_COLOR="${CYAN}"
    fi
    
    if [ "$SYNC" = "Synced" ]; then
        SYNC_COLOR="${GREEN}"
    else
        SYNC_COLOR="${YELLOW}"
    fi
    
    echo -e "  • ${BOLD}$app${NC}: Health=${HEALTH_COLOR}$HEALTH${NC}, Sync=${SYNC_COLOR}$SYNC${NC}"
done

echo ""
echo "Database Status:"
for ns in $DB_NAMESPACES; do
    DB_COUNT=$(oc get postgresql -n $ns --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "$DB_COUNT" -gt 0 ]; then
        DB_NAME=$(oc get postgresql -n $ns -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        DB_STATUS=$(oc get postgresql -n $ns -o jsonpath='{.items[0].status.PostgresClusterStatus}' 2>/dev/null || echo "Creating")
        echo "  • $ns: $DB_NAME ($DB_STATUS)"
    else
        echo "  • $ns: No databases yet (ArgoCD syncing...)"
    fi
done

echo ""
echo "Frontend Status:"
for ns in $DB_NAMESPACES; do
    DEPLOY_STATUS=$(oc get deployment frontend -n $ns -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    ROUTE=$(oc get route frontend -n $ns -o jsonpath='{.spec.host}' 2>/dev/null || echo "pending")
    echo "  • $ns: ${DEPLOY_STATUS:-0} replica(s) ready, route: $ROUTE"
done

echo ""
echo "========================================================"
echo -e "${GREEN}${BOLD}GitOps Installation Complete!${NC}"
echo "========================================================"
echo ""
echo -e "${BOLD}ArgoCD Access:${NC}"
ARGOCD_ROUTE=$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}' 2>/dev/null)
echo -e "  URL: ${CYAN}https://$ARGOCD_ROUTE${NC}"
echo "  Login: Use OpenShift credentials (OAuth enabled)"
echo ""
echo -e "${BOLD}Next Steps:${NC}"
echo ""
echo "1. Check ArgoCD Applications:"
echo -e "   ${CYAN}oc get application -n openshift-gitops${NC}"
echo ""
echo "2. Watch sync progress:"
echo -e "   ${CYAN}watch oc get application -n openshift-gitops${NC}"
echo ""
echo "3. Run full verification (after apps are synced):"
echo -e "   ${CYAN}./common/verify-installation.sh${NC}"
echo ""
echo "4. Access PostgreSQL UI:"
echo -e "   ${CYAN}./common/access-ui.sh${NC}"
echo "   Then open: http://localhost:8081"
echo ""
echo "5. Test DBA user access:"
echo -e "   ${CYAN}oc login \$(oc whoami --show-server) --username=dba-dev --password=${DBA_PASSWORD}${NC}"
echo -e "   ${CYAN}oc get postgresql -n dba-dev${NC}"
echo ""
echo -e "${YELLOW}Note: GitOps applications sync automatically.${NC}"
echo -e "${YELLOW}It may take 5-10 minutes for everything to be fully ready.${NC}"
echo ""
echo "Monitor progress in ArgoCD UI: https://$ARGOCD_ROUTE"
echo ""
echo "Git Sync Configuration:"
echo "  • Webhook URL: https://$ARGOCD_ROUTE/api/webhook"
echo "  • Polling fallback: 30 seconds"
echo ""
