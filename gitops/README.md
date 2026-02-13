# GitOps Configuration

Declarative PostgreSQL configurations for ArgoCD.

## Structure

```
gitops/
├── cluster-config/          # Infrastructure (cluster-admin)
│   ├── app-of-apps.yaml
│   ├── postgres-operator-app.yaml
│   ├── postgres-ui-app.yaml
│   └── rbac-cluster-app.yaml
│
└── apps/databases/          # Database definitions
    ├── base/
    └── overlays/
        ├── dev/
        ├── test/
        └── prod/
```

## Deploy

### 1. Install GitOps (Cluster Admin)

```bash
# Install OpenShift GitOps
./common/install-openshift-gitops.sh

# Configure OAuth
./common/configure-argocd-oauth.sh
```

### 2. Deploy Infrastructure

```bash
# Deploy operator and RBAC
oc apply -f gitops/cluster-config/app-of-apps.yaml

# Wait for sync
oc get application cluster-config -n openshift-gitops -w
```

### 3. Deploy Databases

```bash
# Deploy team applications
oc apply -f gitops/cluster-config/team-dev-app.yaml
oc apply -f gitops/cluster-config/team-test-app.yaml
oc apply -f gitops/cluster-config/team-prod-app.yaml
```

## Access ArgoCD

```bash
# Get URL
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'

# Login with OpenShift OAuth
# Each user sees only their applications
```

## See Also

- **[DEMO.md](../DEMO.md)** - Complete deployment guide
- **[docs/README.md](../docs/README.md)** - Quick reference
