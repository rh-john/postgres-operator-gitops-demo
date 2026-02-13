#!/bin/bash
set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/functions.sh"

banner "Setting up ALL DBA RBAC"

# Apply cluster-level RBAC manifests
# Note: Cross-namespace read access RoleBindings (dba-users-group.yaml) are
# configured per namespace in helm/overlays/{env}/ (applied via oc apply -k)
echo "Applying cluster-level RBAC manifests..."
oc apply -f helm/rbac/dba-users-group-definition.yaml  # Create dba-users group first
oc apply -f helm/rbac/postgres-user-role.yaml
oc apply -f helm/rbac/master-dba.yaml
oc apply -f helm/rbac/master-dba-ui-access.yaml        # UI port-forward access
oc apply -f helm/rbac/secops.yaml

echo ""
echo "Ensuring users are properly registered in dba-users group..."
oc adm groups add-users dba-users dba dba-dev dba-test dba-prod 2>/dev/null || true

success ""
success "✓ All RBAC configured"
echo ""
echo "Group created:"
echo "  - dba-users (group): Contains dba, dba-dev, dba-test, dba-prod"
echo ""
echo "Users configured:"
echo "  - dba (master): Full access to all namespaces + UI port-forward"
echo "  - dba-dev: Write to dba-dev, read all dba-* (via group)"
echo "  - dba-test: Write to dba-test, read all dba-* (via group)"
echo "  - dba-prod: Write to dba-prod, read all dba-* (via group)"
echo "  - secops: Read-only monitoring access (cluster-wide)"
