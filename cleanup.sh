#!/bin/bash
set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common/functions.sh"

# Parse command line arguments
FORCE_FINALIZERS=false
if [[ "$1" == "--force" ]]; then
    FORCE_FINALIZERS=true
fi

banner "PostgreSQL Operator Cleanup"

echo -e "${YELLOW}WARNING: This will delete ALL PostgreSQL resources!${NC}"
if [ "$FORCE_FINALIZERS" = true ]; then
    echo -e "${RED}FORCE MODE: Will aggressively remove finalizers${NC}"
else
    echo -e "${CYAN}SAFE MODE: Will wait for natural cleanup (use --force for aggressive removal)${NC}"
fi
echo ""

# Check login and permissions
check_oc_login
CURRENT_USER=$(get_current_user)
echo -e "Logged in as: ${BOLD}${CURRENT_USER}${NC}"

echo -n "Checking permissions... "
if ! can_delete_namespaces; then
    echo -e "${RED}FAILED${NC}"
    echo ""
    die "Insufficient permissions. This script requires cluster-admin privileges to delete namespaces, ClusterRoles, CRDs, etc."
fi
echo -e "${GREEN}OK${NC}"
echo ""

echo "Starting cleanup in correct dependency order..."
if [ "$FORCE_FINALIZERS" = true ]; then
    echo "Force mode: Finalizers will be removed immediately if resources are stuck."
else
    echo "Safe mode: Resources will be allowed time to clean up naturally."
    echo "Tip: Use --force flag if cleanup gets stuck."
fi
echo ""

# ============================================
# Step 1: Delete ArgoCD applications
# ============================================
step 1 7 "Deleting ArgoCD applications..."

# First, delete applications in team namespaces (they can block namespace deletion)
echo "  → Checking for applications in team namespaces..."
for ns in $DB_NAMESPACES; do
    if namespace_exists $ns; then
        TEAM_APP_COUNT=$(oc get application -n $ns --no-headers 2>/dev/null | wc -l | tr -d ' ')
        if [ "$TEAM_APP_COUNT" -gt 0 ]; then
            echo "     • Found $TEAM_APP_COUNT application(s) in $ns"
            oc get application -n $ns -o json 2>/dev/null | \
                jq -r '.items[] | .metadata.name' | \
                while read name; do
                    echo "       → Removing finalizer from $ns/$name"
                    remove_finalizers "application" "$name" "$ns"
                done
            oc delete application --all -n $ns --ignore-not-found=true 2>/dev/null || true
        fi
    fi
done

# Then delete applications in openshift-gitops
if namespace_exists openshift-gitops; then
    APP_COUNT=$(oc get application -n openshift-gitops --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "$APP_COUNT" -gt 0 ]; then
        echo "  → Found $APP_COUNT application(s) in openshift-gitops:"
        oc get application -n openshift-gitops -o json 2>/dev/null | \
            jq -r '.items[] | "\(.metadata.name) \(.status.sync.status // "Unknown") \(.status.health.status // "Unknown")"' | \
            while read name sync health; do
                echo "     • $name (Sync: $sync, Health: $health)"
            done
        
        # Remove finalizers from ALL applications first (prevents blocking)
        echo "  → Removing finalizers from all applications..."
        oc get application -n openshift-gitops -o json 2>/dev/null | \
            jq -r '.items[] | .metadata.name' | \
            while read name; do
                remove_finalizers "application" "$name" "openshift-gitops"
            done
        
        # CRITICAL: Delete cluster-config FIRST to stop app-of-apps from
        # recreating child applications (it has auto-sync enabled)
        echo "  → Deleting cluster-config (app-of-apps) to stop recreation..."
        oc delete application cluster-config -n openshift-gitops --ignore-not-found=true 2>/dev/null || true
        sleep 2
        
        # Now delete remaining applications (they won't be recreated)
        echo "  → Deleting remaining applications..."
        oc delete application --all -n openshift-gitops --ignore-not-found=true 2>/dev/null || true
        
        success "  ✓ Deleted $APP_COUNT application(s)"
    else
        echo "  → No applications found"
    fi
else
    echo "  → OpenShift GitOps not installed"
fi
success "  ✓ ArgoCD applications processed"
sleep 2

