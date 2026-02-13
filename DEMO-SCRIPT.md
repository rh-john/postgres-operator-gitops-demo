# Demo Script - Presenter Quick Reference

Quick command reference for live demonstrations.

[← Back to Index](DEMO.md)

---

## Pre-Demo Checklist

```bash
# Verify cluster access
oc whoami  # Should show: cluster-admin
oc cluster-info

# Check prerequisites
./common/check-prerequisites.sh

# Verify users exist
oc get users | grep -E "(dba|secops)"

# Verify groups
oc get group dba-users
```

---

## Helm Demo (15 minutes)

### 1. Prerequisites (1 min)

```bash
oc whoami && ./common/check-prerequisites.sh
```

### 2. Install Operator (5 min)

```bash
# Add repos
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

# Configure SCC
oc adm policy add-scc-to-user anyuid -z postgres-operator -n postgres-operator
oc rollout restart deployment/postgres-operator -n postgres-operator

# Install UI
helm install postgres-operator-ui postgres-operator-ui-charts/postgres-operator-ui \
  -n postgres-operator \
  --set envs.targetNamespace="" \
  --set envs.operatorApiUrl="http://postgres-operator:8080"

# Verify
oc get pods -n postgres-operator
```

### 3. Setup RBAC (2 min)

```bash
# Create namespaces and RBAC
oc apply -k helm/overlays/dev/
oc apply -k helm/overlays/test/
oc apply -k helm/overlays/prod/

# Setup cluster-level RBAC
./common/setup-dba-rbac.sh

# Verify
oc get namespaces | grep dba-
oc auth can-i create postgresql -n dba-dev --as=dba-dev
```

### 4. Deploy Database (3 min)

```bash
# Login as dba-dev
export OCP_URL=$(oc whoami --show-server)
oc login $OCP_URL --username=dba-dev --password="Redhat123p@ssword"

# Deploy
oc apply -f helm/overlays/dev/simple-cluster.yaml

# Watch
oc get postgresql -n dba-dev -w
# (Ctrl+C when Running)

# Get credentials
./common/get-credentials.sh dev-cluster dba-dev
```

### 5. Test Isolation (2 min)

```bash
# Show cross-namespace read (works)
oc get postgresql -n dba-test

# Try cross-namespace write (fails)
oc auth can-i create postgresql -n dba-test
# Shows: no

# Login as master DBA
oc login $OCP_URL --username=dba --password="Redhat123p@ssword"

# Show full access
oc get postgresql --all-namespaces
```

### 6. Verify (2 min)

```bash
# Login as cluster-admin
oc login --username=<admin-user> --password='<password>'

# Run verification
./common/verify-installation.sh

# Show UI
./common/access-ui.sh
# Open: http://localhost:8081
```

---

## GitOps Demo (15 minutes)

### 1. Install GitOps (3 min)

```bash
# Install operator
./common/install-openshift-gitops.sh

# Grant permissions
oc create clusterrolebinding argocd-admin \
  --clusterrole=cluster-admin \
  --serviceaccount=openshift-gitops:openshift-gitops-argocd-application-controller

# Configure OAuth
./common/configure-argocd-oauth.sh

# Get URL
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'
```

**Show in browser:** Login via OpenShift

### 2. Deploy Operator + RBAC (5 min)

```bash
# Deploy app-of-apps
oc apply -f gitops/cluster-config/app-of-apps.yaml

# Watch
oc get applications -n openshift-gitops

# Wait for sync
oc get application cluster-config -n openshift-gitops -w
# (Ctrl+C when Synced)

# Verify
oc get pods -n postgres-operator
oc get namespaces | grep dba-
```

**Show in ArgoCD UI:** Application tree, sync status

### 3. Verify RBAC (1 min)

```bash
# Check RBAC app
oc get applications -n openshift-gitops rbac-cluster

# Register users in group
oc adm groups add-users dba-users dba dba-dev dba-test dba-prod

# Verify
oc get group dba-users -o yaml | grep -A5 "^users:"
```

### 4. Deploy Database (3 min)

```bash
# Login as master DBA
export OCP_URL=$(oc whoami --show-server)
oc login $OCP_URL --username=dba --password="Redhat123p@ssword"

# Deploy applications
oc apply -f gitops/cluster-config/team-dev-app.yaml
oc apply -f gitops/cluster-config/team-test-app.yaml
oc apply -f gitops/cluster-config/team-prod-app.yaml

# Watch
oc get applications -A | grep postgres
oc get postgresql --all-namespaces
```

