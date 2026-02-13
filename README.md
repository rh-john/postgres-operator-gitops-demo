
# PostgreSQL Operator Multi-Tenancy Demo

PostgreSQL deployment on OpenShift with RBAC and network isolation.

## Overview

Deploy and manage PostgreSQL databases with:
- **Helm** - Direct control, manual deployment
- **GitOps** - Automated sync, drift detection, distributed multi-namespace architecture

Both methods implement identical multi-tenant RBAC and security.

## Features

- Multi-tenant namespaces (dev/test/prod)
- Role-based access control (master DBA, environment DBAs, secops)
- Network policies (namespace isolation, operator access, monitoring)
- High availability (Patroni with ConfigMap DCS)
- OpenShift-specific configuration (SCC, OAuth)
- PostgreSQL Operator UI

## Quick Start

### Prerequisites

**First-time setup:** Create users and groups (one-time). See [docs/PREREQUISITES.md](docs/PREREQUISITES.md) for details.

```bash
# Logged in as cluster-admin
oc whoami

# Verify prerequisites (tools, users, groups)
./common/check-prerequisites.sh
```

**Quick group setup** (if not already done):
```bash
oc adm groups new dba-users 2>/dev/null || echo "Group exists"
oc adm groups add-users dba-users dba dba-dev dba-test dba-prod
```

### Choose Your Method

**Helm (Manual):**
```bash
# See: DEMO-HELM.md
helm install postgres-operator ...
oc apply -k helm/overlays/dev/
```

**GitOps (Automated):**
```bash
# See: gitops/README.md
./common/install-openshift-gitops.sh
./common/configure-argocd-oauth.sh
oc apply -f gitops/cluster-config/app-of-apps.yaml
```

See [DEMO.md](./DEMO.md) for complete walkthrough.

### One-Click Installation (For Testing)

For quick demo/testing, use automated installation scripts:

```bash
# Helm method (one command)
./install-helm-demo.sh

# GitOps method (one command)
./install-gitops-demo.sh
```

Both scripts install everything automatically and provide verification steps.

## Project Structure

```
├── common/                    # Shared scripts
│   ├── install-openshift-gitops.sh
│   ├── configure-argocd-oauth.sh
│   ├── setup-dba-rbac.sh
│   ├── verify-installation.sh
│   └── cleanup.sh
├── helm/                      # Helm deployment
│   ├── rbac/                  # Cluster-level RBAC
│   ├── base/                  # Shared resources
│   └── overlays/              # Environment-specific
│       ├── dev/
│       ├── test/
│       └── prod/
├── gitops/                    # GitOps deployment
│   ├── cluster-config/        # Operators & cluster RBAC
│   │   ├── postgres-operator/
│   │   ├── postgres-ui/
│   │   └── rbac-cluster/
│   └── apps/                  # Database deployments
│       └── databases/
│           ├── base/
│           └── overlays/
└── docs/                      # Documentation
    ├── PREREQUISITES.md
    ├── ARGOCD-PROJECTS.md
    ├── RBAC-VISUAL.md
    └── README.md
```

## User Personas

| User | Access | Purpose |
|------|--------|---------|
| `dba` | All namespaces (admin) | Master DBA |
| `dba-dev` | Read all, write dev | Dev database admin |
| `dba-test` | Read all, write test | Test database admin |
| `dba-prod` | Read all, write prod | Prod database admin |
| `secops` | Read-only cluster-wide | Security monitoring |

All users: `Redhat123p@ssword`

See [docs/RBAC-VISUAL.md](docs/RBAC-VISUAL.md) for complete permission diagrams.

## Key OpenShift Configurations

### ConfigMaps for Patroni
```yaml
kubernetes_use_configmaps: "true"
```
Required for OpenShift - Endpoints-based DCS blocked by security policies.

### Security Context Constraints
```bash
oc adm policy add-scc-to-user anyuid -z postgres-pod -n dba-dev
```
Grants postgres pods permission to run with specific UIDs.

### ArgoCD OAuth
```bash
./common/configure-argocd-oauth.sh
```
Enables OpenShift SSO for ArgoCD UI - users login with same credentials.

## Verification

```bash
# Comprehensive check
./common/verify-installation.sh

# Quick status
./common/show-all-databases.sh
```

## Cleanup

```bash
# Safe cleanup (waits for natural resource cleanup)
./cleanup.sh

# Force cleanup (aggressively removes finalizers if stuck)
./cleanup.sh --force
```

## Documentation

### Demo Guides
- **[DEMO.md](DEMO.md)** - Start here, choose your path
- **[DEMO-HELM.md](DEMO-HELM.md)** - Helm deployment guide (15 min)
- **[DEMO-GITOPS.md](DEMO-GITOPS.md)** - GitOps deployment guide (15 min)
- **[DEMO-COMPARISON.md](DEMO-COMPARISON.md)** - Compare deployment methods
- **[DEMO-TROUBLESHOOTING.md](DEMO-TROUBLESHOOTING.md)** - Common issues and fixes
- **[DEMO-SCRIPT.md](DEMO-SCRIPT.md)** - Presenter quick reference

### Technical Documentation
- **[docs/README.md](docs/README.md)** - Quick reference
- **[docs/PREREQUISITES.md](docs/PREREQUISITES.md)** - Setup requirements
- **[docs/RBAC-VISUAL.md](docs/RBAC-VISUAL.md)** - RBAC diagrams
- **[docs/ARGOCD-PROJECTS.md](docs/ARGOCD-PROJECTS.md)** - ArgoCD configuration
- **[gitops/README.md](gitops/README.md)** - GitOps architecture
- **[common/README.md](common/README.md)** - Helper scripts

## Architecture

**Separation:**
- Cluster admins manage operators and cluster RBAC
- DBA users manage their databases
- NetworkPolicies enforce namespace isolation
- Cross-namespace read access via groups

**Security:**
- Least privilege access
- Network isolation between environments
- OpenShift SSO integration

**HA:**
- Patroni-managed clusters
- ConfigMap-based DCS
- Automatic failover

## License

This project is provided as-is for PostgreSQL multi-tenancy demonstrations on OpenShift.

## About Me

**John Johansson**  
Specialist Adoption Architect at Red Hat

This PostgreSQL operator demo showcases database-as-a-service patterns on OpenShift with multi-tenant RBAC configuration.

Connect with me for OpenShift architecture guidance and deployment patterns: [LinkedIn](https://linkedin.com/in/jjohanss)
