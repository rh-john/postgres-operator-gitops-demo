# Troubleshooting Guide

Common issues and solutions during demos.

[← Back to Index](DEMO.md)

---

## Quick Fixes

| Issue | Quick Fix |
|-------|-----------|
| Operator not starting | Check SCC: `oc get pods -n postgres-operator` |
| Database stuck | Check events: `oc get events -n <namespace>` |
| Permission denied | Verify RBAC: `oc auth can-i <verb> <resource> --as=<user>` |
| ArgoCD not syncing | Force sync or check application status |
| Group membership missing | Run: `oc adm groups add-users dba-users <users>` |

---

## Operator Issues

### Operator Pod Not Starting

**Symptoms:**
- Operator pod in `CrashLoopBackOff` or `Error` state
- UI not accessible

**Check:**
```bash
# Check pod status
oc get pods -n postgres-operator

# Check logs
oc logs -n postgres-operator deployment/postgres-operator --tail=50

# Check events
oc get events -n postgres-operator --sort-by='.lastTimestamp'
```

**Common Causes:**

1. **Missing SCC:**
```bash
# Verify SCC
oc get rolebinding postgres-operator-anyuid -n postgres-operator

# Fix: Apply SCC
oc adm policy add-scc-to-user anyuid -z postgres-operator -n postgres-operator
oc rollout restart deployment/postgres-operator -n postgres-operator
```

2. **Wrong Configuration:**
```bash
# Check operator configuration
oc get operatorconfigurations.acid.zalan.do postgres-operator -n postgres-operator -o yaml

# Verify kubernetes_use_configmaps is true
```

3. **Resource Limits:**
```bash
# Check if pod is OOMKilled
oc describe pod -n postgres-operator -l app.kubernetes.io/name=postgres-operator
```

---

## Database Issues

### Database Stuck in "Creating" State

**Symptoms:**
- PostgreSQL cluster shows `Creating` status for >5 minutes
- No pods created

**Check:**
```bash
# Check PostgreSQL resource
oc describe postgresql <cluster-name> -n <namespace>

# Check events
oc get events -n <namespace> --sort-by='.lastTimestamp'

# Check operator logs
oc logs -n postgres-operator deployment/postgres-operator --tail=100
```

**Common Causes:**

1. **Missing SCC for postgres-pod:**
```bash
# Check SCC rolebinding
oc get rolebinding postgres-pod-anyuid -n <namespace>

# Fix: Kustomize should have created it, but if missing:
oc adm policy add-scc-to-user anyuid system:serviceaccount:<namespace>:postgres-pod
```

2. **Invalid Configuration:**
```bash
# Check the PostgreSQL spec
oc get postgresql <cluster-name> -n <namespace> -o yaml

# Common issues:
# - Invalid teamId
# - Wrong volume size format
# - Missing required fields
```

3. **Resource Constraints:**
```bash
# Check namespace quota
oc describe resourcequota -n <namespace>

# Check node resources
oc describe nodes | grep -A5 "Allocated resources"
```

### Pods Show "ApiException()" Errors

**Symptoms:**
- Postgres pods running but not ready
- Logs show API exceptions

**Cause:** Patroni trying to use Endpoints instead of ConfigMaps

**Fix:**
```bash
# Verify operator configuration
oc get operatorconfigurations.acid.zalan.do postgres-operator \
  -n postgres-operator -o jsonpath='{.configuration.general.kubernetes_use_configmaps}'
# Should show: true

# If false, operator was installed incorrectly
# Reinstall with: --set configGeneral.kubernetes_use_configmaps=true

# Restart PostgreSQL pods to pick up fix
oc delete pods -l application=spilo -n <namespace>
```

---

## RBAC Issues

### Permission Denied

**Symptoms:**
- User cannot create/view resources
- `oc auth can-i` returns "no"

**Check:**
```bash
# Test specific permission
oc auth can-i get postgresql -n dba-dev --as=dba-dev

# Check rolebindings in namespace
oc get rolebindings -n dba-dev

# Check clusterrolebindings for user
oc get clusterrolebinding | grep dba
```

**Common Causes:**

1. **User not in group:**
```bash
# Check group membership
oc get group dba-users -o yaml

# Fix: Add user to group
oc adm groups add-users dba-users dba-dev
```

2. **RoleBinding missing:**
```bash
# Check if RoleBinding exists
oc get rolebinding postgres-user-binding -n dba-dev

# Fix: Reapply RBAC
oc apply -k helm/overlays/dev/
# or
oc apply -f gitops/apps/databases/overlays/dev/namespace-rbac.yaml
```

3. **Wrong namespace:**
```bash
# Verify user is trying to access correct namespace
# dba-dev can only write to dba-dev (not dba-test or dba-prod)
```

---

## GitOps/ArgoCD Issues

### ArgoCD Application Not Syncing

**Symptoms:**
- Application shows `OutOfSync` but doesn't sync
- Manual changes don't trigger sync

**Check:**
```bash
# Check application status
oc get application <app-name> -n <namespace> -o yaml

# Check ArgoCD logs
oc logs -n openshift-gitops deployment/openshift-gitops-repo-server --tail=50
```