# ============================================
# Step 2: Delete PostgreSQL clusters
# ============================================
step 2 7 "Deleting PostgreSQL clusters..."
CLUSTER_COUNT=$(oc get postgresql --all-namespaces --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$CLUSTER_COUNT" -gt 0 ]; then
    echo "  → Found $CLUSTER_COUNT cluster(s):"
    
    oc get postgresql --all-namespaces -o json 2>/dev/null | \
        jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name) \(.spec.numberOfInstances) \(.spec.volume.size)"' | \
        while read ns name instances size; do
            POD_COUNT=$(oc get pods -n $ns -l application=spilo,cluster-name=$name --no-headers 2>/dev/null | wc -l | tr -d ' ')
            PVC_COUNT=$(oc get pvc -n $ns -l application=spilo,cluster-name=$name --no-headers 2>/dev/null | wc -l | tr -d ' ')
            echo "     • $ns/$name: $instances instance(s), ${size} storage, $POD_COUNT pod(s), $PVC_COUNT PVC(s)"
        done
    
    echo "  → Deleting clusters (operator will handle finalizers)..."
    oc get postgresql --all-namespaces -o json 2>/dev/null | \
        jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name)"' | \
        while read ns name; do
            echo "     → Deleting $ns/$name"
            oc delete postgresql $name -n $ns --ignore-not-found=true 2>/dev/null || true
        done
    
    echo "  → Waiting 10 seconds for operator to process deletions..."
    sleep 10
    
    # Check if any clusters are stuck
    REMAINING=$(oc get postgresql --all-namespaces --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "$REMAINING" -gt 0 ]; then
        if [ "$FORCE_FINALIZERS" = true ]; then
            echo -e "     ${YELLOW}⚠ $REMAINING cluster(s) still terminating - forcing finalizer removal${NC}"
            oc get postgresql --all-namespaces -o json 2>/dev/null | \
                jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name)"' | \
                while read ns name; do
                    echo "       → Force removing finalizers from $ns/$name"
                    remove_finalizers "postgresql" "$name" "$ns"
                done
        else
            echo -e "     ${YELLOW}⚠ $REMAINING cluster(s) still terminating (waiting for natural cleanup)${NC}"
            info "     Tip: Run with --force flag to remove finalizers immediately"
        fi
    fi
    
    success "  ✓ Deleted $CLUSTER_COUNT cluster(s)"
else
    echo "  → No clusters found"
fi
success "  ✓ PostgreSQL clusters processed"
sleep 2

# ============================================
# Step 3: Uninstall Helm releases
# ============================================
step 3 7 "Uninstalling Helm releases..."

if helm list -n $OPERATOR_NAMESPACE 2>/dev/null | grep -q postgres-operator-ui; then
    echo "  → Uninstalling UI via Helm..."
    helm uninstall postgres-operator-ui -n $OPERATOR_NAMESPACE
else
    echo "  → UI Helm release not found"
fi

# Delete UI route if it exists
if resource_exists "route" "postgres-operator-ui" "$OPERATOR_NAMESPACE"; then
    echo "  → Deleting UI route..."
    oc delete route postgres-operator-ui -n $OPERATOR_NAMESPACE --ignore-not-found=true 2>/dev/null
fi

if helm list -n $OPERATOR_NAMESPACE 2>/dev/null | grep -q postgres-operator; then
    echo "  → Uninstalling operator via Helm..."
    helm uninstall postgres-operator -n $OPERATOR_NAMESPACE
else
    echo "  → Operator Helm release not found"
fi

# Remove SCC rolebindings (anyuid)
if namespace_exists $OPERATOR_NAMESPACE; then
    SCC_BINDING=$(oc get rolebinding -n $OPERATOR_NAMESPACE -o name 2>/dev/null | grep "anyuid" || true)
    if [ -n "$SCC_BINDING" ]; then
        echo "  → Removing SCC rolebinding..."
        oc delete $SCC_BINDING -n $OPERATOR_NAMESPACE --ignore-not-found=true 2>/dev/null || true
    fi
fi

# Remove namespace-scoped RBAC
if namespace_exists $OPERATOR_NAMESPACE; then
    if resource_exists "role" "postgres-ui-access" "$OPERATOR_NAMESPACE"; then
        echo "  → Deleting namespace-scoped RBAC..."
        oc delete role postgres-ui-access -n $OPERATOR_NAMESPACE --ignore-not-found=true 2>/dev/null
        oc delete rolebinding dba-postgres-ui-access -n $OPERATOR_NAMESPACE --ignore-not-found=true 2>/dev/null
    fi
fi

success "  ✓ Helm releases processed"

