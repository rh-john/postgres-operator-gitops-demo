# Part 1: Helm/Manual Deployment

Manual deployment with Helm - learn the fundamentals and maintain full control.

**Time:** ~15 minutes | [← Back to Index](DEMO.md) | [Compare Methods →](DEMO-COMPARISON.md)

---

## Overview

**Objective:** Deploy PostgreSQL Operator manually with Helm, then let DBA users deploy databases.

**Steps:**
1. Install PostgreSQL Operator (cluster-admin)
2. Setup RBAC for multi-tenant access
3. Deploy databases as DBA users
4. Test namespace isolation
5. Verify cross-environment visibility

**Why This Method?**
- Simple and direct
- Full manual control
- Familiar Kubernetes workflow
- Good for learning and experimentation

---

## Prerequisites Check

**First-time setup:** See [docs/PREREQUISITES.md](docs/PREREQUISITES.md) for complete prerequisites including user and group creation.

```bash
# Check you're logged in as cluster-admin
oc whoami
# Should show: cluster-admin

# Check cluster is accessible
oc cluster-info

# Verify prerequisites (includes user and group checks)
./common/check-prerequisites.sh
```

**If groups not yet created:**
```bash
# One-time group setup
oc adm groups new dba-users 2>/dev/null || echo "Group exists"
oc adm groups add-users dba-users dba dba-dev dba-test dba-prod

# Verify
oc get group dba-users -o yaml
```

---

## Step 1: Install PostgreSQL Operator (Cluster Admin)

**Time:** ~5 minutes

```bash
# Add Helm repositories
helm repo add postgres-operator-charts https://opensource.zalando.com/postgres-operator/charts/postgres-operator
helm repo add postgres-operator-ui-charts https://opensource.zalando.com/postgres-operator/charts/postgres-operator-ui
helm repo update

# Install operator
helm install postgres-operator postgres-operator-charts/postgres-operator \
  -n postgres-operator \
  --create-namespace \
  --set configGeneral.kubernetes_use_configmaps=true \
  --set configKubernetes.enable_cross_namespace_secret=true \
  --set configGeneral.docker_image="ghcr.io/zalando/spilo-16:3.3-p3"

# Configure OpenShift SCC for operator
oc adm policy add-scc-to-user anyuid -z postgres-operator -n postgres-operator

# Restart operator to apply SCC
oc rollout restart deployment/postgres-operator -n postgres-operator

# Wait for operator to be ready
oc wait --for=condition=ready pod -l app.kubernetes.io/name=postgres-operator \
  -n postgres-operator --timeout=300s

# Install UI
helm install postgres-operator-ui postgres-operator-ui-charts/postgres-operator-ui \
  -n postgres-operator \
  --set envs.targetNamespace="" \
  --set envs.operatorApiUrl="http://postgres-operator:8080"
```

**Verify:**
```bash
oc get pods -n postgres-operator
# Should see operator and UI pods Running
```

---

## Step 2: Setup RBAC (Cluster Admin)

**Time:** ~2 minutes

```bash
# Create namespaces and namespace-level RBAC with Kustomize overlays
oc apply -k helm/overlays/dev/
oc apply -k helm/overlays/test/
oc apply -k helm/overlays/prod/

# Setup cluster-level RBAC
# Note: This applies Group YAML and automatically runs 'oc adm groups add-users'
./common/setup-dba-rbac.sh

# OR manually:
# oc apply -f helm/rbac/dba-users-group-definition.yaml  # Create dba-users group first
# oc apply -f helm/rbac/postgres-user-role.yaml
# oc apply -f helm/rbac/master-dba.yaml
# oc apply -f helm/rbac/master-dba-ui-access.yaml
# oc apply -f helm/base/dba-users-group.yaml  # Cross-namespace read RoleBindings
# oc apply -f helm/rbac/secops.yaml
# oc adm groups add-users dba-users dba dba-dev dba-test dba-prod  # Register users
```

**Verify:**
```bash
# Check namespaces created
oc get namespaces | grep dba-

# Check RBAC
oc get rolebindings -n dba-dev
oc get clusterrolebinding | grep dba

# Test permissions
oc auth can-i create postgresql -n dba-dev --as=dba-dev
# Should show: yes
```

---

## Step 3: Deploy Database as DBA User

**Time:** ~3 minutes

