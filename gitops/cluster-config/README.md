# Cluster Configuration

Cluster-wide operator and infrastructure components managed via app-of-apps pattern.

## Structure

```
cluster-config/
├── app-of-apps.yaml              # App-of-apps managing all infrastructure
├── kustomization.yaml            # Kustomize configuration
├── argocd-projects.yaml          # ArgoCD AppProject definitions
├── argocd-cm-config.yaml         # ArgoCD ConfigMap config
├── argocd-oauth-config.yaml      # ArgoCD OAuth configuration
├── postgres-operator-app.yaml    # PostgreSQL operator ArgoCD Application
├── postgres-ui-app.yaml          # PostgreSQL UI ArgoCD Application
├── rbac-cluster-app.yaml         # RBAC ArgoCD Application
├── team-namespaces-app.yaml      # Namespace creation ArgoCD Application
├── team-dev-app.yaml             # Dev database ArgoCD Application
├── team-test-app.yaml            # Test database ArgoCD Application
├── team-prod-app.yaml            # Prod database ArgoCD Application
├── postgres-operator/            # Operator Helm values
│   └── helm-values.yaml          # Helm values for operator chart
├── postgres-ui/                  # UI Helm values
│   └── helm-values.yaml          # Helm values for UI chart
├── team-namespaces/              # Namespace definitions
│   ├── namespaces.yaml           # dba-dev, dba-test, dba-prod namespaces
│   └── kustomization.yaml
└── rbac-cluster/                 # ALL RBAC manifests
    ├── dba-users-group-definition.yaml  # Create dba-users group
    ├── postgres-user-role.yaml          # PostgreSQL ClusterRole
    ├── master-dba.yaml                  # Master DBA cluster-wide
    ├── dba-ui-access.yaml               # UI port-forward access
    ├── secops.yaml                      # SecOps monitoring
    ├── gitops-master-dba.yaml           # GitOps: master DBA
    ├── gitops-dba-dev.yaml              # GitOps: dev team
    ├── gitops-dba-test.yaml             # GitOps: test team
    ├── gitops-dba-prod.yaml             # GitOps: prod team
    ├── operator-scc-rolebinding.yaml    # OpenShift SCC
    └── kustomization.yaml
```

## Components

### Postgres Operator App
- Creates `postgres-operator` namespace
- Deploys PostgreSQL operator (deployment + config)
- Deploys ClusterRole for postgres-user-role
- Configures SCC for operator and PostgreSQL pods
- **Does NOT create database namespaces**

### Postgres UI App
- Deploys UI deployment in `postgres-operator` namespace
- Access via port-forward (no OpenShift Route)
- Read-only access to all clusters

### RBAC Cluster App
- Deploys ALL RBAC for the entire platform
- **User Group:**
  - `dba-users` group (members: dba, dba-dev, dba-test, dba-prod)
  - Centralized permission management
- **Cluster-wide RBAC:**
  - Master DBA (`dba` user): Full PostgreSQL management across all namespaces
  - Master DBA: Port-forward access to PostgreSQL Operator UI
  - SecOps (`secops` user): Read-only monitoring
- **GitOps RBAC (openshift-gitops namespace):**
  - Master DBA: Manage all Applications
  - Environment DBAs: Manage their specific Application
- **Namespace-level RBAC (via dba-users group):**
  - Cross-namespace READ access to all `dba-*` namespaces
  - Enables collaboration and troubleshooting across teams

## Deployment

```bash
# Deploy cluster configuration
oc apply -f gitops/cluster-config/app-of-apps.yaml
```

## Independence

- **Operator installation** is completely separate from databases
- **Database apps** create their own namespaces
- **No coupling** - operator has zero knowledge of database apps
- Each can be deployed, updated, or removed independently

## What's Deployed

**cluster-config deploys:**
- PostgreSQL operator (in `postgres-operator` namespace)
- PostgreSQL UI (in `postgres-operator` namespace)
- postgres-user-role ClusterRole (cluster-wide RBAC)
- ALL RBAC (master DBA, GitOps, dba-users group, secops)

**cluster-config does NOT deploy:**
- Database namespaces (created by database apps)
- Database clusters (created by database apps)
