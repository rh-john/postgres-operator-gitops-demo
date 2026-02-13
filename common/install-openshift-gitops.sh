#!/bin/bash
set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/functions.sh"

echo "OpenShift GitOps Installation"
echo "=============================="
echo ""

check_oc_login

# Check if already installed
if namespace_exists "openshift-gitops"; then
    echo "Already installed"
    if resource_exists "deployment" "openshift-gitops-server" "openshift-gitops"; then
        if is_deployment_ready "openshift-gitops-server" "openshift-gitops"; then
            ROUTE=$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}')
            PASSWORD=$(oc get secret openshift-gitops-cluster -n openshift-gitops -o jsonpath='{.data.admin\.password}' | base64 -d)
            echo ""
            echo "ArgoCD URL: https://$ROUTE"
            echo "Username: admin"
            echo "Password: $PASSWORD"
            exit 0
        fi
    fi
fi

echo "Installing operator..."
echo ""

# Install operator
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-gitops-operator
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-gitops-operator
  namespace: openshift-gitops-operator
spec:
  upgradeStrategy: Default
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-gitops-operator
  namespace: openshift-gitops-operator
spec:
  channel: latest
  installPlanApproval: Automatic
  name: openshift-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

echo "Waiting for installation..."

# Wait for namespace and deployment
wait_for_namespace "openshift-gitops" 120
wait_for_deployment "openshift-gitops-server" "openshift-gitops" 360

echo ""
echo "Configuring ArgoCD permissions..."
# Grant cluster-admin to ArgoCD controllers so they can manage cluster resources
oc adm policy add-cluster-role-to-user cluster-admin \
    system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller \
    &>/dev/null || true
oc adm policy add-cluster-role-to-user cluster-admin \
    system:serviceaccount:openshift-gitops:openshift-gitops-applicationset-controller \
    &>/dev/null || true
echo "  → Granted cluster-admin permissions to ArgoCD controllers"

# Get credentials
ROUTE=$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}')
PASSWORD=$(oc get secret openshift-gitops-cluster -n openshift-gitops -o jsonpath='{.data.admin\.password}' | base64 -d 2>/dev/null || echo "pending")

echo ""
success "Installation complete"
echo ""
echo "ArgoCD URL: https://$ROUTE"
echo "Username: admin"
echo "Password: $PASSWORD"