```bash
# Set environment variables
export OCP_URL=$(oc whoami --show-server)  # Dynamically get current cluster API URL
export DBA_USER="dba"
export DBA_PASSWORD="Redhat123p@ssword"
export ENVIRONMENT="dev"

# Login as dba-dev user
oc login $OCP_URL --username=${DBA_USER}-${ENVIRONMENT} --password="$DBA_PASSWORD"

# Deploy database cluster
oc apply -f helm/overlays/$ENVIRONMENT/*-cluster.yaml

# Watch deployment
oc get postgresql -n dba-dev -w
```

**Verify:**
```bash
# Check cluster status
oc get postgresql -n dba-dev
# STATUS should show "Running" after ~2 min

# Check pods
oc get pods -n dba-dev
# Should see 2 postgres pods Running

# Get credentials
./common/get-credentials.sh dev-cluster dba-dev
```

---

## Step 4: Test RBAC and Namespace Isolation

**Time:** ~2 minutes

```bash
# As dba-dev, can READ all dba-* namespaces (via dba-users group)
oc get postgresql -n dba-dev   # Works
oc get postgresql -n dba-test  # Works
oc get postgresql -n dba-prod  # Works

# Test permissions using can-i
echo "=== Testing dba-dev permissions ==="
oc auth can-i get postgresql -n dba-dev      # yes - can read own namespace
oc auth can-i create postgresql -n dba-dev   # yes - can write own namespace
oc auth can-i delete postgresql -n dba-dev   # yes - can delete own namespace

echo ""
echo "=== Testing cross-namespace read (should work) ==="
oc auth can-i get postgresql -n dba-test     # yes - can read other namespaces
oc auth can-i get postgresql -n dba-prod     # yes - can read other namespaces

echo ""
echo "=== Testing cross-namespace write (should be forbidden) ==="
oc auth can-i create postgresql -n dba-test  # no - cannot write to test
oc auth can-i delete postgresql -n dba-test  # no - cannot delete in test
oc auth can-i create postgresql -n dba-prod  # no - cannot write to prod

# Login as master DBA - has full access everywhere
oc login $OCP_URL --username=dba --password="$DBA_PASSWORD"

echo ""
echo "=== Testing master DBA permissions ==="
oc auth can-i create postgresql -n dba-dev   # yes - full access
oc auth can-i create postgresql -n dba-test  # yes - full access
oc auth can-i create postgresql -n dba-prod  # yes - full access
```

**Key Point:** Environment DBAs have read access to all dba-* namespaces (via dba-users group membership) but can only write to their own namespace.

---

## Step 5: Access PostgreSQL UI

**Time:** ~1 minute

```bash
# Port-forward to UI
./common/access-ui.sh

# Open in browser
open http://localhost:8081

# Show:
# - All PostgreSQL clusters
# - Cluster details
# - Logs
# - Configuration
```

---

## Step 6: Verify Everything

**Time:** ~2 minutes

```bash
# Run full verification
./common/verify-installation.sh

# Show all checks passing:
# Infrastructure (Operator, UI, CRDs, SCC)
# Namespaces (all dba-* namespaces)
# RBAC (all roles and bindings)
# User permissions (all users tested)
# Namespace isolation (verified)
# Group access (dba-users group)
```

---

## Step 7: Restrict Operator to Single Namespace (Optional)

**Time:** ~3 minutes

**Objective:** Demonstrate transitioning from cluster-wide to single-namespace operator watching.

**Why?** In production, you may want to limit the operator to watch only a single namespace for:
- Better resource isolation
- Reduced RBAC scope
- Prevention of accidental cluster creation in wrong namespaces
- Compliance requirements

**Important Limitation:** The operator only supports watching:
- A **single specific namespace**, OR
- **All namespaces** (`*`)

It does NOT support watching multiple specific namespaces (e.g., `dba-dev,dba-test,dba-prod` will fail).

### Current State: Cluster-Wide

```bash
# Check current operator configuration
oc get operatorconfigurations.acid.zalan.do postgres-operator -n postgres-operator \
  -o jsonpath='{.configuration.kubernetes.watched_namespace}'
# Shows: * (all namespaces)

# Verify via deployment env var
oc get deployment postgres-operator -n postgres-operator \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="WATCHED_NAMESPACE")].value}'
# Shows: * or empty (means all)
```

### Transition to Single-Namespace

```bash
# Update to watch only dba-dev namespace
# LIMITATION: Operator only supports single namespace OR all namespaces (*)
# Default if unset: "*" (all namespaces)
helm upgrade postgres-operator postgres-operator-charts/postgres-operator \
  -n postgres-operator \
  --reuse-values \
  --set 'configKubernetes.watched_namespace=dba-dev'

# Wait for operator to restart
oc rollout status deployment/postgres-operator -n postgres-operator

# Verify the change
echo "=== Deployment WATCHED_NAMESPACE env var ==="
oc get deployment postgres-operator -n postgres-operator \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="WATCHED_NAMESPACE")].value}'
# Shows: dba-dev

# Check operator logs to confirm
oc logs -n postgres-operator deployment/postgres-operator --tail=20 | grep -i "watch"
```

