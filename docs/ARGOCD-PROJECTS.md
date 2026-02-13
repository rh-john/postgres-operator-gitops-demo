# ArgoCD Projects for Multi-Tenancy

This document explains the ArgoCD Project structure used for secure multi-tenant PostgreSQL deployments.

## Prerequisites

**Important:** Team namespaces (`dba-dev`, `dba-test`, `dba-prod`) must exist **before** deploying Applications, because:
1. Application CRs are deployed **in** team namespaces (distributed architecture)
2. ArgoCD Projects don't allow managing Namespace resources (security restriction)
3. Namespaces must exist for Applications to be created there

**Solution:** The `team-namespaces` app (part of cluster-config) automatically creates team namespaces:

```bash
# Namespaces are created automatically by ArgoCD
# Verify they exist:
oc get namespaces | grep dba-
# Should show: dba-dev, dba-test, dba-prod

# Check the team-namespaces app
oc get application team-namespaces -n openshift-gitops
```

The `team-namespaces` app uses sync-wave: -1 to ensure namespaces are created before other infrastructure.

## Project Structure

### 1. cluster-infrastructure
**Purpose:** Cluster-wide components managed by cluster-admin

**Allowed Resources:**
- Cluster-scoped: ClusterRoles, ClusterRoleBindings, CRDs
- Namespaces: `postgres-operator`, `openshift-gitops`

**Applications:**
- `cluster-config` (app-of-apps)
- `postgres-operator`
- `postgres-ui`
- `rbac-cluster`

**Access:** Only cluster-admin

### 2. postgres-databases
**Purpose:** Shared project for all team databases

**Allowed Resources:**
- Namespace-scoped only (no cluster resources)
- Limited to: Namespaces, ConfigMaps, Secrets, Services, StatefulSets, postgresql CRs

**Allowed Destinations:**
- Only `dba-*` namespaces

**Applications:**
- `dev-postgres` (in namespace `dba-dev`)
- `test-postgres` (in namespace `dba-test`)
- `prod-postgres` (in namespace `dba-prod`)

**Access:** DBA users via RBAC

### 3. team-dev / team-test / team-prod (Optional)
**Purpose:** Per-team isolation with stricter controls

**Allowed Destinations:**
- `team-dev`: Only `dba-dev` namespace
- `team-test`: Only `dba-test` namespace
- `team-prod`: Only `dba-prod` namespace

**Access:** Team-specific DBAs only

## Benefits of Project Separation

### 1. Security Isolation
```yaml
# Infrastructure can create cluster resources
clusterResourceWhitelist:
  - ClusterRole, ClusterRoleBinding, CRDs

# Teams CANNOT create cluster resources
clusterResourceBlacklist:
  - group: '*'
    kind: '*'
```

### 2. Namespace Boundaries
```yaml
# Infrastructure can access system namespaces
destinations:
  - namespace: postgres-operator
  - namespace: openshift-gitops

# Teams restricted to their namespaces
destinations:
  - namespace: dba-*  # or specific: dba-dev
```

### 3. Resource Type Restrictions
```yaml
# Teams have limited resource types
namespaceResourceWhitelist:
  - ConfigMap, Secret, Service
  - StatefulSet, PVC
  - postgresql (custom resource)
  - NO: Deployments, DaemonSets, Jobs
```

### 4. Audit Trail
- Projects provide clear ownership boundaries
- Easy to track which team deployed what
- Compliance reporting per project

### 5. Prevents Accidental Changes
- `dba-dev` **cannot** create applications in `dba-test`
- Teams **cannot** modify cluster-wide RBAC
- Clear separation between platform and application teams

## Current Configuration

### Using Shared Project (Default)
All team apps use `postgres-databases` project:

```yaml
# gitops/cluster-config/team-dev-app.yaml
spec:
  project: postgres-databases
```

**Pros:**
- Simpler setup
- Master DBA can manage all teams
- Good for demos/small teams

**Cons:**
- Less isolation between teams
- Harder to enforce per-team quotas

### Using Per-Team Projects (Optional)
Each team has dedicated project:

