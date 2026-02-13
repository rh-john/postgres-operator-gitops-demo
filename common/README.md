# Common Scripts

Shared utilities for both Helm and GitOps methods.

## Core Library

### functions.sh
Shared function library used by all scripts. Provides:

**Colors and Formatting:**
- Color variables (`RED`, `GREEN`, `YELLOW`, `CYAN`, `BOLD`, `NC`)
- Status symbols (`OK`, `FAIL`, `WARN`, `INFO`)
- Output functions (`die`, `warn`, `info`, `success`, `banner`, `section_header`, `step`)

**OpenShift Connection:**
- `check_oc_login` - Verify OpenShift login
- `get_current_user` - Get current user
- `has_cluster_admin` - Check for cluster-admin privileges
- `can_i <verb> <resource> [namespace]` - Check specific permissions
- `require_cluster_admin` - Require cluster-admin or exit

**Resource Wait Functions:**
- `wait_for_namespace <name> [timeout]` - Wait for namespace to be Active
- `wait_for_deployment <name> <namespace> [timeout]` - Wait for deployment ready
- `wait_for_pods <label> <namespace> [timeout]` - Wait for pods with label
- `wait_for_argocd_app <name> [namespace] [timeout]` - Wait for ArgoCD app sync

**Resource Checks:**
- `namespace_exists <name>` - Check if namespace exists
- `resource_exists <type> <name> [namespace]` - Check if resource exists
- `get_deployment_status <name> <namespace>` - Get "ready/desired" status
- `is_deployment_ready <name> <namespace>` - Check if deployment is ready

**Cleanup:**
- `remove_finalizers <type> <name> <namespace>` - Remove finalizers
- `remove_all_finalizers <type> <namespace>` - Remove all finalizers by type

Usage: Scripts source this file at the beginning:
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common/functions.sh"
```

## Setup Scripts

### setup-dba-rbac.sh
Configure master DBA with full access to all environments.

```bash
./setup-dba-rbac.sh dba
```

### setup-secops-rbac.sh
Configure monitoring user with cluster-wide read-only access.

```bash
./setup-secops-rbac.sh secops
```

### setup-user-namespace.sh
Grant user access to a specific namespace.

```bash
./setup-user-namespace.sh -n <namespace> -u <user>
```

### install-openshift-gitops.sh
Install OpenShift GitOps operator.

```bash
./install-openshift-gitops.sh
```

### configure-argocd-oauth.sh
Configure ArgoCD to use OpenShift OAuth and enable webhook support.

```bash
./configure-argocd-oauth.sh
```

Automatically configures:
- OpenShift SSO integration
- Webhook server (for instant Git sync)
- 30-second polling interval (fallback)
- RBAC policies for DBA users

### setup-github-webhook.sh
Automatically configure GitHub webhook for instant ArgoCD sync.

```bash
./setup-github-webhook.sh
```

Prerequisites:
- GitHub CLI (`gh`) installed and authenticated
- OpenShift GitOps installed
- Repository access permissions

This script:
- Detects your Git repository
- Creates webhook with ArgoCD URL
- Tests webhook connectivity
- Enables instant sync on git push

## Utility Scripts

### verify-installation.sh
Verify operator and cluster status.

```bash
./verify-installation.sh
```

### get-credentials.sh
Extract database credentials.

```bash
./get-credentials.sh <cluster-name> <namespace>
```

### show-all-databases.sh
List all PostgreSQL clusters across namespaces.

```bash
./show-all-databases.sh
```

### access-ui.sh
Port-forward to UI.

```bash
./access-ui.sh
# Access: http://localhost:8081
```

### check-prerequisites.sh
Check required tools and cluster connectivity.

```bash
./check-prerequisites.sh
```

## One-Click Installation Scripts

### install-helm-demo.sh (Root Level)
Automated Helm installation - installs everything in one go.

```bash
./install-helm-demo.sh
```

### install-gitops-demo.sh (Root Level)
Automated GitOps installation - installs everything in one go.

```bash
./install-gitops-demo.sh
```
