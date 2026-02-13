# Helm Installation

Direct manual deployment using Kustomize overlays.

## Structure

```
helm/
├── base/                    # Shared resources
│   ├── kustomization.yaml
│   ├── networkpolicies.yaml
│   ├── scc-rolebinding.yaml
│   └── dba-users-group.yaml
└── overlays/                # Per-environment
    ├── dev/
    │   ├── kustomization.yaml
    │   ├── namespace.yaml
    │   ├── simple-cluster.yaml
    │   └── frontend.yaml
    ├── test/
    │   ├── kustomization.yaml
    │   ├── namespace.yaml
    │   ├── test-cluster.yaml
    │   └── frontend.yaml
    └── prod/
        ├── kustomization.yaml
        ├── namespace.yaml
        ├── ha-cluster.yaml
        └── frontend.yaml
```

## Prerequisites

- PostgreSQL Operator installed (see DEMO.md)
- OpenShift CLI (`oc`)
- Cluster admin access

## Quick Deploy

```bash
# Dev environment
oc apply -k helm/overlays/dev/

# Test environment
oc apply -k helm/overlays/test/

# Production environment
oc apply -k helm/overlays/prod/
```

## Verify

```bash
# Check clusters
oc get postgresql --all-namespaces

# Check pods
oc get pods -n dba-dev

# Check Patroni status
oc exec dev-cluster-0 -n dba-dev -- patronictl list
```

## Cleanup

```bash
oc delete -k helm/overlays/dev/
oc delete -k helm/overlays/test/
oc delete -k helm/overlays/prod/
```

## See Also

- **[DEMO.md](../DEMO.md)** - Complete deployment guide
- **[gitops/](../gitops/)** - GitOps alternative with ArgoCD
