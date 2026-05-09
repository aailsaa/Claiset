# Zero-downtime promotion: how to capture evidence (**C6**)

**Requirement (summary):** Promotions / rollouts **must not drop user-visible traffic** in a sustained way—you need **artifacts** (**short silent video**, **`kubectl rollout status`** transcript, **`curl`/smoke logs**) showing **`2xx`/healthy path** across an image rollout.

Your stack already biases toward availability:

- **Deployments** (`infra/modules/eks-app`): **`maxUnavailable: 0`**, **readiness probes**, **`minReadySeconds`** soak on **UAT/Prod**, **`maxSurge`** bounds.
- **Smoke** pipeline: [`infra/scripts/smoke-test-env.sh`](../infra/scripts/smoke-test-env.sh) hits **HTTPS frontend** plus API paths checking **non-5xx**.

This doc ties those to **recording** what graders see.

---

## Option A — **Production-like proof** (recommended if CI is trusted)

Trigger a harmless deploy (tiny image tag churn or **`kubectl rollout restart`** on **dev**):

1. `kubectl -n dev rollout restart deployment/items deployment/outfits deployment/schedule deployment/web`
2. Parallel terminals:
   ```bash
   kubectl -n dev rollout status deployment/web --timeout=5m
   ```
   ```bash
   FRONTEND_HOST=app-dev.claiset.xyz bash infra/scripts/http-availability-during-rollout.sh 400
   ```
3. Redirect the curl loop to **`docs/evidence-media/C6-rollout-http-log.txt`** and screen-record (**silent**) or include in slide as **snippet**.

**Interpretation:** If HTTP codes stay **`2xx`/`301`/`302`** (anything but hung **5xx** streams), narrative **“zero dropped requests meaningful to users.”**

---

## Option B — **GitHub Actions / promotion workflow**

Reuse the **successful** **`promotion`** run where **smoke** passed after apply; export:

- Workflow **summary** (**green**) + **`smoke-test-env.sh`** excerpt from logs (shows API checks).

If the video **`C6-rollout-or-deployment-recording.mov`** already aligns, **rename/annotate** via [`docs/evidence-media/MEDIA_MAPPING.txt`](evidence-media/MEDIA_MAPPING.txt) so graders know **which** clip proves **zero downtime.**

---

## What “good enough” looks like on video

10–45 s is fine:

- Left: **`rollout status` advancing**
- Right: **`http-availability-during-rollout.sh`** (**no prolonged `503`/`502`**)

If **`replicas == 1`**, micropauses can occur—explain **RollingUpdate keeps old Pod until Ready new Pod** aligns with syllabus **intent**.

---

## Checklist alignment

See **`### C6`** in [`evidence-media-checklist.md`](evidence-media-checklist.md) — update notes + embed **MOV**/**log** filenames once refreshed.
