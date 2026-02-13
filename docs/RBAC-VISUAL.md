# RBAC Visual Diagrams

## Quick Reference: User Permissions

```mermaid
graph TB
    subgraph Users
        DBA[dba<br/>Master DBA]
        DBADEV[dba-dev<br/>Dev DBA]
        DBATEST[dba-test<br/>Test DBA]
        DBAPROD[dba-prod<br/>Prod DBA]
        SECOPS[secops<br/>Monitoring]
    end

    subgraph Group
        GROUP[dba-users GROUP]
    end

    subgraph Namespaces
        NSDEV[dba-dev namespace]
        NSTEST[dba-test namespace]
        NSPROD[dba-prod namespace]
        NSOP[postgres-operator]
    end

    DBA -->|WRITE| NSDEV
    DBA -->|WRITE| NSTEST
    DBA -->|WRITE| NSPROD
    DBA -->|Port-Forward| NSOP

    DBADEV -->|WRITE| NSDEV
    DBATEST -->|WRITE| NSTEST
    DBAPROD -->|WRITE| NSPROD

    DBA -.->|member| GROUP
    DBADEV -.->|member| GROUP
    DBATEST -.->|member| GROUP
    DBAPROD -.->|member| GROUP

    GROUP -->|READ| NSDEV
    GROUP -->|READ| NSTEST
    GROUP -->|READ| NSPROD

    SECOPS -->|READ| NSDEV
    SECOPS -->|READ| NSTEST
    SECOPS -->|READ| NSPROD
    SECOPS -->|READ| NSOP

    style DBA fill:#ff6b6b
    style DBADEV fill:#4ecdc4
    style DBATEST fill:#45b7d1
    style DBAPROD fill:#f38181
    style SECOPS fill:#95e1d3
    style GROUP fill:#ffd93d
```

## Permission Inheritance Flow

```mermaid
graph LR
    subgraph Cluster Level
        CR1[ClusterRole:<br/>postgres-user-role]
        CR2[ClusterRole:<br/>postgres-monitor]
        CR3[ClusterRole:<br/>view]
    end

    subgraph Master DBA
        DBA[dba user]
        CRB1[ClusterRoleBinding]
    end

    subgraph Environment DBAs
        ENVDBA[dba-dev/test/prod]
        RB1[RoleBinding<br/>in own namespace]
        GROUP[dba-users group]
        RB2[RoleBinding<br/>cross-namespace]
    end

    subgraph SecOps
        SECOPS[secops user]
        CRB2[ClusterRoleBinding]
    end

    CR1 -->|grants| CRB1
    CRB1 -->|to| DBA

    CR1 -->|grants| RB1
    RB1 -->|to| ENVDBA

    CR2 -->|grants| RB2
    CR3 -->|grants| RB2
    RB2 -->|to| GROUP
    ENVDBA -.->|member of| GROUP

    CR2 -->|grants| CRB2
    CR3 -->|grants| CRB2
    CRB2 -->|to| SECOPS
```

## Permission Levels by Namespace

```mermaid
graph TB
    subgraph dba-dev Namespace
        D1[dba: WRITE]
        D2[dba-dev: WRITE]
        D3[dba-test: READ]
        D4[dba-prod: READ]
        D5[secops: READ]
    end

    subgraph dba-test Namespace
        T1[dba: WRITE]
        T2[dba-dev: READ]
        T3[dba-test: WRITE]
        T4[dba-prod: READ]
        T5[secops: READ]
    end

    subgraph dba-prod Namespace
        P1[dba: WRITE]
        P2[dba-dev: READ]
        P3[dba-test: READ]
        P4[dba-prod: WRITE]
        P5[secops: READ]
    end

    style D1 fill:#ff6b6b
    style D2 fill:#4ecdc4
    style D3 fill:#e8f5e9
    style D4 fill:#e8f5e9
    style D5 fill:#e8f5e9

    style T1 fill:#ff6b6b
    style T2 fill:#e8f5e9
    style T3 fill:#45b7d1
    style T4 fill:#e8f5e9
    style T5 fill:#e8f5e9

    style P1 fill:#ff6b6b
    style P2 fill:#e8f5e9
    style P3 fill:#e8f5e9
    style P4 fill:#f38181
    style P5 fill:#e8f5e9
```

## RBAC Resource Relationships

```mermaid
graph TB
    subgraph User Management
        USERS[Users:<br/>dba, dba-dev,<br/>dba-test, dba-prod]
        GROUP[Group:<br/>dba-users]
        USERS -->|members of| GROUP
    end

    subgraph Cluster Resources
        CR1[ClusterRole:<br/>postgres-user-role<br/>FULL access]
        CR2[ClusterRole:<br/>postgres-monitor<br/>READ access]
        CR3[ClusterRole:<br/>view<br/>K8s READ]
    end

    subgraph Bindings
        CRB1[ClusterRoleBinding:<br/>Master DBA]
        RB1[RoleBindings:<br/>Per Namespace<br/>for DBAs]
        RB2[RoleBindings:<br/>Per Namespace<br/>for Group]
    end

    CR1 -->|used by| CRB1
    CR1 -->|used by| RB1
    CR2 -->|used by| RB2
    CR3 -->|used by| RB2

    USERS -->|individual| RB1
    GROUP -->|group| RB2
    USERS -->|dba only| CRB1

    CRB1 -->|grants cluster-wide| NS
    RB1 -->|grants namespace| NS
    RB2 -->|grants namespace| NS

    subgraph Namespaces
        NS[dba-dev<br/>dba-test<br/>dba-prod]
    end
```

## Access Summary Table

| User | Cluster-Wide | dba-dev | dba-test | dba-prod | postgres-operator |
|------|-------------|---------|----------|----------|-------------------|
| **dba** | PostgreSQL CRUD<br/>View all | READ/WRITE | READ/WRITE | READ/WRITE | Port-forward |
| **dba-dev** | View all (group)<br/>PostgreSQL READ (group) | READ/WRITE | READ | READ | - |
| **dba-test** | View all (group)<br/>PostgreSQL READ (group) | READ | READ/WRITE | READ | - |
| **dba-prod** | View all (group)<br/>PostgreSQL READ (group) | READ | READ | READ/WRITE | - |
| **secops** | View all<br/>PostgreSQL READ<br/>Pod logs | READ | READ | READ | READ |

**Legend:**
- **WRITE** = Create, Update, Delete PostgreSQL clusters
- **READ** = View resources only
- **(group)** = Permission inherited via dba-users group membership

## Key Security Features

```
┌─────────────────────────────────────────────────────────────┐
│  WRITE Isolation (Can modify databases)                    │
├─────────────────────────────────────────────────────────────┤
│  • dba         → ALL namespaces (Master DBA)                │
│  • dba-dev     → dba-dev only                               │
│  • dba-test    → dba-test only                              │
│  • dba-prod    → dba-prod only                              │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  READ Visibility (Can view for troubleshooting)             │
├─────────────────────────────────────────────────────────────┤
│  • dba-users group → ALL dba-* namespaces                   │
│  • secops          → ALL namespaces (monitoring)            │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  Special Access                                              │
├─────────────────────────────────────────────────────────────┤
│  • dba → Port-forward to PostgreSQL Operator UI             │
└─────────────────────────────────────────────────────────────┘
```
