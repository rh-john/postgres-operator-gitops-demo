# Part 2: GitOps Deployment

Automated deployment with ArgoCD - demonstrate modern GitOps workflows.

**Time:** ~15 minutes | [← Back to Index](DEMO.md) | [Compare Methods →](DEMO-COMPARISON.md)

---

## Overview

**Objective:** Same deployment but fully automated with ArgoCD.

**Steps:**
1. Install OpenShift GitOps (ArgoCD)
2. Deploy operator and RBAC via app-of-apps
3. Deploy databases with auto-sync
4. Demonstrate drift detection and self-healing
5. Show manual sync for production
6. Deploy frontend web app connected to databases (optional)

**Why This Method?**
- Automated deployments from Git
- Self-healing (drift detection and correction)
- Full audit trail (Git + ArgoCD history)
- Production-ready with approval workflows
- Scalable for multiple teams/environments

---

## Prerequisites

```bash
# Cleanup Helm deployment first (optional)
./cleanup.sh

# Login as cluster-admin
oc login --username=cluster-admin --password='Redhat123p@ssword'
```

**Note:** See [docs/PREREQUISITES.md](docs/PREREQUISITES.md) for complete prerequisites including user and group creation.

---

## Step 1: Install OpenShift GitOps (Cluster Admin)

**Time:** ~3 minutes

```bash
# Install OpenShift GitOps operator
./common/install-openshift-gitops.sh

# Grant ArgoCD permissions
oc create clusterrolebinding argocd-admin \
  --clusterrole=cluster-admin \
  --serviceaccount=openshift-gitops:openshift-gitops-argocd-application-controller

# Configure OpenShift OAuth for ArgoCD
./common/configure-argocd-oauth.sh

# Get ArgoCD URL
oc get route openshift-gitops-server -n openshift-gitops \
  -o jsonpath='{.spec.host}'
```

**Login to ArgoCD UI:**
```bash
# Open ArgoCD URL in browser
# Click: "LOG IN VIA OPENSHIFT"
# Login with OpenShift credentials:
#   - Master DBA: dba / Redhat123p@ssword
#   - Dev DBA:    dba-dev / Redhat123p@ssword
#   - Test DBA:   dba-test / Redhat123p@ssword
#   - Prod DBA:   dba-prod / Redhat123p@ssword
#   - SecOps:     secops / Redhat123p@ssword

# Each user sees only their applications!
```

---

## Step 2: Deploy Operator Infrastructure (Cluster Admin)

**Time:** ~5 minutes

**What this deploys:**
- PostgreSQL operator
- PostgreSQL UI
- Cluster-wide RBAC
- Team namespaces
- **NOT databases** (those come in Step 4)

```bash
# Deploy app-of-apps (creates operator and RBAC automatically)
oc apply -f gitops/cluster-config/app-of-apps.yaml

# Watch applications
oc get applications -n openshift-gitops

# Wait for sync (watch status)
oc get application cluster-config -n openshift-gitops -w
# Ctrl+C when STATUS shows "Synced" and HEALTH shows "Healthy"

# Should see multiple apps: postgres-operator, postgres-ui, rbac-cluster, team-namespaces
oc get applications -n openshift-gitops | grep -E "(postgres|rbac|team)"
```

**Show in ArgoCD UI:**
- Application tree (cluster-config → child apps)
- Sync status for each component
- Resource health
- Sync waves in action

**Verify operator:**
```bash
oc get pods -n postgres-operator
# Should see operator and UI running

# Verify team namespaces created
oc get namespaces | grep dba-
# Should show: dba-dev, dba-test, dba-prod

# No databases yet!
oc get postgresql --all-namespaces
# Should show: No resources found
```

---

## Step 3: Verify RBAC (Cluster Admin)

**Time:** ~1 minute

**RBAC is automatically deployed - no manual steps!**

```bash
# Verify RBAC app deployed
oc get applications -n openshift-gitops rbac-cluster

# Check ClusterRoleBindings
oc get clusterrolebinding | grep dba

# Check DBA users group
oc get group dba-users -o yaml
```

**IMPORTANT: One-time group registration** (if not already done in prerequisites):
```bash
# ArgoCD creates the Group resource, but OpenShift requires explicit user registration
oc adm groups add-users dba-users dba dba-dev dba-test dba-prod

# Verify
oc get group dba-users -o yaml | grep -A5 "^users:"
```

**What was deployed automatically:**
- Master DBA cluster-wide permissions
- GitOps RBAC (ArgoCD Application management)
- DBA users group (read-only to all namespaces)
- SecOps monitoring access

---

## Step 4: Deploy Databases (Master DBA)

**Time:** ~3 minutes

```bash
# Login as master DBA
export OCP_URL=$(oc whoami --show-server)
export DBA_PASSWORD="Redhat123p@ssword"

oc login $OCP_URL --username=dba --password="$DBA_PASSWORD"

# Deploy all team database applications
oc apply -f gitops/cluster-config/team-dev-app.yaml
oc apply -f gitops/cluster-config/team-test-app.yaml
oc apply -f gitops/cluster-config/team-prod-app.yaml

# Watch applications
oc get applications -A | grep postgres

# Check PostgreSQL clusters
oc get postgresql --all-namespaces
```

**Show in ArgoCD UI:**
- Applications in separate namespaces (dba-dev, dba-test, dba-prod)
- Auto-sync happening in real-time
- PostgreSQL clusters being created

---

## Step 5: Demo GitOps Features

**Time:** ~5 minutes

### A. Auto-Sync

