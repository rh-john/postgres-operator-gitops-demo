# Application Configuration

PostgreSQL database clusters managed via GitOps using ArgoCD.

## Structure

```
apps/
├── databases/                     # PostgreSQL cluster definitions
│   ├── base/                      # Common resources (RBAC, network policies, SCC)
│   │   ├── kustomization.yaml
│   │   ├── dba-users-group.yaml   # Group definition for DBA users
│   │   ├── scc-rolebinding.yaml   # OpenShift SCC binding for postgres-pod
│   │   ├── networkpolicies.yaml   # Network policies for PostgreSQL
│   │   └── application-manager-role.yaml
│   └── overlays/                  # Environment-specific clusters
│       ├── dev/                   # Development environment
│       │   ├── kustomization.yaml
│       │   ├── simple-cluster.yaml        # Single-instance PostgreSQL
│       │   ├── namespace-rbac.yaml        # DBA RBAC for dev namespace
│       │   └── application-manager-binding.yaml
│       ├── test/                  # Test environment
│       │   ├── kustomization.yaml
│       │   ├── test-cluster.yaml          # HA PostgreSQL cluster
│       │   ├── namespace-rbac.yaml
│       │   └── application-manager-binding.yaml
│       └── prod/                  # Production environment
│           ├── kustomization.yaml
│           ├── ha-cluster.yaml            # HA PostgreSQL cluster
│           ├── namespace-rbac.yaml
│           └── application-manager-binding.yaml
└── README.md                      # This file
```

## Overview

The `databases/` directory contains PostgreSQL cluster definitions organized using Kustomize:

- **Base:** Common resources shared across all environments
- **Overlays:** Environment-specific PostgreSQL clusters (dev, test, prod)

Each overlay includes:
1. PostgreSQL cluster definition
2. Namespace-specific RBAC for DBA users
3. Application manager role binding (for ArgoCD)

## Deployment

These resources are deployed via ArgoCD Applications defined in `../cluster-config/`:
- `team-dev-app.yaml` - Points to `databases/overlays/dev/`
- `team-test-app.yaml` - Points to `databases/overlays/test/`
- `team-prod-app.yaml` - Points to `databases/overlays/prod/`

See `../cluster-config/README.md` for details on the ArgoCD Application definitions.

## Making Changes

### As a DBA User

1. **Edit the database definition:**
   ```bash
   # For dev environment
   vim databases/overlays/dev/simple-cluster.yaml
   
   # For test environment
   vim databases/overlays/test/test-cluster.yaml
   
   # For prod environment (create PR)
   git checkout -b prod-update
   vim databases/overlays/prod/ha-cluster.yaml
   ```

2. **Commit and push:**
   ```bash
   git add .
   git commit -m "Update PostgreSQL cluster configuration"
   git push
   ```

3. **ArgoCD syncs automatically:**
   - Dev and Test environments: Auto-sync enabled
   - Prod environment: Manual sync required (cluster-admin only)

### Adding a New Database

1. **Create new cluster definition:**
   ```bash
   cat > databases/overlays/dev/myapp-cluster.yaml <<EOF
   apiVersion: acid.zalan.do/v1
   kind: postgresql
   metadata:
     name: myapp-db
     namespace: dba-dev
     annotations:
       argocd.argoproj.io/sync-wave: "2"
   spec:
     teamId: "dev-team"
     numberOfInstances: 1
     postgresql:
       version: "16"
     volume:
       size: 10Gi
     users:
       myapp: []
     databases:
       myappdb: myapp
     resources:
       requests:
         cpu: 100m
         memory: 250Mi
       limits:
         cpu: 500m
         memory: 500Mi
   EOF
   ```

2. **Add to kustomization:**
   ```bash
   # Edit databases/overlays/dev/kustomization.yaml
   # Add under resources:
   #   - myapp-cluster.yaml
   ```

3. **Commit and push:**
   ```bash
   git add databases/overlays/dev/
   git commit -m "Add myapp database cluster"
   git push
   ```

4. **ArgoCD deploys automatically** (for dev/test) or after manual sync (for prod)

## Sync Policies

### Dev & Test (Auto-Sync)
- Changes deploy automatically when pushed to Git
- Self-healing: Manual changes are reverted
- Pruning: Resources removed from Git are deleted from cluster

### Prod (Manual Sync)
- Changes require explicit sync by cluster-admin
- Changes pushed to Git remain "OutOfSync" until manually synced
- Enables review before deployment

## RBAC Integration

The database applications work with cluster-level RBAC defined in `../cluster-config/rbac-cluster/`:

- **DBA users** can create/manage PostgreSQL clusters in their assigned namespace
- **Master DBAs** can manage PostgreSQL across all namespaces
- **SecOps** has read-only access to all namespaces

Each overlay includes `namespace-rbac.yaml` that creates namespace-specific RoleBindings.

## References

- [DEMO.md](../../DEMO.md) - Complete walkthrough
- [ArgoCD Applications](https://argo-cd.readthedocs.io/en/stable/user-guide/applications/)
- [Kustomize](https://kustomize.io/)
- [Zalando PostgreSQL Operator](https://github.com/zalando/postgres-operator)
