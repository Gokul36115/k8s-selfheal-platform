#!/usr/bin/env bash
# =====================================================================
#  chaos.sh: break the app on purpose and watch Kubernetes heal it.
#  Run while the Grafana dashboard is open to see each event live.
# =====================================================================
set -uo pipefail
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
NS=selfheal
IP=$(hostname -I | awk '{print $1}'); URL="http://$IP:30080"
hdr() { echo; echo -e "\e[36m=== $* ===\e[0m"; }
restarts() { kubectl -n $NS get pods -l app.kubernetes.io/name=selfheal -o jsonpath='{range .items[*]}{.metadata.name}{"  restarts="}{.status.containerStatuses[0].restartCount}{"\n"}{end}'; }
availability() {   # send 40 requests, count failures while chaos is happening
  local ok=0 fail=0
  for i in $(seq 1 40); do
    code=$(curl -s -o /dev/null -m 3 -w '%{http_code}' "$URL/") ; [ "$code" = 200 ] && ok=$((ok+1)) || fail=$((fail+1)); sleep 0.25
  done
  echo "    user requests during the test: $ok OK, $fail failed"
}

hdr "Before"; restarts

hdr "1. Delete a pod (simulates a node/pod loss)"
POD=$(kubectl -n $NS get pods -l app.kubernetes.io/name=selfheal -o jsonpath='{.items[0].metadata.name}')
kubectl -n $NS delete pod "$POD" --wait=false
availability
kubectl -n $NS rollout status deploy/selfheal --timeout=180s

hdr "2. Crash the JVM (/api/crash -> exit code 1)"
curl -s -m 3 "$URL/api/crash"; echo
availability
sleep 20; restarts

hdr "3. OutOfMemoryError (/api/memory until the JVM exits with code 3)"
for i in $(seq 1 15); do curl -s -m 5 -o /dev/null "$URL/api/memory"; done
availability
sleep 25; restarts
echo
echo "    Last termination reasons:"
kubectl -n $NS get pods -l app.kubernetes.io/name=selfheal -o jsonpath='{range .items[*]}{.metadata.name}{"  exitCode="}{.status.containerStatuses[0].lastState.terminated.exitCode}{"\n"}{end}'

hdr "4. Manual drift (scale to 1 by hand -> Argo CD self-heal reverts it)"
kubectl -n $NS scale deploy/selfheal --replicas=1
echo "    scaled to 1... waiting for the HPA / Argo CD to restore it"
sleep 45
kubectl -n $NS get deploy selfheal

hdr "After"; restarts
echo
echo "Check Grafana -> 'Selfheal · SLO & Self-Healing': restarts panel, availability, alerts."
