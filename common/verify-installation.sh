#!/bin/bash
# Note: Not using 'set -e' to allow script to continue on permission check failures

# Source common functions (provides colors, constants, helpers)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/functions.sh"

# Helper: record a failure (call alongside any $FAIL output)
mark_fail() {
    VERIFICATION_PASS=false
}

echo "================================================"
echo "PostgreSQL Operator - Full Installation Verification"
echo "================================================"
echo ""

# Track overall verification result
VERIFICATION_PASS=true

# Must be run as cluster-admin for full verification
CURRENT_USER=$(oc whoami 2>/dev/null || echo "")
if [ -z "$CURRENT_USER" ]; then
    echo -e "${FAIL} Not logged in to OpenShift"
    exit 1
fi

echo -e "Current user: ${BOLD}${CURRENT_USER}${NC}"

# Check if user has cluster-admin privileges
if oc auth can-i '*' '*' &>/dev/null; then
    echo -e "${OK} Running with cluster-admin privileges"
else
    echo -e "${WARN} Not running as cluster-admin - some checks will be skipped"
    echo "      For full verification, run as cluster-admin"
fi
echo ""

# ==============================================
# 1. INFRASTRUCTURE CHECKS
# ==============================================
echo -e "${YELLOW}=== Infrastructure ===${NC}"
echo ""

# Check operator
echo "Operator:"
if oc get deployment postgres-operator -n postgres-operator &>/dev/null; then
    READY=$(oc get deployment postgres-operator -n postgres-operator -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    DESIRED=$(oc get deployment postgres-operator -n postgres-operator -o jsonpath='{.status.replicas}' 2>/dev/null)
    # Default to 0 if empty
    READY=${READY:-0}
    DESIRED=${DESIRED:-0}
    STATUS="$READY/$DESIRED"
    
    if [ "$READY" -gt 0 ] && [ "$READY" -eq "$DESIRED" ]; then
        echo -e "  $OK Running ($STATUS)"
        
        # Check which namespaces the operator watches
        WATCHED_NS=$(oc get deployment postgres-operator -n postgres-operator -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="WATCHED_NAMESPACE")].value}' 2>/dev/null)
        if [ -z "$WATCHED_NS" ]; then
            echo -e "  ${INFO} Watches: ${CYAN}All namespaces${NC} (cluster-wide)"
        else
            echo -e "  ${INFO} Watches: ${CYAN}$WATCHED_NS${NC}"
        fi
        
        # Show operator configuration source
        CONFIG_TYPE=$(oc get deployment postgres-operator -n postgres-operator -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="CONFIG_MAP_NAME")].value}' 2>/dev/null)
        if [ -n "$CONFIG_TYPE" ]; then
            echo -e "  ${INFO} Config: Using ConfigMap ($CONFIG_TYPE)"
        else
            echo -e "  ${INFO} Config: Using CRD (OperatorConfiguration)"
        fi
        
    elif [ "$READY" -gt 0 ]; then
        echo -e "  $WARN Partially ready ($STATUS)"
    else
        echo -e "  $FAIL Not running ($STATUS)"; mark_fail
        echo -e "      ${YELLOW}Check: oc get pods -n postgres-operator${NC}"
        echo -e "      ${YELLOW}Check: oc logs -n postgres-operator deployment/postgres-operator${NC}"
    fi
else
    echo -e "  $FAIL Not found"; mark_fail
fi