**Show in ArgoCD UI:** Applications syncing in real-time

### 5. Demo GitOps Features (5 min)

**A. Auto-Sync:**
```bash
# Edit cluster
vim gitops/apps/databases/overlays/dev/simple-cluster.yaml
# Change numberOfInstances: 1 → 2

# Commit and push
git add . && git commit -m "Scale dev" && git push

# Watch ArgoCD sync automatically
oc get application dev-postgres -n dba-dev -w
```

**Show in ArgoCD UI:** Auto-sync in action

**B. Drift Detection:**
```bash
# Make manual change
oc scale postgresql dev-cluster -n dba-dev --replicas=1

# Watch ArgoCD detect and fix
oc get application dev-postgres -n dba-dev
# STATUS: OutOfSync → Synced (self-healing)
```

**Show in ArgoCD UI:** Drift detected, self-healing

**C. Manual Sync:**
```bash
# Check prod sync policy
oc get application prod-postgres -n dba-prod -o jsonpath='{.spec.syncPolicy}'
# Empty = manual sync required

# Make change
vim gitops/apps/databases/overlays/prod/ha-cluster.yaml
git commit && git push

# Show OutOfSync (not auto-syncing)
oc get application prod-postgres -n dba-prod

# Manual sync required
```

**Show in ArgoCD UI:** Waiting for approval

### 6. Verify (2 min)

```bash
# Login as cluster-admin
oc login --username=<admin-user> --password='<password>'

# Full verification
./common/verify-installation.sh
```

---

## Talking Points

### Multi-Tenancy
- Environment DBAs: Write to own namespace, read all
- Master DBA: Full access everywhere
- SecOps: Read-only monitoring
- Group-based collaboration via `dba-users` group

### Security
- Namespace isolation enforced by RBAC
- Group membership for cross-environment visibility
- OpenShift SCC integration
- Separation of concerns (operator vs databases)

### Helm Advantages
- Simple and direct
- Full manual control
- Familiar workflow
- Good for learning

### GitOps Advantages
- Automated from Git
- Self-healing (drift detection)
- Full audit trail
- Production-ready
- Scalable

---

## Demo Tips

1. **Keep ArgoCD UI open** during GitOps demo
2. **Use two terminals** - one for commands, one for watching
3. **Pre-create terminal tabs:**
   - Tab 1: cluster-admin
   - Tab 2: dba-dev
   - Tab 3: dba (master)
   - Tab 4: watch commands

4. **Have backup commands ready:**
   ```bash
   # If operator fails
   oc logs -n postgres-operator deployment/postgres-operator

   # If database stuck
   oc describe postgresql dev-cluster -n dba-dev

   # If RBAC fails
   oc auth can-i create postgresql -n dba-dev --as=dba-dev
   ```

5. **Time management:**
   - Prerequisites: 1 min
   - Operator install: 5 min
   - RBAC setup: 2 min
   - Database deploy: 3 min
   - Demo features: 5 min
   - Verification: 2 min
   - **Buffer:** 2 min

---

## Quick Recovery

### Operator not starting
```bash
oc adm policy add-scc-to-user anyuid -z postgres-operator -n postgres-operator
oc rollout restart deployment/postgres-operator -n postgres-operator
```

### Database stuck
```bash
oc describe postgresql <cluster-name> -n <namespace>
oc get events -n <namespace> --sort-by='.lastTimestamp'
```

### RBAC issues
```bash
oc adm groups add-users dba-users dba dba-dev dba-test dba-prod
oc auth can-i create postgresql -n dba-dev --as=dba-dev
```

### ArgoCD not syncing
```bash
oc patch application <app-name> -n <namespace> --type merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'
```

---

## Questions & Answers

**Q: Can Helm and GitOps coexist?**
A: No - choose one per cluster to avoid conflicts.

**Q: Which method for production?**
A: GitOps preferred for automation, audit trails, and self-healing.

**Q: Can I switch later?**
A: Yes - manifests are compatible between methods.

**Q: Why do DBAs need read access to all namespaces?**
A: Collaboration and visibility while maintaining write isolation.

**Q: What if operator crashes?**
A: Existing databases continue running. Fix operator, it will reconcile.

---

## One-Click Commands

```bash
# Helm (full automation)
./install-helm-demo.sh

# GitOps (full automation)
./install-gitops-demo.sh

# Verify
./common/verify-installation.sh

# Cleanup
./cleanup.sh
```

---

[← Back to Index](DEMO.md) | [Troubleshooting →](DEMO-TROUBLESHOOTING.md)
