#!/bin/bash
set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/functions.sh"

banner "Setting up ALL DBA RBAC"

# Create PostgreSQL DBA users
create_openshift_users "pg-dba pg-dba-dev pg-dba-test pg-dba-prod" "$DBA_PASSWORD"
echo ""

# Create MongoDB DBA users
create_openshift_users "mongo-dba mongo-dba-dev mongo-dba-test mongo-dba-prod" "$DBA_PASSWORD"
echo ""

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
echo "Registering users in groups..."
oc adm groups add-users pg-dba-users    pg-dba pg-dba-dev pg-dba-test pg-dba-prod 2>/dev/null || true
oc adm groups add-users mongo-dba-users mongo-dba mongo-dba-dev mongo-dba-test mongo-dba-prod 2>/dev/null || true

success ""
success "✓ All RBAC configured"
echo ""
echo "PostgreSQL DBA users (Crunchy PGO):"
echo "  - pg-dba (master): Full access to all pg-* namespaces"
echo "  - pg-dba-dev: Write to pg-dev"
echo "  - pg-dba-test: Write to pg-test"
echo "  - pg-dba-prod: Write to pg-prod"
echo ""
echo "MongoDB DBA users (Percona Operator):"
echo "  - mongo-dba (master): Full access to all mongo-* namespaces"
echo "  - mongo-dba-dev: Write to mongo-dev"
echo "  - mongo-dba-test: Write to mongo-test"
echo "  - mongo-dba-prod: Write to mongo-prod"
echo ""
echo "  - secops: Read-only monitoring access (cluster-wide)"
echo ""
echo "Password for all users: ${DBA_PASSWORD}"
