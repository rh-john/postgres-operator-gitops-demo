# PostgreSQL Operator on OpenShift - Quick Reference

Complete setup guide for running Zalando PostgreSQL Operator on OpenShift with GitOps.

## Quick Start

```bash
# 1. Install OpenShift GitOps
./common/install-openshift-gitops.sh

# 2. Configure OAuth for ArgoCD
./common/configure-argocd-oauth.sh

# 3. Deploy infrastructure
oc apply -f gitops/cluster-config/app-of-apps.yaml

# 4. Wait for operator
oc get application postgres-operator -n openshift-gitops

# 5. Verify clusters
oc get postgresql --all-namespaces
```

## Architecture

- **GitOps**: ArgoCD manages all cluster configuration
- **Multi-tenant**: Separate namespaces for dev/test/prod teams
- **HA**: Patroni with ConfigMap-based leader election (OpenShift requirement)

## Key Differences from Standard Kubernetes

### 1. ConfigMaps for Patroni DCS
**Why**: OpenShift security policies prevent Endpoints-based DCS
**Impact**: Must set `configGeneral.kubernetes_use_configmaps: true` in Helm values
**Details**: Set in `gitops/cluster-config/postgres-operator/helm-values.yaml`

### 2. Security Context Constraints (SCC)
**Why**: OpenShift has stricter pod security
**Impact**: Must grant `anyuid` SCC to postgres-pod ServiceAccount in each namespace
**Files**: `gitops/apps/databases/base/scc-rolebinding.yaml`

## Directory Structure

```
├── gitops/
│   ├── cluster-config/          # Cluster-wide resources
│   │   ├── postgres-operator/   # Helm values
│   │   ├── postgres-operator-app.yaml
│   │   ├── team-dev-app.yaml    # Team applications
│   │   ├── team-test-app.yaml
│   │   └── team-prod-app.yaml
│   └── apps/
│       └── databases/
│           ├── base/            # Shared NetworkPolicies
│           └── overlays/        # Environment-specific configs
│               ├── dev/
│               ├── test/
│               └── prod/
├── common/                      # Shared scripts
│   ├── functions.sh             # Shared functions library
│   ├── verify-installation.sh   # Verification script
│   └── setup-dba-rbac.sh       # RBAC setup
└── docs/
    ├── README.md                # This file
    ├── PREREQUISITES.md         # Prerequisites
    └── RBAC-VISUAL.md           # RBAC diagrams
```

## Common Operations

### Check Cluster Health
```bash
# All clusters
oc get postgresql --all-namespaces

# Specific cluster
oc exec dev-cluster-0 -n dba-dev -- patronictl list
```

### Access Database
```bash
# Get credentials
oc get secret postgres.dev-cluster.credentials.postgresql.acid.zalan.do \
  -n dba-dev -o jsonpath='{.data.password}' | base64 -d

# Port forward
oc port-forward dev-cluster-0 5432:5432 -n dba-dev

# Connect
psql -h localhost -U postgres -d postgres
```

### View All Resources (Including Operator-Created)
```bash
# ArgoCD only tracks the postgresql CR
# To see operator-created resources (pods, secrets, etc.):
oc get all,secret,configmap,pvc -n dba-dev -l cluster-name=dev-cluster
```

**Why?** ArgoCD manages declarative intent (the `postgresql` CR). The operator manages implementation (pods, services, secrets). This is by design - ArgoCD only tracks what you declare, not what the operator creates.

### Restart Cluster
```bash
# Delete pods - StatefulSet recreates them
oc delete pods -l application=spilo -n dba-dev

# Or restart via operator
oc annotate postgresql dev-cluster -n dba-dev \
  force-sync="$(date +%s)" --overwrite
```

## Troubleshooting

### Pods Show "ApiException()" Errors
**Cause**: Patroni trying to use Endpoints instead of ConfigMaps

**Fix**:
```bash
# Verify operator configuration
oc get operatorconfigurations.acid.zalan.do postgres-operator \
  -n postgres-operator -o jsonpath='{.configuration.general.kubernetes_use_configmaps}'
# Should show: true

# If false, the operator was installed without the correct Helm values
# Reinstall or upgrade with: --set configGeneral.kubernetes_use_configmaps=true

# Then restart the PostgreSQL pods
oc delete pods -l application=spilo -n <namespace>
```

### Pods Fail with SCC Error
**Cause**: Missing anyuid SCC RoleBinding

**Fix**:
```bash
# Verify RoleBinding exists
oc get rolebinding postgres-pod-anyuid -n dba-dev

# If missing, sync the application
oc annotate application dev-postgres -n dba-dev \
  argocd.argoproj.io/refresh=hard --overwrite
```

### "Secret not found" Errors
**Cause**: Operator event queue stuck

**Fix**:
```bash
# Restart operator
oc rollout restart deployment/postgres-operator -n postgres-operator

# Wait and check
oc rollout status deployment/postgres-operator -n postgres-operator
```

### Application Shows "OutOfSync"
**Cause**: Operator adds annotations (`force-reconcile`, `force-sync`)

**Expected**: This is normal and ignoreDifferences handles it. If health is "Healthy", ignore the sync status.

## Key Learnings

###  Do's
- Use `commonAnnotations` in kustomizations (safe for metadata)
- Reference LOCAL ServiceAccounts in SCC RoleBindings (namespace-specific)
- Ignore operator-managed annotations in ArgoCD Applications
- Run setup script after operator deployment/upgrade

###  Don'ts  
- Don't use `commonLabels` in kustomizations (breaks RoleBindings and NetworkPolicies)
- Don't add duplicate `spec.version` field to postgresql CRs (operator removes it)
- Don't track operator-created resources in ArgoCD (pods, secrets, etc.)
- Don't ignore metadata fields only in ArgoCD - must ignore `/configuration` entirely

## Multi-Tenant Access

### DBA Users & Group
- **dba-users** (group): Contains all DBA users, provides cross-namespace READ access
- **dba** (master): Full access to all dba-* namespaces + UI port-forward
- **dba-dev**: WRITE to dba-dev, READ to all dba-* (via group)
- **dba-test**: WRITE to dba-test, READ to all dba-* (via group)
- **dba-prod**: WRITE to dba-prod, READ to all dba-* (via group)

See [RBAC-VISUAL.md](RBAC-VISUAL.md) for detailed diagrams.

### Access ArgoCD UI
```bash
# Get URL
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'

# Login with OpenShift credentials
# Each DBA user sees only their team's applications
```

## Documentation

- **PREREQUISITES.md**: Prerequisites and setup
- **README.md** (this file): Quick reference
- **RBAC-VISUAL.md**: RBAC diagrams

## References

- [Zalando PostgreSQL Operator Docs](https://opensource.zalando.com/postgres-operator/)
- [OpenShift GitOps (ArgoCD)](https://docs.openshift.com/gitops/)
- [Patroni Documentation](https://patroni.readthedocs.io/)