# ============================================
# Step 4: Remove blocking finalizers
# ============================================
step 4 7 "Checking for resources that might block deletion..."
if [ "$FORCE_FINALIZERS" = true ]; then
    FINALIZERS_REMOVED=0
    for ns in $ALL_NAMESPACES; do
        if namespace_exists $ns; then
            # Remove PVC finalizers
            PVC_COUNT=$(oc get pvc -n $ns --no-headers 2>/dev/null | wc -l | tr -d ' ')
            if [ "$PVC_COUNT" -gt 0 ]; then
                echo "  → Removing PVC finalizers in $ns..."
                remove_all_finalizers "pvc" "$ns"
                FINALIZERS_REMOVED=$((FINALIZERS_REMOVED + PVC_COUNT))
            fi
            
            # Remove service finalizers
            SVC_COUNT=$(oc get svc -n $ns --no-headers 2>/dev/null | wc -l | tr -d ' ')
            if [ "$SVC_COUNT" -gt 0 ]; then
                echo "  → Removing service finalizers in $ns..."
                remove_all_finalizers "svc" "$ns"
                FINALIZERS_REMOVED=$((FINALIZERS_REMOVED + SVC_COUNT))
            fi
        fi
    done
    
    if [ "$FINALIZERS_REMOVED" -gt 0 ]; then
        success "  ✓ Processed $FINALIZERS_REMOVED resource(s)"
    else
        echo "  → No blocking finalizers found"
    fi
else
    echo "  → Skipping finalizer removal (safe mode)"
    info "     Resources will clean up naturally"
    info "     Note: PVCs may delay namespace deletion until volumes detach"
fi
success "  ✓ Resource check complete"

# ============================================
# Step 5: Delete namespaces
# ============================================
step 5 7 "Deleting namespaces..."
DELETED_COUNT=0
for ns in $ALL_NAMESPACES; do
    if namespace_exists $ns; then
        echo "  → Namespace: $ns"
        
        # Show current resources before deletion
        POD_COUNT=$(oc get pods -n $ns --no-headers 2>/dev/null | wc -l | tr -d ' ')
        SVC_COUNT=$(oc get svc -n $ns --no-headers 2>/dev/null | wc -l | tr -d ' ')
        PVC_COUNT=$(oc get pvc -n $ns --no-headers 2>/dev/null | wc -l | tr -d ' ')
        
        if [ "$POD_COUNT" -gt 0 ] || [ "$SVC_COUNT" -gt 0 ] || [ "$PVC_COUNT" -gt 0 ]; then
            echo "     Resources: ${POD_COUNT} pod(s), ${SVC_COUNT} service(s), ${PVC_COUNT} PVC(s)"
        else
            echo "     (empty namespace)"
        fi
        
        echo "     Deleting namespace..."
        oc delete namespace $ns --ignore-not-found=true 2>/dev/null || true
        
        if [ "$FORCE_FINALIZERS" = true ]; then
            sleep 2
            if namespace_exists $ns; then
                echo "     → Force removing namespace finalizers"
                oc get namespace $ns -o json 2>/dev/null | jq '.spec.finalizers = []' | \
                    oc replace --raw /api/v1/namespaces/$ns/finalize -f - 2>/dev/null || true
            fi
        fi
        DELETED_COUNT=$((DELETED_COUNT + 1))
    fi
done

if [ "$DELETED_COUNT" -gt 0 ]; then
    success "  ✓ Deleted $DELETED_COUNT namespace(s)"
else
    echo "  → Namespaces: not found (already deleted)"
fi
sleep 2

# ============================================
# Step 6: Delete cluster RBAC resources
# ============================================
step 6 7 "Deleting cluster RBAC resources..."

# Delete OpenShift Groups
if resource_exists "group" "dba-users"; then
    echo "  → Deleting OpenShift Groups..."
    oc delete group dba-users --ignore-not-found=true 2>/dev/null
else
    echo "  → OpenShift Groups not found"
fi

# Delete ClusterRoles
echo "  → Deleting ClusterRoles..."
oc delete clusterrole $CLUSTER_ROLES --ignore-not-found=true 2>/dev/null || true

# Delete ClusterRoleBindings
echo "  → Deleting ClusterRoleBindings..."
oc delete clusterrolebinding $CLUSTER_ROLE_BINDINGS --ignore-not-found=true 2>/dev/null || true

success "  ✓ RBAC resources processed"

# ============================================
# Step 7: Delete CRDs
# ============================================
step 7 7 "Deleting CRDs..."
CRD_COUNT=0
for crd in $OPERATOR_CRDS; do
    if resource_exists "crd" "$crd"; then
        echo "  → Deleting CRD: $crd"
        if [ "$FORCE_FINALIZERS" = true ]; then
            remove_finalizers "crd" "$crd"
        fi
        oc delete crd $crd --ignore-not-found=true 2>/dev/null || true
        CRD_COUNT=$((CRD_COUNT + 1))
    fi
done

if [ "$CRD_COUNT" -gt 0 ]; then
    success "  ✓ Deleted $CRD_COUNT CRD(s)"
else
    echo "  → CRDs not found"
fi
success "  ✓ CRD cleanup complete"

echo ""
banner "Cleanup complete!"
