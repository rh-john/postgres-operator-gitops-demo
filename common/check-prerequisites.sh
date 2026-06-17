#!/bin/bash

echo "Prerequisites Check"
echo "==================="
echo ""

MISSING=()
WARNINGS=()

# Check oc
if command -v oc &>/dev/null; then
    echo "✓ oc: $(oc version --client | head -1)"
else
    echo "✗ oc: Not found"
    MISSING+=("oc")
fi

# Check helm
if command -v helm &>/dev/null; then
    echo "✓ helm: $(helm version --short 2>/dev/null || helm version)"
else
    echo "✗ helm: Not found"
    MISSING+=("helm")
fi

# Check jq
if command -v jq &>/dev/null; then
    echo "✓ jq: $(jq --version)"
else
    echo "✗ jq: Not found"
    MISSING+=("jq")
fi

# Check login
echo ""
if oc whoami &>/dev/null; then
    CURRENT_USER=$(oc whoami)
    echo "✓ OpenShift: Logged in as $CURRENT_USER"
    echo "  Server: $(oc whoami --show-server)"
    
    # Check if user is cluster-admin (needed for setup)
    if oc auth can-i '*' '*' &>/dev/null; then
        echo "  ✓ Admin privileges: Yes"
    else
        echo "  ⚠ Admin privileges: No (required for initial setup)"
        WARNINGS+=("admin-privileges")
    fi
else
    echo "✗ OpenShift: Not logged in"
    MISSING+=("login")
fi

# Detect which demo is active.
# Priority: 1) --dbaas / --zalando flag, 2) git branch, 3) deployed namespaces/apps
DEMO_MODE="zalando"
for arg in "$@"; do
    case $arg in
        --dbaas)   DEMO_MODE="dbaas";    break ;;
        --zalando) DEMO_MODE="zalando";  break ;;
    esac
done

if [ "$DEMO_MODE" = "zalando" ]; then
    GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    if [[ "$GIT_BRANCH" == *"dbaas"* ]] || [[ "$GIT_BRANCH" == *"operators"* ]]; then
        DEMO_MODE="dbaas"
    elif oc get namespace pg-dev &>/dev/null 2>&1 || \
         oc get application cluster-config-dbaas -n openshift-gitops &>/dev/null 2>&1; then
        DEMO_MODE="dbaas"
    fi
fi

echo "Demo mode: $DEMO_MODE"

# Check OpenShift users (if logged in)
echo ""
if oc whoami &>/dev/null && oc auth can-i list users &>/dev/null; then
    if [ "$DEMO_MODE" = "dbaas" ]; then
        echo "OpenShift Users (DBaaS demo – pg-dba-* / mongo-dba-*):"
        REQUIRED_USERS=("pg-dba" "pg-dba-dev" "pg-dba-test" "pg-dba-prod"
                        "mongo-dba" "mongo-dba-dev" "mongo-dba-test" "mongo-dba-prod"
                        "secops")
        SETUP_HINT="./common/setup-dbaas-rbac.sh"
    else
        echo "OpenShift Users (Zalando demo – dba/dba-dev/dba-test/dba-prod):"
        REQUIRED_USERS=("dba" "dba-dev" "dba-test" "dba-prod" "secops")
        SETUP_HINT="./common/setup-dba-rbac.sh"
    fi

    for user in "${REQUIRED_USERS[@]}"; do
        if oc get user "$user" &>/dev/null; then
            echo "  ✓ $user"
        else
            echo "  ✗ $user (missing) → run: $SETUP_HINT"
            MISSING+=("user:$user")
        fi
    done
else
    echo "OpenShift Users:"
    echo "  ⚠ Cannot check users (not logged in or insufficient privileges)"
fi

# Check OpenShift groups (if logged in)
echo ""
echo "OpenShift Groups:"
if oc whoami &>/dev/null && oc auth can-i list groups &>/dev/null; then
    if [ "$DEMO_MODE" = "dbaas" ]; then
        GROUPS_TO_CHECK=("pg-dba-users" "mongo-dba-users")
        EXPECTED_MEMBERS_pg=("pg-dba" "pg-dba-dev" "pg-dba-test" "pg-dba-prod")
        EXPECTED_MEMBERS_mongo=("mongo-dba" "mongo-dba-dev" "mongo-dba-test" "mongo-dba-prod")
        for grp in "${GROUPS_TO_CHECK[@]}"; do
            if oc get group "$grp" &>/dev/null; then
                MEMBERS=$(oc get group "$grp" -o jsonpath='{.users[*]}' 2>/dev/null)
                echo "  ✓ $grp (members: $MEMBERS)"
            else
                echo "  ✗ $grp not found → run: ./common/setup-dbaas-rbac.sh"
                WARNINGS+=("group:$grp")
            fi
        done
    else
        if oc get group dba-users &>/dev/null; then
            GROUP_MEMBERS=$(oc get group dba-users -o jsonpath='{.users[*]}' 2>/dev/null)
            echo "  ✓ dba-users exists"
            echo "    Members: $GROUP_MEMBERS"
            for member in "dba" "dba-dev" "dba-test" "dba-prod"; do
                if echo "$GROUP_MEMBERS" | grep -q "$member"; then
                    echo "    ✓ $member in group"
                else
                    echo "    ✗ $member NOT in group"
                    WARNINGS+=("group-member:$member")
                fi
            done
        else
            echo "  ✗ dba-users group not found → run: ./common/setup-dba-rbac.sh"
            WARNINGS+=("group:dba-users")
        fi
    fi
else
    echo "  ⚠ Cannot check groups (not logged in or insufficient privileges)"
fi

# Summary
echo ""
echo "Summary"
echo "======="
if [ ${#MISSING[@]} -eq 0 ] && [ ${#WARNINGS[@]} -eq 0 ]; then
    echo "✓ All prerequisites met - ready to deploy!"
    exit 0
elif [ ${#MISSING[@]} -eq 0 ]; then
    echo "⚠ Prerequisites mostly met, but with warnings:"
    for warning in "${WARNINGS[@]}"; do
        echo "  - $warning"
    done
    echo ""
    echo "You can proceed, but may need to create users/groups first."
    echo "See: DEMO.md or DEMO-HELM.md for user/group setup instructions."
    exit 0
else
    echo "✗ Missing required prerequisites:"
    for missing in "${MISSING[@]}"; do
        echo "  - $missing"
    done
    if [ ${#WARNINGS[@]} -gt 0 ]; then
        echo ""
        echo "⚠ Additional warnings:"
        for warning in "${WARNINGS[@]}"; do
            echo "  - $warning"
        done
    fi
    exit 1
fi