```bash
# Edit cluster size
vim gitops/apps/databases/overlays/dev/simple-cluster.yaml
# Change: numberOfInstances: 1 → 2

git add .
git commit -m "Scale dev cluster to 2 instances"
git push

# Watch ArgoCD auto-sync
oc get application dev-postgres -n dba-dev -w
```

**Show:** ArgoCD detects change and syncs automatically

### B. Drift Detection & Self-Healing

```bash
# Make manual change (simulate drift)
oc scale postgresql dev-cluster -n dba-dev --replicas=1

# Watch ArgoCD detect drift
oc get application dev-postgres -n dba-dev
# STATUS: OutOfSync

# Auto-healing kicks in (watch it revert)
# ArgoCD reverts to 2 replicas
```

**Show:** Self-healing in action

### C. Manual Sync (Production)

```bash
# Check prod sync policy (manual)
oc get application prod-postgres -n dba-prod -o jsonpath='{.spec.syncPolicy}'
# Should be empty (manual sync required)

# Make change in Git
vim gitops/apps/databases/overlays/prod/ha-cluster.yaml
git add . && git commit -m "Update prod" && git push

# Show it waits for approval
oc get application prod-postgres -n dba-prod
# STATUS: OutOfSync (but not auto-syncing)

# Manual sync required
oc patch application prod-postgres -n dba-prod --type merge \
  -p '{"operation":{"initiatedBy":{"username":"dba"},"sync":{"revision":"main"}}}'
```

**Show:** Production requires explicit approval

---

## Step 6: Demo Cross-Environment Visibility

**Time:** ~2 minutes

```bash
# Login as dba-test
oc login $OCP_URL --username=dba-test --password="$DBA_PASSWORD"

# Can view all environments (read-only)
oc get postgresql -n dba-dev   # Works (read-only)
oc get postgresql -n dba-test  # Works (read/write)
oc get postgresql -n dba-prod  # Works (read-only)

# Can create in own namespace
oc apply -f gitops/apps/databases/overlays/test/test-cluster.yaml

# But cannot create in other namespaces
# (Try creating in dba-dev - will be forbidden)
```

**Show:** Environment DBAs have visibility but write isolation

---

## Step 7: Full Verification

**Time:** ~2 minutes

```bash
# Login as cluster-admin
oc login --username=cluster-admin --password='Redhat123p@ssword'

# Run full verification
./common/verify-installation.sh

# Show all checks passing
```

---

## Step 8: Restrict Operator to Single Namespace (Optional)

**Time:** ~5 minutes

**Objective:** GitOps approach to operator namespace restriction.

**IMPORTANT LIMITATION:** The operator only supports:
- A **single specific namespace**, OR
- The wildcard `*` for all namespaces

### Update Configuration

```bash
# Edit helm-values.yaml
vim gitops/cluster-config/postgres-operator/helm-values.yaml
```

Add or update:
```yaml
configKubernetes:
  watched_namespace: "dba-dev"  # Single namespace only
```

### Commit and Let ArgoCD Sync

```bash
# Commit the change
git add gitops/cluster-config/postgres-operator/helm-values.yaml
git commit -m "Restrict operator to dba-dev namespace"
git push

# ArgoCD detects and syncs automatically
# Monitor in UI or CLI
oc get application postgres-operator -n openshift-gitops -w
```

### Verify

```bash
# Check WATCHED_NAMESPACE env var
oc get deployment postgres-operator -n postgres-operator \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="WATCHED_NAMESPACE")].value}'
# Shows: dba-dev
```

### Revert (GitOps Way)

```bash
# Change back to "*" in helm-values.yaml
# Commit and push
# ArgoCD syncs automatically

# Full audit trail in Git!
```

---

## Step 9: Frontend Web App

**Time:** ~3 minutes

The frontend web app is deployed automatically as part of the database applications (Step 4/6).
Each environment gets a Go web frontend that connects to its local PostgreSQL database.

### Trigger Builds

The BuildConfig is created by ArgoCD, but the first build needs to be started manually:

```bash
# Start builds in each namespace
oc start-build frontend -n dba-dev --follow
oc start-build frontend -n dba-test
oc start-build frontend -n dba-prod

# Watch deployments
oc get pods -n dba-dev -l app=frontend -w
```

### Access Frontend

```bash
# Get routes
oc get route frontend -n dba-dev -o jsonpath='{.spec.host}'
oc get route frontend -n dba-test -o jsonpath='{.spec.host}'
oc get route frontend -n dba-prod -o jsonpath='{.spec.host}'

# Open in browser - shows:
#   - Database connection status
#   - PostgreSQL version
#   - Simple CRUD operations (create table, add notes)
```

**Show in ArgoCD UI:**
- Frontend resources visible alongside database resources in the same app
- No separate namespaces or credential management needed
- Credentials come directly from operator-created secrets

---

## Next Steps

- **Compare Methods:** [DEMO-COMPARISON.md](DEMO-COMPARISON.md) - Helm vs GitOps
- **Try Helm:** [DEMO-HELM.md](DEMO-HELM.md) - Manual deployment
- **Troubleshooting:** [DEMO-TROUBLESHOOTING.md](DEMO-TROUBLESHOOTING.md) - Common issues
- **Cleanup:** Run `./cleanup.sh` when done

---

## Quick Reference

```bash
# One-click install (automates all steps)
./install-gitops-demo.sh

# Verify installation
./common/verify-installation.sh

# Get ArgoCD URL
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'

# Force application sync
oc patch application <app-name> -n <namespace> --type merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'

# Cleanup
./cleanup.sh
```

---

[← Back to Index](DEMO.md) | [Compare Methods →](DEMO-COMPARISON.md) | [Try Helm →](DEMO-HELM.md)
