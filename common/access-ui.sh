#!/bin/bash

set -e

echo "==========================================
  PostgreSQL Operator UI - Port Forward
==========================================
"

echo "Starting port-forward to UI service..."
echo ""
echo "UI will be accessible at: http://localhost:8081"
echo ""
echo "Press Ctrl+C to stop"
echo ""

oc port-forward -n postgres-operator svc/postgres-operator-ui 8081:80
