# Demo Guide: PostgreSQL Operator Multi-Tenant Deployment

Choose your deployment method and follow the focused guide.

## Quick Start

### Prerequisites

Before starting, ensure all prerequisites are met:
- **Complete Setup:** [docs/PREREQUISITES.md](docs/PREREQUISITES.md)
- **Quick Check:** `./common/check-prerequisites.sh`

### Choose Your Deployment Method

| Method | Guide | Time | Best For |
|--------|-------|------|----------|
| **Helm** | [DEMO-HELM.md](DEMO-HELM.md) | 15 min | Learning, quick start, manual control |
| **GitOps** | [DEMO-GITOPS.md](DEMO-GITOPS.md) | 15 min | Production, automation, drift detection |

### Need Help?

- **Comparison:** [DEMO-COMPARISON.md](DEMO-COMPARISON.md) - Which method to choose?
- **Troubleshooting:** [DEMO-TROUBLESHOOTING.md](DEMO-TROUBLESHOOTING.md) - Common issues
- **Quick Script:** [DEMO-SCRIPT.md](DEMO-SCRIPT.md) - Presenter cheat sheet

## Overview

Both deployment methods demonstrate:

- **Multi-Tenant Architecture:** Namespace isolation with cross-environment visibility
- **Group-Based RBAC:** Collaboration without compromising security
- **Self-Service Workflow:** DBA users deploy databases independently
- **Environment Isolation:** Dev, Test, Prod with appropriate controls
- **Master DBA Role:** Full administrative access across all environments
- **SecOps Monitoring:** Read-only access for security teams

## Architecture Overview

```
┌─────────────────────────────────────────────┐
│ Cluster-Admin                               │
│ ├── Installs Operator                       │
│ ├── Configures Cluster-Wide RBAC            │
│ └── Grants namespace-specific permissions   │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│ DBA Users (Self-Service)                    │
│ ├── dba-dev  → Manages dba-dev namespace    │
│ ├── dba-test → Manages dba-test namespace   │
│ ├── dba-prod → Manages dba-prod namespace   │
│ ├── dba (Master) → Manages ALL namespaces   │
│ └── All DBAs → Read-only to all via group   │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│ PostgreSQL Clusters + Frontend Web App      │
│ ├── dba-dev:  dev-cluster + frontend (Go)   │
│ ├── dba-test: test-cluster + frontend (Go)  │
│ └── dba-prod: prod-cluster + frontend (Go)  │
└─────────────────────────────────────────────┘
```

## Key Features Demonstrated

### Security & Isolation
- Namespace-based isolation (write permissions)
- Group-based collaboration (read permissions via `dba-users` group)
- Role-based access control (Master DBA, Environment DBAs, SecOps)
- OpenShift SCC integration

### Deployment Methods

#### Helm (Traditional)
- Manual deployment with `oc apply`
- Direct control over sync timing
- Familiar workflow for Kubernetes users
- Good for learning and experimentation

#### GitOps (Automated)
- ArgoCD auto-sync from Git repository
- Automatic drift detection and correction
- Full audit trail of all changes
- Production-ready with approval workflows

## Documentation Structure

```
(root)
├── DEMO.md                    # This file - choose your path
├── DEMO-HELM.md              # Helm deployment (Part 1)
├── DEMO-GITOPS.md            # GitOps deployment (Part 2)
├── DEMO-COMPARISON.md        # Side-by-side comparison
├── DEMO-TROUBLESHOOTING.md   # Common issues and solutions
├── DEMO-SCRIPT.md            # Quick presenter reference
docs/
└── PREREQUISITES.md          # Complete setup requirements
```

## Quick Commands

```bash
# Check prerequisites
./common/check-prerequisites.sh

# One-click install (Helm)
./install-helm-demo.sh

# One-click install (GitOps)
./install-gitops-demo.sh

# Verify installation
./common/verify-installation.sh

# Access PostgreSQL UI
./common/access-ui.sh

# Get database credentials
./common/get-credentials.sh <cluster-name> <namespace>

# Cleanup
./cleanup.sh
```

## What's Next?

1. **Complete Prerequisites:** [docs/PREREQUISITES.md](docs/PREREQUISITES.md)
2. **Choose Deployment:**
   - Manual/Learning → [DEMO-HELM.md](DEMO-HELM.md)
   - Automated/Production → [DEMO-GITOPS.md](DEMO-GITOPS.md)
3. **Compare Methods:** [DEMO-COMPARISON.md](DEMO-COMPARISON.md)
4. **Present to Team:** [DEMO-SCRIPT.md](DEMO-SCRIPT.md)

## Additional Resources

- **Architecture:** [gitops/README.md](gitops/README.md)
- **Helper Scripts:** [common/README.md](common/README.md)
- **Quick Reference:** [docs/README.md](docs/README.md)
- **RBAC Details:** [docs/RBAC-VISUAL.md](docs/RBAC-VISUAL.md)
- **ArgoCD Projects:** [docs/ARGOCD-PROJECTS.md](docs/ARGOCD-PROJECTS.md)
