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

# Check OpenShift users (if logged in)
echo ""
echo "OpenShift Users:"
if oc whoami &>/dev/null && oc auth can-i list users &>/dev/null; then
    REQUIRED_USERS=("dba" "dba-dev" "dba-test" "dba-prod" "secops")
    for user in "${REQUIRED_USERS[@]}"; do
        if oc get user "$user" &>/dev/null; then
            echo "  ✓ $user"
        else
            echo "  ✗ $user (missing)"
            MISSING+=("user:$user")
        fi
    done
else
    echo "  ⚠ Cannot check users (not logged in or insufficient privileges)"
fi

# Check OpenShift groups (if logged in)
echo ""
echo "OpenShift Groups:"
if oc whoami &>/dev/null && oc auth can-i list groups &>/dev/null; then
    if oc get group dba-users &>/dev/null; then
        GROUP_MEMBERS=$(oc get group dba-users -o jsonpath='{.users[*]}' 2>/dev/null)
        echo "  ✓ dba-users exists"
        echo "    Members: $GROUP_MEMBERS"
        
        # Verify expected members
        EXPECTED_MEMBERS=("dba" "dba-dev" "dba-test" "dba-prod")
        for member in "${EXPECTED_MEMBERS[@]}"; do
            if echo "$GROUP_MEMBERS" | grep -q "$member"; then
                echo "    ✓ $member in group"
            else
                echo "    ✗ $member NOT in group"
                WARNINGS+=("group-member:$member")
            fi
        done
    else
        echo "  ✗ dba-users group not found"
        echo "    Run: oc adm groups new dba-users"
        echo "    Then: oc adm groups add-users dba-users dba dba-dev dba-test dba-prod"
        WARNINGS+=("group:dba-users")
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
