# Rendered by scripts/bootstrap.sh (REPO_URL is filled in from your git remote)
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: selfheal
  namespace: argocd
  finalizers: ["resources-finalizer.argocd.argoproj.io"]
spec:
  project: default
  source:
    repoURL: ${REPO_URL}
    targetRevision: main
    path: charts/selfheal
  destination:
    server: https://kubernetes.default.svc
    namespace: selfheal
  syncPolicy:
    automated:
      prune: true
      selfHeal: true            # if someone changes the cluster by hand, Argo CD puts it back
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 10                 # first sync may wait for the monitoring CRDs to exist
      backoff: { duration: 20s, factor: 2, maxDuration: 3m }