**Common Causes:**

1. **Manual Sync Policy:**
```bash
# Check if application has manual sync
oc get application <app-name> -n <namespace> -o jsonpath='{.spec.syncPolicy}'

# If empty or no automated section, it requires manual sync

# Fix: Manually sync
oc patch application <app-name> -n <namespace> --type merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'
```

2. **Sync Failed:**
```bash
# Check sync status
oc get application <app-name> -n <namespace> -o jsonpath='{.status.operationState}'

# View detailed error
oc describe application <app-name> -n <namespace>
```

3. **Git Repository Access:**
```bash
# Check if ArgoCD can reach Git repo
oc logs -n openshift-gitops deployment/openshift-gitops-application-controller --tail=50 | grep -i "git"
```

### Application Shows "Unknown" Health

**Symptoms:**
- Application health is `Unknown` or `Progressing`
- Resources created but health not updating

**Check:**
```bash
# Check application resources
oc get application <app-name> -n <namespace> -o yaml

# Check if resources have health checks
oc get postgresql <cluster-name> -n <namespace>
```

**Fix:**
- Wait for resources to fully deploy
- PostgreSQL clusters take 2-5 minutes to become `Running`
- Check operator logs for errors

---

## Group Membership Issues

### DBA User Cannot Read Other Namespaces

**Symptoms:**
- dba-dev can create in dba-dev (works)
- dba-dev cannot view dba-test (should work, but doesn't)

**Root Cause:** User not properly registered in `dba-users` group

**Fix:**
```bash
# Check group membership
oc get group dba-users -o yaml

# If user missing from users list, add them
oc adm groups add-users dba-users dba dba-dev dba-test dba-prod

# Verify
oc get group dba-users -o yaml | grep -A10 "^users:"

# Test again
oc auth can-i get postgresql -n dba-test --as=dba-dev
# Should show: yes
```

**Note:** Simply applying the Group YAML is not sufficient. OpenShift requires explicit user registration via `oc adm groups add-users`.

---

## Demo-Specific Issues

### Cluster Credentials Not Found

**Symptoms:**
- `./common/get-credentials.sh` returns "not found"

**Fix:**
```bash
# Wait for cluster to be fully ready
oc get postgresql <cluster-name> -n <namespace>
# STATUS must be "Running"

# Check if secret exists
oc get secret <username>.<cluster-name>.credentials.postgresql.acid.zalan.do \
  -n <namespace>

# If missing, wait longer or check operator logs
```

### UI Not Accessible

**Symptoms:**
- Port-forward fails
- UI shows empty

**Fix:**
```bash
# Check UI pod
oc get pods -n postgres-operator | grep ui

# Restart port-forward
pkill -f "port-forward.*8081"
./common/access-ui.sh

# If UI shows no clusters, check:
# - Operator is running
# - PostgreSQL clusters exist
# - UI is configured correctly (targetNamespace="")
```

---

## Emergency Procedures

### Complete Reset

```bash
# Full cleanup
./cleanup.sh

# Wait for all namespaces to terminate
oc get namespaces | grep Terminating

# If stuck, force remove finalizers (use with caution)
./cleanup.sh --force

# Start fresh
./install-helm-demo.sh
# or
./install-gitops-demo.sh
```

### Operator Unresponsive

```bash
# Restart operator
oc rollout restart deployment/postgres-operator -n postgres-operator

# Wait for new pod
oc wait --for=condition=ready pod \
  -l app.kubernetes.io/name=postgres-operator \
  -n postgres-operator --timeout=60s

# Check logs
oc logs -n postgres-operator deployment/postgres-operator --tail=20
```

---

## Prevention Tips

1. **Always verify prerequisites** before starting:
   ```bash
   ./common/check-prerequisites.sh
   ```

2. **Check operator logs** immediately after installation:
   ```bash
   oc logs -n postgres-operator deployment/postgres-operator --tail=20
   ```

3. **Verify RBAC** before testing as DBA users:
   ```bash
   oc auth can-i create postgresql -n dba-dev --as=dba-dev
   ```

4. **Use verification script** after each major step:
   ```bash
   ./common/verify-installation.sh
   ```

5. **Check ArgoCD UI** during GitOps demos for real-time status

---

## Getting More Help

### Check Documentation
- [README.md](README.md) - Overview
- [docs/README.md](docs/README.md) - Quick reference
- [docs/PREREQUISITES.md](docs/PREREQUISITES.md) - Setup requirements

### Check Logs
```bash
# Operator logs
oc logs -n postgres-operator deployment/postgres-operator --tail=100

# PostgreSQL pod logs
oc logs <pod-name> -n <namespace> -c postgres

# ArgoCD logs
oc logs -n openshift-gitops deployment/openshift-gitops-application-controller --tail=100
```

### Verification
```bash
# Full system verification
./common/verify-installation.sh

# Show all databases
./common/show-all-databases.sh
```

---

[← Back to Index](DEMO.md) | [Helm Guide →](DEMO-HELM.md) | [GitOps Guide →](DEMO-GITOPS.md)
