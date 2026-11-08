# Rendered by scripts/bootstrap.sh (REPO_URL is filled in from your git remote)
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: monitoring
  namespace: argocd
  finalizers: ["resources-finalizer.argocd.argoproj.io"]
spec:
  project: default
  sources:
    - repoURL: https://prometheus-community.github.io/helm-charts
      chart: kube-prometheus-stack
      targetRevision: "*"
      helm:
        releaseName: monitoring
        valueFiles:
          - $values/gitops/monitoring-values.yaml
    - repoURL: ${REPO_URL}
      targetRevision: main
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true       # the Prometheus CRDs are too large for client-side apply
    retry:
      limit: 10
      backoff: { duration: 15s, factor: 2, maxDuration: 3m }
