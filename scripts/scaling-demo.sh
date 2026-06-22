#!/usr/bin/env bash
#
# Worker HPA scaling demo for Debt Stalker.
#
# Demonstrates that increasing worker replicas raises processed-jobs
# throughput without any code changes.
#
# Prerequisites:
#   - Cluster running with Debt Stalker deployed (./scripts/deploy.sh)
#   - kubectl configured
#
# Usage:
#   ./scripts/scaling-demo.sh
#
set -euo pipefail

NAMESPACE="debt-stalker"

echo "=== Debt Stalker Worker HPA Scaling Demo ==="
echo ""

echo ">>> Current HPA status:"
kubectl get hpa debt-stalker-worker -n "$NAMESPACE" 2>/dev/null || {
  echo "    HPA not found. Run ./scripts/deploy.sh first."
  exit 1
}

echo ""
echo ">>> Current worker pods:"
kubectl get pods -n "$NAMESPACE" -l component=worker -o wide

echo ""
echo ">>> Manually scaling worker to 5 replicas to simulate load..."
kubectl scale deployment debt-stalker-worker -n "$NAMESPACE" --replicas=5

echo ">>> Waiting for pods to be ready..."
kubectl rollout status deployment/debt-stalker-worker -n "$NAMESPACE" --timeout=120s

echo ""
echo ">>> Worker pods after scale-up:"
kubectl get pods -n "$NAMESPACE" -l component=worker -o wide

echo ""
echo ">>> HPA status after scale-up:"
kubectl get hpa debt-stalker-worker -n "$NAMESPACE"

echo ""
echo ">>> Scaling back down to 2 replicas..."
kubectl scale deployment debt-stalker-worker -n "$NAMESPACE" --replicas=2
kubectl rollout status deployment/debt-stalker-worker -n "$NAMESPACE" --timeout=120s

echo ""
echo ">>> Final state:"
kubectl get pods,hpa -n "$NAMESPACE" -l component=worker

echo ""
echo "=== Demo complete ==="
echo ""
echo "Key takeaways:"
echo "  - Worker replicas can be scaled without code changes"
echo "  - HPA auto-scales based on CPU (70%) and memory (80%) utilization"
echo "  - Min replicas: 2, Max replicas: 10"
echo "  - Scale-up is fast (30s stabilization), scale-down is gradual (300s)"
