#!/usr/bin/env bash
# =====================================================================
#  release.sh: promote a CI-built image to the cluster (GitOps).
#  Updates charts/selfheal/values.yaml, commits it under YOUR git identity
#  and pushes. Argo CD sees the change in Git and rolls it out.
#  Usage: ./scripts/release.sh [commit-sha]   (default: latest commit on origin/main)
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
git fetch -q origin main
SHA="${1:-$(git rev-parse origin/main)}"
OWNER=$(git remote get-url origin | sed -E 's#.*github.com[:/]([^/]+)/.*#\1#' | tr '[:upper:]' '[:lower:]')
IMAGE="ghcr.io/${OWNER}/selfheal-app"

echo "Checking that ${IMAGE}:${SHA} exists (CI must have passed for this commit)..."
if ! docker manifest inspect "${IMAGE}:${SHA}" >/dev/null 2>&1; then
  echo "  Not found. Check the Actions tab: use the SHA of a green run, e.g. ./scripts/release.sh <sha>"
  echo "  (Also make sure the ghcr.io package 'selfheal-app' is set to Public.)"
  exit 1
fi

git pull -q --ff-only origin main
sed -i "s|^  repository: .*|  repository: ${IMAGE}|; s|^  tag: .*|  tag: \"${SHA}\"|" charts/selfheal/values.yaml
git --no-pager diff charts/selfheal/values.yaml
read -rp "Release ${SHA:0:7} to the cluster? [y/N] " ans
[[ "$ans" =~ ^[Yy]$ ]] || { git checkout charts/selfheal/values.yaml; echo "Cancelled."; exit 0; }
git commit -qm "release: selfheal-app ${SHA:0:7}" charts/selfheal/values.yaml
git push -q origin main
echo "Pushed. Argo CD will roll out ${SHA:0:7} within ~3 minutes:"
echo "  kubectl -n selfheal rollout status deploy/selfheal"
