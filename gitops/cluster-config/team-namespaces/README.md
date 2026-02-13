# Team Namespace Management

This directory manages team namespaces for PostgreSQL database deployments.

## Purpose

Centralizes namespace creation and configuration for database teams:
- `dba-dev` - Development team
- `dba-test` - Test team
- `dba-prod` - Production team

## Why Separate Application?

1. **Lifecycle Management**: Namespaces are created before Applications
2. **GitOps Principle**: Everything in Git, including namespaces
3. **Onboarding**: Add new team by editing `namespaces.yaml`
4. **Audit Trail**: Track namespace changes through Git history

## Expected Behavior

**Status: "OutOfSync" is NORMAL**

The `team-namespaces` app shows "OutOfSync" with orphaned resource warnings because:
- This app manages only Namespace objects
- ArgoCD detects all resources inside the namespaces (pods, services, etc.)
- Those resources are managed by team Applications (dev-postgres, test-postgres, prod-postgres)

**This is expected and not an error.** The namespaces themselves are correctly managed.

**Health: "Healthy"** indicates the namespaces exist and are accessible.

## Adding a New Team

To onboard a new team:

```yaml
# Add to namespaces.yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: dba-staging
  labels:
    name: dba-staging
    team: staging-team
    environment: staging
    managed-by: gitops
```

Commit and push - ArgoCD will create the namespace automatically.

## Namespace Labels

Each namespace includes:
- `name`: Namespace name
- `team`: Team identifier
- `environment`: Environment type (development/testing/production)
- `managed-by`: Management method (gitops)
- `app.kubernetes.io/managed-by`: Managed by GitOps
- `app.kubernetes.io/part-of`: Part of PostgreSQL operator

## Sync Wave

`argocd.argoproj.io/sync-wave: "-1"` ensures namespaces are created **before** other infrastructure components.

## Manual Namespace Creation (Not Recommended)

If you need to create namespaces manually (e.g., for testing):

```bash
oc create namespace dba-dev
oc create namespace dba-test
oc create namespace dba-prod
```

But the GitOps approach (this app) is preferred for production.
