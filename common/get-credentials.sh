#!/bin/bash
set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/functions.sh"

CLUSTER=$1
NAMESPACE=${2:-default}

if [ -z "$CLUSTER" ]; then
    echo "Usage: $0 <cluster-name> [namespace]"
    exit 1
fi

check_oc_login

echo "Credentials for: $CLUSTER (namespace: $NAMESPACE)"
echo ""

# Get all secrets for this cluster
SECRETS=$(oc get secrets -n $NAMESPACE -o name | grep "$CLUSTER.credentials")

if [ -z "$SECRETS" ]; then
    echo "No credentials found"
    exit 1
fi

# Display credentials
for SECRET in $SECRETS; do
    SECRET_NAME=$(basename $SECRET)
    USERNAME=$(oc get $SECRET -n $NAMESPACE -o jsonpath='{.data.username}' | base64 -d 2>/dev/null)
    PASSWORD=$(oc get $SECRET -n $NAMESPACE -o jsonpath='{.data.password}' | base64 -d 2>/dev/null)

    echo "User: $USERNAME"
    echo "Password: $PASSWORD"
    echo ""
done

# Connection info
MASTER_SVC="$CLUSTER.$NAMESPACE.svc.cluster.local"
REPLICA_SVC="$CLUSTER-repl.$NAMESPACE.svc.cluster.local"

echo "Connection:"
echo "  Master: $MASTER_SVC:5432"
echo "  Replica: $REPLICA_SVC:5432"
echo ""
echo "Connect: oc exec -it $CLUSTER-0 -n $NAMESPACE -- psql -U postgres"
