#!/usr/bin/env bash
# =====================================================================
#  bootstrap.sh: build the whole platform on a single Ubuntu VM
#    k3s (Kubernetes) -> app image -> Argo CD -> GitOps apps
#    (monitoring stack + selfheal app are then deployed BY Argo CD from Git)
#  Safe to re-run: every step checks whether it is already done.
# =====================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"

c_ok=$'\e[32m'; c_info=$'\e[36m'; c_warn=$'\e[33m'; c_err=$'\e[31m'; c_off=$'\e[0m'
step() { echo; echo "${c_info}==> [$1] $2${c_off}"; }
ok()   { echo "${c_ok}    ✔ $*${c_off}"; }
warn() { echo "${c_warn}    ! $*${c_off}"; }
die()  { echo "${c_err}    ✘ $*${c_off}"; exit 1; }

# ---------------------------------------------------------------------
step 1 "Pre-flight checks"
CPUS=$(nproc); MEM_GB=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
DISK_GB=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')
echo "    CPUs: $CPUS   RAM: ${MEM_GB} GB   Free disk: ${DISK_GB} GB"
[ "$CPUS" -ge 2 ]     || die "Need at least 2 CPUs"
[ "$MEM_GB" -ge 6 ]   || die "Need at least 6 GB RAM (have ${MEM_GB} GB). Increase VM memory first."
[ "$DISK_GB" -ge 15 ] || die "Need at least 15 GB free disk (have ${DISK_GB} GB). Grow the disk first."
command -v docker >/dev/null || die "Docker is required to build the app image"
command -v git >/dev/null    || die "git is required"
command -v envsubst >/dev/null || sudo apt-get install -y gettext-base >/dev/null

REPO_URL="${REPO_URL:-$(git remote get-url origin 2>/dev/null || true)}"
REPO_URL="${REPO_URL%.git}"
[[ "$REPO_URL" == https://github.com/* ]] || die "Push this repo to GitHub first (Argo CD deploys from it). Found remote: '${REPO_URL:-none}'"
git fetch -q origin main 2>/dev/null || true
if [ -n "$(git status --porcelain)" ] || [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main 2>/dev/null || echo x)" ]; then
  warn "Local changes are not pushed. Argo CD deploys what is on GitHub, so push first if you changed anything."
fi
ok "Repo: $REPO_URL"

# ---------------------------------------------------------------------
step 2 "Kubernetes (k3s)"
if ! command -v k3s >/dev/null; then
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644" sh -
else
  ok "k3s already installed"
fi
mkdir -p "$HOME/.kube"
cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"; chmod 600 "$HOME/.kube/config"
export KUBECONFIG="$HOME/.kube/config"
for i in $(seq 1 60); do kubectl get nodes 2>/dev/null | grep -q " Ready" && break; sleep 5; done
kubectl get nodes | grep -q " Ready" || die "Node did not become Ready"
ok "Node ready: $(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')"

# ---------------------------------------------------------------------
step 3 "Helm"
if ! command -v helm >/dev/null; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi
helm lint charts/selfheal >/dev/null && ok "Helm chart lint passed"

# ---------------------------------------------------------------------
step 4 "Build the app image and load it into k3s"
docker build -t selfheal-app:local app/
docker save selfheal-app:local | sudo k3s ctr images import - >/dev/null
ok "Image selfheal-app:local is available to Kubernetes"

# ---------------------------------------------------------------------
step 5 "Argo CD (GitOps controller)"
kubectl get ns argocd >/dev/null 2>&1 || kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml >/dev/null
kubectl -n argocd rollout status deploy/argocd-server --timeout=600s
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=600s
kubectl -n argocd patch svc argocd-server -p '{"spec":{"type":"NodePort","ports":[{"name":"https","port":443,"targetPort":8080,"nodePort":30443}]}}' >/dev/null
ok "Argo CD is running"

# ---------------------------------------------------------------------
step 6 "Register the GitOps applications"
export REPO_URL
for t in gitops/monitoring.app.yaml.tpl gitops/selfheal.app.yaml.tpl; do
  envsubst '${REPO_URL}' < "$t" | kubectl apply -f - >/dev/null
done
ok "Applications 'monitoring' and 'selfheal' created. Argo CD now deploys them from Git"

# ---------------------------------------------------------------------
step 7 "Wait for Argo CD to deploy everything (first run takes 5-10 minutes)"
echo "    Monitoring stack..."
for i in $(seq 1 90); do
  kubectl -n monitoring get deploy monitoring-grafana >/dev/null 2>&1 && break; sleep 10
done
kubectl -n monitoring rollout status deploy/monitoring-grafana --timeout=600s
echo "    Selfheal app..."
for i in $(seq 1 60); do kubectl -n selfheal get deploy selfheal >/dev/null 2>&1 && break; sleep 10; done
kubectl -n selfheal rollout status deploy/selfheal --timeout=600s
kubectl -n argocd get applications

# ---------------------------------------------------------------------
IP=$(hostname -I | awk '{print $1}')
ARGO_PW=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "(already rotated)")
GRAF_PW=$(kubectl -n monitoring get secret monitoring-grafana -o jsonpath='{.data.admin-password}' | base64 -d)
echo
echo "${c_ok}=================== PLATFORM READY ===================${c_off}"
echo "  App        http://$IP:30080/            (health: /actuator/health)"
echo "  Grafana    http://$IP:30300/            user: admin   password: $GRAF_PW"
echo "             dashboard: 'Selfheal · SLO & Self-Healing'"
echo "  Argo CD    https://$IP:30443/           user: admin   password: $ARGO_PW"
echo "             (self-signed certificate: click Advanced -> Proceed)"
echo
echo "  Next:  ./scripts/chaos.sh     (break things, watch them heal)"
echo "         ./scripts/load.sh      (generate load, watch autoscaling)"
echo "${c_ok}======================================================${c_off}"
