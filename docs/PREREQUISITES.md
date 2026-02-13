# Prerequisites

This document outlines all prerequisites and one-time setup steps required before deploying the PostgreSQL Operator.

## 1. Required Tools

Install the following tools on your workstation:

- **OpenShift CLI (`oc`)** - Version 4.x
- **Helm** - Version 3.x
- **jq** - JSON processor for scripts

Check prerequisites:
```bash
./common/check-prerequisites.sh
```

## 2. OpenShift Cluster Access

You need cluster-admin access to the OpenShift cluster for initial setup:

```bash
oc login --server=https://your-cluster:6443
oc whoami
oc auth can-i '*' '*'  # Should return 'yes'
```

## 3. User Creation (One-Time Setup)

Create the DBA and monitoring users via htpasswd OAuth provider:

```bash
# This is typically done by cluster administrators
# Users needed:
# - dba (master DBA)
# - dba-dev (dev environment DBA)
# - dba-test (test environment DBA)
# - dba-prod (prod environment DBA)
# - secops (monitoring user)

# Password for all demo users: Redhat123p@ssword
```

**Note:** User creation is outside the scope of this demo. Consult your OpenShift administrator or see [OpenShift Authentication documentation](https://docs.openshift.com/container-platform/latest/authentication/index.html).

## 4. Group Creation and Membership (One-Time Setup)

After users are created, set up the `dba-users` group:

```bash
# Create the group
oc adm groups new dba-users

# Add users to the group
oc adm groups add-users dba-users dba dba-dev dba-test dba-prod

# Verify
oc get group dba-users -o yaml
```

**Why is this needed?**

OpenShift requires bidirectional linking for group membership:
1. The Group resource lists users (done via YAML in our repo)
2. Users must be registered with the group (done via `oc adm groups add-users`)

Both steps are required for RBAC to work correctly. The Group YAML provides documentation and structure, but the CLI command activates the membership.

### For Helm Deployments

The `setup-dba-rbac.sh` script automatically runs `oc adm groups add-users`, so you only need to ensure users exist first.

### For GitOps Deployments

After ArgoCD creates the Group resource, run once:
```bash
oc adm groups add-users dba-users dba dba-dev dba-test dba-prod
```

This is a known limitation of managing OpenShift Groups via GitOps.

## 5. Verification

After completing setup, verify everything is ready:

```bash
./common/check-prerequisites.sh
```

Expected output:
```
Prerequisites Check
===================

 oc: ...
 helm: ...
 jq: ...

 OpenShift: Logged in as cluster-admin
  Server: https://...
   Admin privileges: Yes

OpenShift Users:
   dba
   dba-dev
   dba-test
   dba-prod
   secops

OpenShift Groups:
   dba-users exists
    Members: dba dba-dev dba-test dba-prod
     dba in group
     dba-dev in group
     dba-test in group
     dba-prod in group

Summary
=======
 All prerequisites met - ready to deploy!
```

## Quick Setup Script

For convenience, you can run everything after user creation:

```bash
# Assumes users already exist
oc adm groups new dba-users 2>/dev/null || echo "Group exists"
oc adm groups add-users dba-users dba dba-dev dba-test dba-prod
./common/check-prerequisites.sh
```

## Next Steps

Once prerequisites are met:

- **Helm Deployment:** See [DEMO.md](../DEMO.md) Part 1 - Helm Installation
- **GitOps Deployment:** See [DEMO.md](../DEMO.md) Part 2 - GitOps Installation
- **Architecture:** See [gitops/README.md](../gitops/README.md)
