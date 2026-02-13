#!/bin/bash
set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/functions.sh"

banner "Setting up ALL DBA namespaces and RBAC"

# Create all namespaces and RBAC
for ENV in dev test prod; do
    echo "Setting up dba-$ENV..."
    oc apply -k helm/overlays/$ENV/
    echo "✓ dba-$ENV ready"
    echo ""
done

success ""
success "✓ All namespaces configured"
echo ""
echo "Namespaces created:"
echo "  - dba-dev"
echo "  - dba-test"
echo "  - dba-prod"
echo ""
echo "Each namespace has:"
echo "  - Namespace with labels"
echo "  - SCC RoleBinding for PostgreSQL pods"
echo "  - View RoleBinding for DBA user"
echo "  - PostgreSQL user RoleBinding"
