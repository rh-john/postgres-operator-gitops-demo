#!/bin/bash
set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/functions.sh"

banner "Configure ArgoCD OpenShift OAuth"

# Check logged in
check_oc_login

# Check GitOps installed
if ! namespace_exists "openshift-gitops"; then
    die "OpenShift GitOps not installed. Run: ./common/install-openshift-gitops.sh"
fi

echo "Applying ArgoCD OAuth configuration..."
oc apply -f gitops/cluster-config/argocd-oauth-config.yaml

echo ""
echo "Waiting for ArgoCD operator to reconcile changes..."
sleep 10

echo "Restarting ArgoCD components to apply new configuration..."

# Restart repo-server and application-controller to pick up CR changes
oc rollout restart deployment openshift-gitops-repo-server -n openshift-gitops
oc rollout restart statefulset openshift-gitops-application-controller -n openshift-gitops

echo ""
echo "Waiting for ArgoCD components to restart..."
sleep 5

# Wait for components
wait_for_pods "app.kubernetes.io/name=openshift-gitops-dex-server" "openshift-gitops" 300 || echo "Dex starting..."
wait_for_pods "app.kubernetes.io/name=openshift-gitops-server" "openshift-gitops" 300

oc rollout status deployment openshift-gitops-repo-server -n openshift-gitops --timeout=300s
oc rollout status statefulset openshift-gitops-application-controller -n openshift-gitops --timeout=300s

separator
success "Configuration complete!"
separator
echo ""

ROUTE=$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}')

echo "ArgoCD URL: https://$ROUTE"
echo ""
echo "Login with OpenShift credentials:"
echo "  - Master DBA: dba / Redhat123p@ssword (full admin)"
echo "  - Dev DBA:    dba-dev / Redhat123p@ssword (team-dev-postgres only)"
echo "  - Test DBA:   dba-test / Redhat123p@ssword (team-test-postgres only)"
echo "  - Prod DBA:   dba-prod / Redhat123p@ssword (team-prod-postgres only)"
echo "  - SecOps:     secops / Redhat123p@ssword (read-only)"
echo ""
info "Note: Click 'LOG IN VIA OPENSHIFT' button"
echo ""
echo "Git Sync Configuration:"
echo "  - Webhook URL: https://$ROUTE/api/webhook"
echo "  - Polling interval: 30 seconds (fallback if webhook unavailable)"
echo ""
echo "To enable instant Git sync, add webhook to your Git repository:"
echo "  Payload URL: https://$ROUTE/api/webhook"
echo "  Content type: application/json"
echo "  Events: Just the push event"
echo ""