```yaml
# gitops/cluster-config/team-dev-app.yaml
spec:
  project: team-dev  # Strict: only dba-dev namespace
```

**Pros:**
- Maximum isolation
- Per-team resource quotas
- Audit per team
- Security isolation

**Cons:**
- More configuration overhead
- Need separate RBAC per project

## Implementation

### Files Updated

1. **argocd-projects.yaml** (new)
   - Defines all projects
   - Sets resource allow/deny lists
   - Configures destination restrictions

2. **Application manifests:**
   - `app-of-apps.yaml` → `project: cluster-infrastructure`
   - `postgres-operator-app.yaml` → `project: cluster-infrastructure`
   - `postgres-ui-app.yaml` → `project: cluster-infrastructure`
   - `rbac-cluster-app.yaml` → `project: cluster-infrastructure`
   - `team-namespaces-app.yaml` → `project: cluster-infrastructure`
   - `team-dev-app.yaml` → `project: team-dev`
   - `team-test-app.yaml` → `project: team-test`
   - `team-prod-app.yaml` → `project: team-prod`

3. **RBAC files:**
   - `gitops-dba-*.yaml` → Added `appprojects` permissions
   - `argocd-oauth-config.yaml` → Updated policy to reference projects

## Deployment Model: Distributed Applications

**Architecture:**
- **Infrastructure apps** (operator, UI, RBAC) → `openshift-gitops` namespace
- **Team apps** (databases) → **Team namespaces** (`dba-dev`, `dba-test`, `dba-prod`)

**Why Distributed?**
- True namespace isolation
- Teams have full control over their Application CRs
- Can apply namespace-level quotas/policies
- ArgoCD watches multiple namespaces via `sourceNamespaces`

**Configuration:**
```yaml
# argocd-oauth-config.yaml
spec:
  sourceNamespaces:
    - dba-dev
    - dba-test
    - dba-prod
```

Projects are created by cluster-admin during Step 2:

```bash
# Deploy app-of-apps (includes projects)
oc apply -f gitops/cluster-config/app-of-apps.yaml

# Projects are created automatically
oc get appprojects -n openshift-gitops

# Applications will be in team namespaces
oc get applications -A
```

## Verifying Project Isolation

```bash
# List all projects (in openshift-gitops)
oc get appprojects -n openshift-gitops

# Check team-dev project restrictions
oc get appproject team-dev -n openshift-gitops -o yaml

# List applications across all namespaces
oc get applications -A

# Infrastructure apps (openshift-gitops namespace):
#   - cluster-config, postgres-operator, postgres-ui, rbac-cluster

# Team apps (team namespaces):
#   - dba-dev/dev-postgres
#   - dba-test/test-postgres
#   - dba-prod/prod-postgres

# Verify dba-dev can only see their application
oc login --username=dba-dev --password='Redhat123p@ssword'
oc get applications -n dba-dev
# Should only see: dev-postgres

# Cannot see other team applications
oc get applications -n dba-test
# Forbidden

# Check ArgoCD UI - should only see dev-postgres in dba-dev namespace
```

## Best Practices

### 1. Use Per-Team Projects in Production
For actual production, use individual projects (`team-dev`, `team-test`, `team-prod`) with strict namespace restrictions.

### 2. Define Resource Quotas
Add to AppProject spec:
```yaml
spec:
  resourceQuotas:
    - hard:
        limits.cpu: "10"
        limits.memory: 20Gi
        persistentvolumeclaims: "10"
```

### 3. Source Repository Restrictions
Limit which repos teams can deploy from:
```yaml
spec:
  sourceRepos:
    - https://github.com/your-org/team-dev-configs  # Only their repo
```

### 4. Enable Orphaned Resource Detection
```yaml
spec:
  orphanedResources:
    warn: true  # Alert on resources not in Git
```

## Switching Project Strategy

### To Use Shared Project
Update all team apps to use `postgres-databases`:
```yaml
spec:
  project: postgres-databases
```

### To Use Per-Team Projects
Keep current configuration (already set):
```yaml
spec:
  project: team-dev  # or team-test, team-prod
```

Both are valid depending on your security requirements!
