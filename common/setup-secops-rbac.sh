#!/bin/bash
set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/functions.sh"

banner "Setting up SecOps monitoring RBAC"

# Apply secops RBAC manifest
echo "Applying secops RBAC manifest..."
oc apply -f helm/rbac/secops.yaml

success ""
success "✓ SecOps monitoring access configured"
echo ""
echo "User: secops"
echo "Access: Read-only to all PostgreSQL resources"
echo ""
echo "Login:"
echo "  oc login --username=secops --password='Redhat123p@ssword'"
