#!/bin/bash

echo "PostgreSQL Clusters"
echo "==================="
echo ""

oc get postgresql --all-namespaces \
    -o custom-columns=\
NAMESPACE:.metadata.namespace,\
NAME:.metadata.name,\
TEAM:.spec.teamId,\
VERSION:.spec.postgresql.version,\
INSTANCES:.spec.numberOfInstances,\
VOLUME:.spec.volume.size,\
STATUS:.status.PostgresClusterStatus 2>/dev/null || echo "No clusters found"

echo ""
echo "Pods"
echo "===="
echo ""

oc get pods --all-namespaces -l application=spilo \
    -o custom-columns=\
NAMESPACE:.metadata.namespace,\
POD:.metadata.name,\
STATUS:.status.phase,\
ROLE:.metadata.labels.spilo-role,\
AGE:.metadata.creationTimestamp 2>/dev/null || echo "No pods found"

echo ""
echo "Services"
echo "========"
echo ""

oc get services --all-namespaces -l application=spilo \
    -o custom-columns=\
NAMESPACE:.metadata.namespace,\
SERVICE:.metadata.name,\
TYPE:.spec.type,\
CLUSTER-IP:.spec.clusterIP,\
PORT:.spec.ports[0].port 2>/dev/null || echo "No services found"
