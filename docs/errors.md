# Problems I hit and how I fixed them

Real issues from building and running this platform: symptom, root cause, fix, and what I took away.

---

## 1. Lab VM too small for Kubernetes + monitoring
- **Symptom:** Pre-flight check showed 2 CPUs, 3.8 GB RAM (2.1 GB available) and 9.7 GB free disk, below what k3s + Argo CD + Prometheus + Grafana need.
- **Root cause:** The VM was sized for Docker + Jenkins only.
- **Fix:** Resized the VMware VM to 4 vCPU / 8 GB RAM and expanded the virtual disk from 40 GB to 80 GB (checked there were no snapshots first). Then grew the partition and filesystem **online** inside Ubuntu:
  ```bash
  lsblk && df -T /                 # confirm sda3 is the last partition and ext4
  sudo growpart /dev/sda 3         # extend the partition
  sudo resize2fs /dev/sda3         # grow ext4 while mounted
  ```
  Result: `/` went from 39 GB to 78 GB (48 GB free) without a reboot.
- **Lesson:** Capacity-check before installing. `bootstrap.sh` now refuses to start below 6 GB RAM / 15 GB disk.

## 2. CI image push failed: `denied: permission_denied: write_package`
- **Symptom:** In GitHub Actions, `test` and `chart` passed, but `image` failed at the very end, when pushing to `ghcr.io/gokul36115/selfheal-app`.
- **Root cause:** The GHCR package already existed from an earlier repository and was still linked to it. A new repository's `GITHUB_TOKEN` has no write access to a package owned by another repo.
- **Fix:** Package settings → **Manage Actions access** → added `k8s-selfheal-platform` with the **Write** role, then *Re-run failed jobs*. The build was already fine; only the permission was missing.
- **Lesson:** GHCR permissions are per package, not per account. Read the last line of the log before touching the Dockerfile.

## 3. Grafana `CrashLoopBackOff` → `OOMKilled` (exit code 137)
- **Symptom:** `bootstrap.sh` stopped with `deployment "monitoring-grafana" exceeded its progress deadline`. The pod showed `2/3 Running`, `CrashLoopBackOff`, and probes failed with `connection refused` on port 3000.
- **Debugging:**
  ```bash
  kubectl -n monitoring get pods
  kubectl -n monitoring describe pod -l app.kubernetes.io/name=grafana     # events: probe failures, back-off
  kubectl -n monitoring get pod <pod> -o jsonpath='{.status.containerStatuses[*].lastState.terminated.reason}'
  # -> OOMKilled
  ```
- **Root cause:** I had set Grafana's memory limit to 256Mi. Grafana 13 uses more than that during start-up, so the kernel killed it before it could listen on :3000.
- **Fix (GitOps, no `kubectl edit`):** Raised the limit in `gitops/monitoring-values.yaml` (request 256Mi, limit 768Mi), committed and pushed. Argo CD rolled out the new pod, and the app went `Synced / Healthy`.
- **Lesson:** `CrashLoopBackOff` is a symptom, not a cause. `lastState.terminated.reason` tells you why. Size limits from observed usage, not guesses.

## 4. Unwanted bot in the repository's Contributors
- **Symptom:** After the first CI run, `github-actions[bot]` appeared as a contributor.
- **Root cause:** The first version of the pipeline committed the new image tag to `values.yaml` itself.
- **Fix:** Changed CI to `permissions: contents: read`, so it can't write to the repo at all. Promotion is now a reviewed human step (`scripts/release.sh`), committed under my own identity.
- **Lesson:** Give pipelines the least privilege they need. A human-approved promotion step is also a common production pattern.

## 5. Observation: HPA scaled out during chaos testing without real load
- **What I saw:** While crashing the JVM on purpose, Grafana showed **desired replicas 2 → 5** and ready pods 4, even though no load test was running. It scaled back to 2 afterwards.
- **Why:** A restarting JVM burns a lot of CPU during start-up (class loading, JIT). Relative to a 250m CPU request, that looks like >60% utilization to the HPA.
- **Takeaways / possible improvements:** Tune the HPA with a scale-up stabilization window or `behavior.scaleUp` policies, or use custom metrics (requests per second) instead of raw CPU for JVM workloads.
