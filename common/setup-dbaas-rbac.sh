#!/bin/bash
set -e

# DBaaS demo RBAC setup – Crunchy PGO + Percona MongoDB users.
# The original setup-dba-rbac.sh (Zalando dba/dba-dev/dba-test/dba-prod) is untouched.
# Both can coexist on the same cluster.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/functions.sh"

banner "Setting up DBaaS RBAC (Crunchy PGO + Percona MongoDB)"

# ── PostgreSQL DBA users (Crunchy PGO) ─────────────────────────────────────
echo "Creating PostgreSQL DBA users..."
create_openshift_users "pg-dba pg-dba-dev pg-dba-test pg-dba-prod" "$DBA_PASSWORD"
echo ""

# ── MongoDB DBA users (Percona Operator) ───────────────────────────────────
echo "Creating MongoDB DBA users..."
create_openshift_users "mongo-dba mongo-dba-dev mongo-dba-test mongo-dba-prod" "$DBA_PASSWORD"
echo ""

# ── Apply RBAC manifests ───────────────────────────────────────────────────
echo "Applying DBaaS RBAC manifests..."
oc apply -f gitops/cluster-config/dbaas-rbac/postgres-user-role-crunchy.yaml
oc apply -f gitops/cluster-config/dbaas-rbac/mongo-user-role.yaml

echo ""
echo "Creating OpenShift User objects (required before first login)..."
ALL_USERS="pg-dba pg-dba-dev pg-dba-test pg-dba-prod mongo-dba mongo-dba-dev mongo-dba-test mongo-dba-prod secops"
for user in $ALL_USERS; do
    oc create user "$user" --dry-run=client -o yaml | oc apply -f - &>/dev/null
    echo "  → user object '$user' ensured"
done

echo ""
echo "Registering users in groups..."
oc adm groups new pg-dba-users    2>/dev/null || true
oc adm groups new mongo-dba-users 2>/dev/null || true
oc adm groups add-users pg-dba-users    pg-dba pg-dba-dev pg-dba-test pg-dba-prod 2>/dev/null || true
oc adm groups add-users mongo-dba-users mongo-dba mongo-dba-dev mongo-dba-test mongo-dba-prod 2>/dev/null || true

success ""
success "✓ DBaaS RBAC configured"
echo ""
echo "PostgreSQL DBA users (Crunchy PGO) – namespaces: pg-dev / pg-test / pg-prod"
echo "  - pg-dba       : full access to all pg-* namespaces"
echo "  - pg-dba-dev   : write to pg-dev"
echo "  - pg-dba-test  : write to pg-test"
echo "  - pg-dba-prod  : write to pg-prod"
echo ""
echo "MongoDB DBA users (Percona Operator) – namespaces: mongo-dev / mongo-test / mongo-prod"
echo "  - mongo-dba      : full access to all mongo-* namespaces"
echo "  - mongo-dba-dev  : write to mongo-dev"
echo "  - mongo-dba-test : write to mongo-test"
echo "  - mongo-dba-prod : write to mongo-prod"
echo ""
echo "Password for all users: ${DBA_PASSWORD}"
echo ""
echo "Login example:"
echo "  oc login --username=pg-dba --password='${DBA_PASSWORD}'"
