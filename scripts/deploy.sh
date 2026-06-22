#!/usr/bin/env bash
#
# Deploy Debt Stalker to a local kind/minikube cluster.
#
# Prerequisites:
#   - kind or minikube installed and running
#   - kubectl configured to talk to the cluster
#   - Docker image built: docker build -t debt-stalker:latest .
#   - For kind: kind load docker-image debt-stalker:latest
#
# Usage:
#   ./scripts/deploy.sh          # deploy all resources
#   ./scripts/deploy.sh rollback # rollback to previous rollout
#
set -euo pipefail

NAMESPACE="debt-stalker"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="${SCRIPT_DIR}/../k8s"

# Detect cluster type and load image
if command -v kind &>/dev/null && kind get clusters 2>/dev/null | grep -q .; then
  echo ">>> Loading image into kind..."
  kind load docker-image debt-stalker:latest
elif command -v minikube &>/dev/null && minikube status 2>/dev/null | grep -q "Running"; then
  echo ">>> Minikube detected — using minikube docker-env..."
  eval "$(minikube docker-env)"
else
  echo ">>> No kind/minikube cluster found. Assuming image is available in cluster."
fi

if [[ "${1:-}" == "rollback" ]]; then
  echo ">>> Rolling back web deployment..."
  kubectl rollout undo deployment/debt-stalker-web -n "$NAMESPACE"
  echo ">>> Rolling back worker deployment..."
  kubectl rollout undo deployment/debt-stalker-worker -n "$NAMESPACE"
  echo ">>> Rollback complete."
  kubectl rollout status deployment/debt-stalker-web -n "$NAMESPACE"
  kubectl rollout status deployment/debt-stalker-worker -n "$NAMESPACE"
  exit 0
fi

echo ">>> Applying namespace..."
kubectl apply -f "${K8S_DIR}/namespace.yaml"

echo ">>> Applying configmap..."
kubectl apply -f "${K8S_DIR}/configmap.yaml"

echo ">>> Applying secrets..."
kubectl apply -f "${K8S_DIR}/secret.yaml"

echo ">>> Running migration job..."
kubectl apply -f "${K8S_DIR}/migration-job.yaml"
kubectl wait --for=condition=complete job/debt-stalker-migrate -n "$NAMESPACE" --timeout=120s || {
  echo ">>> Migration job failed. Check logs:"
  kubectl logs job/debt-stalker-migrate -n "$NAMESPACE"
  exit 1
}
echo ">>> Migration complete."

echo ">>> Deploying web deployment..."
kubectl apply -f "${K8S_DIR}/deployment-web.yaml"
kubectl rollout status deployment/debt-stalker-web -n "$NAMESPACE" --timeout=180s

echo ">>> Deploying worker deployment..."
kubectl apply -f "${K8S_DIR}/deployment-worker.yaml"
kubectl rollout status deployment/debt-stalker-worker -n "$NAMESPACE" --timeout=180s

echo ">>> Applying service..."
kubectl apply -f "${K8S_DIR}/service.yaml"

echo ">>> Applying HPA for worker..."
kubectl apply -f "${K8S_DIR}/hpa-worker.yaml"

echo ""
echo ">>> Deploy complete!"
echo "    Web pods:   $(kubectl get pods -n "$NAMESPACE" -l component=web -o name | wc -l | tr -d ' ')"
echo "    Worker pods: $(kubectl get pods -n "$NAMESPACE" -l component=worker -o name | wc -l | tr -d ' ')"
echo "    HPA:         $(kubectl get hpa -n "$NAMESPACE" -l component=worker -o name | wc -l | tr -d ' ')"
echo ""
echo "    To port-forward: kubectl port-forward svc/debt-stalker -n $NAMESPACE 4000:4000"
