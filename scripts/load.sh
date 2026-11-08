#!/usr/bin/env bash
# =====================================================================
#  load.sh: CPU load from inside the cluster to trigger autoscaling (HPA).
#  Usage: ./scripts/load.sh [seconds]   (default 240)
# =====================================================================
set -uo pipefail
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
DUR="${1:-240}"
echo "Starting 4 load workers for ${DUR}s against selfheal (watch the HPA in another terminal):"
echo "    kubectl -n selfheal get hpa,pods -w"
kubectl -n selfheal delete pod loadgen --ignore-not-found >/dev/null
kubectl -n selfheal run loadgen --image=curlimages/curl:8.10.1 --restart=Never --command -- sh -c "
  end=\$((\$(date +%s)+$DUR));
  for w in 1 2 3 4; do (while [ \$(date +%s) -lt \$end ]; do curl -s -o /dev/null 'http://selfheal:8080/api/cpu?ms=300'; done) & done; wait"
kubectl -n selfheal wait --for=condition=Ready pod/loadgen --timeout=90s >/dev/null 2>&1
for i in $(seq 1 $((DUR/15))); do
  cpu=$(kubectl -n selfheal get hpa selfheal -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}')
  rep=$(kubectl -n selfheal get hpa selfheal -o jsonpath='{.status.currentReplicas}')
  echo "  $(date +%H:%M:%S)  cpu=${cpu:-?}%  (target 60%)  replicas=${rep:-?}"
  sleep 15
done
kubectl -n selfheal delete pod loadgen --ignore-not-found >/dev/null
echo "Load finished. Replicas scale back down after the 2-minute stabilization window."