### Test the Restriction

```bash
# Try creating a PostgreSQL cluster in a non-watched namespace
oc create namespace test-restricted 2>/dev/null || echo "Namespace exists"

# Create a test cluster
cat <<EOF | oc apply -f -
apiVersion: "acid.zalan.do/v1"
kind: postgresql
metadata:
  name: test-cluster
  namespace: test-restricted
spec:
  teamId: "test-team"
  numberOfInstances: 1
  volume:
    size: 1Gi
  postgresql:
    version: "16"
  resources:
    requests:
      cpu: 100m
      memory: 250Mi
    limits:
      cpu: 500m
      memory: 500Mi
EOF

# Wait a moment and check - operator will NOT reconcile this
sleep 10
oc get postgresql test-cluster -n test-restricted
# Status will show: Operator not managing this cluster

# Check operator logs - no activity for this cluster
oc logs -n postgres-operator deployment/postgres-operator --tail=50 | grep -i "test-restricted"
# No logs (operator ignores this namespace)

# Verify existing clusters in watched namespace still work
oc get postgresql -n dba-dev
# Should show Running status

# Verify clusters in NON-watched namespaces are ignored
oc get postgresql -n dba-test
oc get postgresql -n dba-prod
# Status will not update (operator ignoring these namespaces)

# Cleanup test
oc delete postgresql test-cluster -n test-restricted
oc delete namespace test-restricted
```

### Revert to Cluster-Wide (Optional)

```bash
# Switch back to watching all namespaces (default behavior)
helm upgrade postgres-operator postgres-operator-charts/postgres-operator \
  -n postgres-operator \
  --reuse-values \
  --set 'configKubernetes.watched_namespace=*'

# Verify
oc get deployment postgres-operator -n postgres-operator \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="WATCHED_NAMESPACE")].value}'
# Shows: *
```

**Key Points:**
- Existing PostgreSQL clusters continue running during the transition
- Operator only reconciles changes in the watched namespace
- Clusters in non-watched namespaces will not receive updates from operator
- RBAC permissions remain unchanged (this only affects operator behavior)
- **Limitation:** Operator only supports single namespace OR all namespaces (`*`)
- For multi-tenant with separate namespaces, you must use `watched_namespace: "*"` (default)
- Default value if unset: `"*"` (watches all namespaces)


---

## Step 8: Deploy Frontend Application (Optional)

**Time:** ~3 minutes

**Objective:** Deploy a Go web frontend that connects to the PostgreSQL databases.

The frontend is included in the database Kustomize overlays, so it was already deployed
in Step 3. You just need to trigger the first build.

### Trigger Builds

```bash
# Start builds (the BuildConfig was created with the database overlay)
oc start-build frontend -n dba-dev --follow
oc start-build frontend -n dba-test
oc start-build frontend -n dba-prod
```

### Access Frontend

```bash
# Get routes
oc get route frontend -n dba-dev -o jsonpath='{.spec.host}'
oc get route frontend -n dba-test -o jsonpath='{.spec.host}'
oc get route frontend -n dba-prod -o jsonpath='{.spec.host}'
```

The frontend shows database connection status, PostgreSQL version, and a simple notes CRUD interface.
No separate namespaces or credential copying needed -- credentials come directly from operator-created secrets.

---

## Next Steps

- **Compare Methods:** [DEMO-COMPARISON.md](DEMO-COMPARISON.md) - See how GitOps differs
- **Try GitOps:** [DEMO-GITOPS.md](DEMO-GITOPS.md) - Automated deployment
- **Troubleshooting:** [DEMO-TROUBLESHOOTING.md](DEMO-TROUBLESHOOTING.md) - Common issues
- **Cleanup:** Run `./cleanup.sh` when done

---

## Quick Reference

```bash
# One-click install (automates all steps)
./install-helm-demo.sh

# Verify installation
./common/verify-installation.sh

# Access UI
./common/access-ui.sh

# Get credentials
./common/get-credentials.sh <cluster-name> <namespace>

# Show all databases
./common/show-all-databases.sh

# Cleanup
./cleanup.sh
```

---

[← Back to Index](DEMO.md) | [Compare Methods →](DEMO-COMPARISON.md) | [Try GitOps →](DEMO-GITOPS.md)