# Check UI
echo "UI:"
if oc get deployment postgres-operator-ui -n postgres-operator &>/dev/null; then
    READY=$(oc get deployment postgres-operator-ui -n postgres-operator -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    DESIRED=$(oc get deployment postgres-operator-ui -n postgres-operator -o jsonpath='{.status.replicas}' 2>/dev/null)
    # Default to 0 if empty
    READY=${READY:-0}
    DESIRED=${DESIRED:-0}
    STATUS="$READY/$DESIRED"
    
    if [ "$READY" -gt 0 ] && [ "$READY" -eq "$DESIRED" ]; then
        echo -e "  $OK Running ($STATUS)"
    elif [ "$READY" -gt 0 ]; then
        echo -e "  $WARN Partially ready ($STATUS)"
    else
        echo -e "  $FAIL Not running ($STATUS)"; mark_fail
        echo -e "      ${YELLOW}Check: oc get pods -n postgres-operator${NC}"
    fi
else
    echo -e "  $FAIL Not found"; mark_fail
fi

# Check CRDs
echo "CRDs:"
if oc get crd postgresqls.acid.zalan.do &>/dev/null; then
    echo -e "  $OK postgresqls.acid.zalan.do"
else
    echo -e "  $FAIL postgresqls.acid.zalan.do"; mark_fail
fi

# Check SCC
echo "SCC:"
# Check if namespace exists first
if oc get namespace postgres-operator &>/dev/null 2>&1; then
    # Check if ServiceAccount exists
    if oc get serviceaccount postgres-operator -n postgres-operator &>/dev/null 2>&1; then
        # Check if SA can use anyuid SCC
        if oc adm policy who-can use scc anyuid -n postgres-operator 2>/dev/null | grep -q "system:serviceaccount:postgres-operator:postgres-operator"; then
            echo -e "  $OK postgres-operator ServiceAccount has anyuid SCC"
        else
            echo -e "  $WARN postgres-operator ServiceAccount missing anyuid SCC"
        fi
    else
        echo -e "  $FAIL postgres-operator ServiceAccount not found"; mark_fail
    fi
else
    echo -e "  $FAIL postgres-operator namespace not found"; mark_fail
fi

echo ""

# ==============================================
# 2. NAMESPACE CHECKS
# ==============================================
echo -e "${YELLOW}=== Namespaces ===${NC}"
echo ""

for ns in $DB_NAMESPACES; do
    if oc get namespace $ns &>/dev/null; then
        echo -e "$OK $ns"
        
        # Check if any database pods exist and are running
        POD_COUNT=$(oc get pods -n $ns --no-headers 2>/dev/null | wc -l | tr -d ' ')
        if [ "$POD_COUNT" -gt 0 ]; then
            RUNNING_COUNT=$(oc get pods -n $ns --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
            # Count ready containers, handling edge cases
            READY_COUNT=$(oc get pods -n $ns -o jsonpath='{range .items[*]}{.status.containerStatuses[0].ready}{"\n"}{end}' 2>/dev/null | grep -c "true" 2>/dev/null || echo "0")
            # Remove any whitespace/newlines and ensure it's a number
            READY_COUNT=$(echo "$READY_COUNT" | tr -d '\n\r ' | grep -E '^[0-9]+$' || echo "0")
            
            if [ "$READY_COUNT" -eq "$POD_COUNT" ]; then
                echo -e "  ├─ Database Pods: $OK ($READY_COUNT/$POD_COUNT ready)"
            elif [ "$RUNNING_COUNT" -gt 0 ]; then
                echo -e "  ├─ Database Pods: $WARN ($READY_COUNT/$POD_COUNT ready, $RUNNING_COUNT running)"
                echo -e "     ${YELLOW}Check: oc get pods -n $ns${NC}"
            else
                echo -e "  ├─ Database Pods: $FAIL (0/$POD_COUNT running)"; mark_fail
                echo -e "     ${YELLOW}Check: oc get pods -n $ns${NC}"
                echo -e "     ${YELLOW}Check: oc describe pods -n $ns${NC}"
            fi
        else
            echo -e "  ├─ Database Pods: $INFO No pods yet (cluster not deployed)"
        fi
        
        # Check postgres-pod ServiceAccount (created by operator)
        if oc get serviceaccount postgres-pod -n $ns &>/dev/null; then
            echo -e "  ├─ postgres-pod ServiceAccount: $OK"
        else
            echo -e "  ├─ postgres-pod ServiceAccount: $WARN (created by operator when cluster deployed)"
        fi
        
        # Check SCC RoleBinding
        if oc get rolebinding postgres-pod-anyuid -n $ns &>/dev/null; then
            echo -e "  ├─ SCC RoleBinding (anyuid): $OK"
        else
            echo -e "  ├─ SCC RoleBinding (anyuid): $FAIL"; mark_fail
        fi
        
        # Check PostgreSQL clusters
        CLUSTER_COUNT=$(oc get postgresql -n $ns --no-headers 2>/dev/null | wc -l | tr -d ' ')
        if [ "$CLUSTER_COUNT" -gt 0 ]; then
            echo "  ├─ PostgreSQL clusters: $CLUSTER_COUNT"
            oc get postgresql -n $ns --no-headers 2>/dev/null | while read name team version pods rest; do
                echo "  │  └─ $name"
            done
        else
            echo "  ├─ PostgreSQL clusters: 0"
        fi
        
        # Check Frontend
        if oc get deployment frontend -n $ns &>/dev/null; then
            F_READY=$(oc get deployment frontend -n $ns -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
            F_DESIRED=$(oc get deployment frontend -n $ns -o jsonpath='{.status.replicas}' 2>/dev/null)
            F_READY=${F_READY:-0}
            F_DESIRED=${F_DESIRED:-0}
            if [ "$F_READY" -gt 0 ] && [ "$F_READY" -eq "$F_DESIRED" ]; then
                ROUTE=$(oc get route frontend -n $ns -o jsonpath='{.spec.host}' 2>/dev/null || echo "none")
                echo -e "  └─ Frontend: $OK ($F_READY/$F_DESIRED ready, route: $ROUTE)"
            else
                echo -e "  └─ Frontend: $WARN ($F_READY/$F_DESIRED ready)"
            fi
        else
            echo -e "  └─ Frontend: $INFO Not deployed"
        fi
    else
        echo -e "$FAIL $ns"; mark_fail
    fi
done

echo ""

# ==============================================
# 3. NETWORK POLICY CHECKS
# ==============================================
echo -e "${YELLOW}=== Network Policies ===${NC}"
echo ""

EXPECTED_POLICIES=(
    "default-deny-ingress"
    "allow-postgres-same-namespace"
    "allow-postgres-operator"
    "allow-monitoring"
    "allow-patroni-cluster"
    "allow-frontend-ingress"
)

for ns in $DB_NAMESPACES; do
    echo "Namespace: $ns"
    ALL_PRESENT=true
    
    for policy in "${EXPECTED_POLICIES[@]}"; do
        if oc get networkpolicy "$policy" -n "$ns" &>/dev/null; then
            echo -e "  $OK $policy"
        else
            echo -e "  $FAIL $policy (missing)"; mark_fail
            ALL_PRESENT=false
        fi
    done
    
    if [ "$ALL_PRESENT" = true ]; then
        echo -e "  ${GREEN}All policies configured${NC}"
    else
        echo -e "  ${RED}Some policies missing!${NC}"
    fi
    echo ""
done

# ==============================================
# 4. RBAC CHECKS
# ==============================================
echo -e "${YELLOW}=== RBAC Configuration ===${NC}"
echo ""

# Check if user has permissions to view cluster resources
HAS_CLUSTER_PERMISSIONS=false
if oc auth can-i list clusterroles &>/dev/null && oc auth can-i list groups &>/dev/null; then
    HAS_CLUSTER_PERMISSIONS=true
fi

if [ "$HAS_CLUSTER_PERMISSIONS" = false ]; then
    echo -e "$WARN Skipping cluster-level RBAC checks (requires cluster-admin)"
    echo "      To verify RBAC: run as cluster-admin"
    echo ""
    echo -e "$INFO Checking namespace-level RBAC only..."
    echo ""
fi

# Check Group (requires admin)
if [ "$HAS_CLUSTER_PERMISSIONS" = true ]; then
    echo "OpenShift Groups:"
    if oc get group dba-users &>/dev/null; then
        MEMBERS=$(oc get group dba-users -o jsonpath='{.users[*]}' 2>/dev/null)
        echo -e "  $OK dba-users group (members: $MEMBERS)"
    else
        echo -e "  $FAIL dba-users group (missing)"; mark_fail
    fi

    # Check ClusterRoles
    echo "ClusterRoles:"
    if oc get clusterrole postgres-user-role &>/dev/null; then
        echo -e "  $OK postgres-user-role"
    else
        echo -e "  $FAIL postgres-user-role"; mark_fail
    fi
    if oc get clusterrole postgres-monitor &>/dev/null; then
        echo -e "  $OK postgres-monitor"
    else
        echo -e "  $FAIL postgres-monitor"; mark_fail
    fi

    # Check master DBA ClusterRoleBinding
    echo "Master DBA (dba):"
    if oc get clusterrolebinding dba-master-postgres-user &>/dev/null; then
        echo -e "  $OK ClusterRoleBinding: dba-master-postgres-user"
    else
        echo -e "  $FAIL ClusterRoleBinding: dba-master-postgres-user"; mark_fail
    fi
    
    # Check secops
    echo "Monitoring (secops):"
    if oc get clusterrolebinding secops-postgres-monitoring &>/dev/null; then
        echo -e "  $OK ClusterRoleBinding: secops-postgres-monitoring"
    else
        echo -e "  $FAIL ClusterRoleBinding: secops-postgres-monitoring"; mark_fail
    fi
    if oc get clusterrolebinding secops-postgres-read &>/dev/null; then
        echo -e "  $OK ClusterRoleBinding: secops-postgres-read"
    else
        echo -e "  $FAIL ClusterRoleBinding: secops-postgres-read"; mark_fail
    fi
    echo ""
fi

# Namespace-level RBAC (always check these)
echo "Namespace-level RBAC:"

# Check UI access role
if oc get role postgres-ui-access -n postgres-operator &>/dev/null; then
    echo -e "  $OK Role: postgres-ui-access (UI port-forward)"
else
    echo -e "  $WARN Role: postgres-ui-access (UI port-forward) - not found"
fi
if oc get rolebinding dba-postgres-ui-access -n postgres-operator &>/dev/null; then
    echo -e "  $OK RoleBinding: dba-postgres-ui-access"
else
    echo -e "  $WARN RoleBinding: dba-postgres-ui-access - not found"
fi

# Check environment-specific DBA RoleBindings
for env in dev test prod; do
    ns="dba-${env}"
    user="dba-${env}"
    
    if oc get rolebinding postgres-user-binding -n $ns &>/dev/null; then
        echo -e "  $OK $user → $ns (postgres-user-binding)"
    else
        echo -e "  $WARN $user → $ns (postgres-user-binding) - not found"
    fi
    
    if oc get rolebinding ${user}-view -n $ns &>/dev/null; then
        echo -e "  $OK $user → $ns (${user}-view)"
    else
        echo -e "  $WARN $user → $ns (${user}-view) - not found"
    fi
done

# Check dba-users group RoleBindings
for ns in $DB_NAMESPACES; do
    if oc get rolebinding dba-users-view -n $ns &>/dev/null; then
        echo -e "  $OK $ns: dba-users-view (cross-namespace read)"
    else
        echo -e "  $WARN $ns: dba-users-view - not found"
    fi
    if oc get rolebinding dba-users-postgres-read -n $ns &>/dev/null; then
        echo -e "  $OK $ns: dba-users-postgres-read"
    else
        echo -e "  $WARN $ns: dba-users-postgres-read - not found"
    fi
done

echo ""

# ==============================================
# 5. USER PERMISSION TESTS (Real Login Tests)
# ==============================================
echo -e "${YELLOW}=== User Permission Tests (Real Login) ===${NC}"
echo ""
echo "Testing actual user permissions by logging in as each user..."
echo "This properly validates OpenShift Group membership."
echo ""

# Save current context
ORIGINAL_CONTEXT=$(oc config current-context 2>/dev/null)
ORIGINAL_USER=$CURRENT_USER
API_SERVER=$(oc whoami --show-server)
PASSWORD="$DBA_PASSWORD"

# Function to test user permissions by actually logging in
test_user_permissions_real() {
    local user=$1
    local user_env=$2  # Which namespace they should have write access to
    local namespaces=("dba-dev" "dba-test" "dba-prod")
    
    echo -e "${CYAN}Testing: ${user}${NC}"
    
    # Login as user
    if oc login "$API_SERVER" --username="$user" --password="$PASSWORD" &>/dev/null; then
        
        for ns in "${namespaces[@]}"; do
            CAN_GET=$(oc auth can-i get postgresql -n $ns 2>/dev/null)
            CAN_CREATE=$(oc auth can-i create postgresql -n $ns 2>/dev/null)
            
            # Determine expected behavior
            if [ "$user" = "dba" ]; then
                # Master DBA should have full access everywhere
                EXPECTED_GET="yes"
                EXPECTED_CREATE="yes"
            elif [ "$ns" = "$user_env" ]; then
                # Should have write access in own namespace
                EXPECTED_GET="yes"
                EXPECTED_CREATE="yes"
            else
                # Should have read-only in other namespaces (via group)
                EXPECTED_GET="yes"
                EXPECTED_CREATE="no"
            fi
            
            # Build status string with clear read/write indicators
            if [ "$CAN_CREATE" = "yes" ]; then
                # Has write access
                ACCESS_TYPE="${BOLD}${GREEN}READ+WRITE${NC}"
            elif [ "$CAN_GET" = "yes" ]; then
                # Read-only access
                ACCESS_TYPE="${CYAN}READ-ONLY${NC}"
            else
                # No access
                ACCESS_TYPE="${RED}NO ACCESS${NC}"
            fi
            
            # Check if actual matches expected
            if [ "$CAN_GET" = "$EXPECTED_GET" ] && [ "$CAN_CREATE" = "$EXPECTED_CREATE" ]; then
                echo -e "  $OK $ns: $ACCESS_TYPE"
            else
                # Check if this might be due to missing CRD or resources
                if ! oc get crd postgresqls.acid.zalan.do &>/dev/null; then
                    echo -e "  $WARN $ns: Cannot verify (PostgreSQL CRD not installed)"
                elif [ "$CAN_GET" = "no" ] && [ "$CAN_CREATE" = "no" ]; then
                    echo -e "  $WARN $ns: ${RED}NO ACCESS${NC} (expected $ACCESS_TYPE)"
                else
                    echo -e "  $WARN $ns: $ACCESS_TYPE (expected READ=${EXPECTED_GET} WRITE=${EXPECTED_CREATE})"
                fi
            fi
        done
    else
        echo -e "  $FAIL Failed to login as $user"; mark_fail
    fi
    echo ""
}

# Test cluster-admin (current user should be admin)
if [[ "$ORIGINAL_USER" == *"admin"* ]] || oc auth can-i '*' '*' &>/dev/null; then
    echo -e "$OK cluster-admin: Full access (original user: $ORIGINAL_USER)"
    echo ""
fi

# Test master DBA
test_user_permissions_real "dba" "all"

# Test environment-specific DBAs
test_user_permissions_real "dba-dev" "dba-dev"
test_user_permissions_real "dba-test" "dba-test"
test_user_permissions_real "dba-prod" "dba-prod"

# Test secops (monitoring user)
echo -e "${CYAN}Testing: secops${NC}"
if oc login "$API_SERVER" --username="secops" --password="$PASSWORD" &>/dev/null; then
    for ns in $DB_NAMESPACES; do
        CAN_GET=$(oc auth can-i get postgresql -n $ns 2>/dev/null)
        CAN_CREATE=$(oc auth can-i create postgresql -n $ns 2>/dev/null)
        
        if [ "$CAN_GET" = "yes" ] && [ "$CAN_CREATE" = "no" ]; then
            echo -e "  $OK $ns: ${CYAN}READ-ONLY${NC} (monitoring)"
        elif ! oc get crd postgresqls.acid.zalan.do &>/dev/null; then
            echo -e "  $WARN $ns: Cannot verify (PostgreSQL CRD not installed)"
        else
            echo -e "  $WARN $ns: READ=${CAN_GET} WRITE=${CAN_CREATE} (expected read-only)"
        fi
    done
else
    echo -e "  $FAIL Failed to login as secops"; mark_fail
fi

echo ""

# Restore original context
echo "Restoring original session..."
if [ -n "$ORIGINAL_CONTEXT" ]; then
    oc config use-context "$ORIGINAL_CONTEXT" &>/dev/null
else
    # If no context, try to restore by server
    oc login "$API_SERVER" &>/dev/null
fi

# Verify we're back
RESTORED_USER=$(oc whoami 2>/dev/null)
if [ "$RESTORED_USER" = "$ORIGINAL_USER" ]; then
    echo -e "$OK Session restored to: $ORIGINAL_USER"
else
    echo -e "$WARN Session is now: $RESTORED_USER (was: $ORIGINAL_USER)"
    echo "  Run: oc config use-context $ORIGINAL_CONTEXT"
fi

echo ""

# ==============================================
# 6. NAMESPACE ISOLATION VERIFICATION
# ==============================================
echo -e "${YELLOW}=== Namespace Isolation Summary ===${NC}"
echo ""

echo "Expected behavior (validated above with real logins):"
echo ""
echo -e "  ${BOLD}User${NC}          │ ${BOLD}Access Pattern${NC}"
echo "  ────────────────┼────────────────────────────────────────────────────"
echo -e "  dba (master)   │ ${BOLD}${GREEN}READ+WRITE${NC} to ${BOLD}ALL${NC} dba-* namespaces"
echo -e "  dba-dev        │ ${BOLD}${GREEN}READ+WRITE${NC} dba-dev, ${CYAN}READ-ONLY${NC} dba-test/prod (via group)"
echo -e "  dba-test       │ ${BOLD}${GREEN}READ+WRITE${NC} dba-test, ${CYAN}READ-ONLY${NC} dba-dev/prod (via group)"
echo -e "  dba-prod       │ ${BOLD}${GREEN}READ+WRITE${NC} dba-prod, ${CYAN}READ-ONLY${NC} dba-dev/test (via group)"
echo -e "  secops         │ ${CYAN}READ-ONLY${NC} ALL namespaces (monitoring)"
echo ""

echo "Key Features:"
echo -e "  • ${CYAN}Cross-namespace READ${NC} access via dba-users OpenShift Group"
echo -e "  • ${GREEN}WRITE${NC} isolation enforced by namespace-specific RoleBindings"
echo "  • All users tested with actual login (not impersonation)"
echo ""

echo ""

# ==============================================
# SUMMARY
# ==============================================
echo "================================================"
if $VERIFICATION_PASS; then
    echo -e "$OK Verification Complete - All checks passed!"
else
    echo -e "$FAIL Verification Complete - Some checks failed"
fi
echo "================================================"
