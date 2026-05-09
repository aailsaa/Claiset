# Day 2: OS / security patching on EKS worker nodes (runbook)

**Rubric intent:** Change the **underlying worker AMIs / nodegroup release** (security patches) **without** taking the workload down for an extended outage. Explain **cordoning, draining, replacement order**, and how you verify the app stays healthy.

**What you already have in Terraform**

- **`aws_eks_node_group.default`** ([`infra/modules/eks/main.tf`](../infra/modules/eks/main.tf)) is a **managed node group**.
- **`update_config { max_unavailable_percentage = 33 }`** lets AWS replace nodes in rolling fashion (within that cap)—this is your **automated parallelism** language for graders (*“max unavailable during update”*).

Pods are evicted gracefully when a node drains; combined with **`RollingUpdate`** on Deployments (**`infra/modules/eks-app`**) and **PDB** when **`replicas > 1`**, workloads should reschedule onto new nodes rather than disappearing.

---

## 1. Evidence to capture (**P1–P3** alignment)

Use [`infra/scripts/eks-node-patch-evidence.sh`](../infra/scripts/eks-node-patch-evidence.sh) **before** and **after** the update:

| Artifact | Example |
| --- | --- |
| **Before** console or CLI snapshot | **`P1-before-nodegroup`** — `describe-nodegroup`: `releaseVersion`, `kubernetesVersion`, `status` |
| **After** snapshot | **`P2-after-nodegroup`** — same fields **changed** (new `releaseVersion` or AMI line in console) |
| **Healthy service during / after rotation** | **`P3-patch-smoke`** — green [`smoke-test-env.sh`](../infra/scripts/smoke-test-env.sh), or Grafana / manual curl while nodes churn |

Suggested filenames under `docs/evidence-media/`: **`P1-nodegroup-before.png`**, **`P2-nodegroup-after.png`**, optional **`P3-patch-smoke-terminal.txt`** (redirect script output).

---

## 2. Preflight

```bash
export AWS_REGION=us-east-1
export CLUSTER=claiset-dev          # or qa / uat / prod
export NODEGROUP=${CLUSTER}-default

aws eks update-kubeconfig --region "${AWS_REGION}" --name "${CLUSTER}"
bash infra/scripts/eks-node-patch-evidence.sh "${CLUSTER}" "${NODEGROUP}"
```

Perform the **before** snapshot (script + screenshots).

---

## 3. Trigger a genuine patch (pick one path)

### A. AWS Console (**easiest demo**)

1. Open **Amazon EKS** → your cluster → **Compute** → select the **managed node group** (`claiset-<env>-default`).
2. Choose **Update** / **Upgrade** when the console offers a newer **AMI release version** or **Kubernetes** patch version aligned with docs.
3. Confirm; wait until status returns to **Active** and nodes show the new AMI / release.

### B. AWS CLI (**scriptable narrative**)

1. Inspect current revision:

```bash
aws eks describe-nodegroup \
  --region "${AWS_REGION}" \
  --cluster-name "${CLUSTER}" \
  --nodegroup-name "${NODEGROUP}" \
  --query 'nodegroup.{Version:version,ReleaseVersion:releaseVersion,Status:status}' \
  --output table
```

2. List upgrades available from AWS (**exact flag names vary by CLI version**; if `list-node-versions` isn’t present, rely on Console or [EKS AMI release docs](https://docs.aws.amazon.com/eks/latest/userguide/eks-linux-ami-release-versions.html)):

```bash
aws eks describe-nodegroup --region "${AWS_REGION}" \
  --cluster-name "${CLUSTER}" --nodegroup-name "${NODEGROUP}" --output json
```

3. Start update (Kubernetes version bump **or** new releaseVersion when supported):

```bash
aws eks update-nodegroup-version \
  --region "${AWS_REGION}" \
  --cluster-name "${CLUSTER}" \
  --nodegroup-name "${NODEGROUP}"
  # Optionally: --kubernetes-version 1.xx  OR  --release-version amzn-eks-xxx
```

4. Wait until active:

```bash
aws eks wait nodegroup-active --region "${AWS_REGION}" \
  --cluster-name "${CLUSTER}" --nodegroup-name "${NODEGROUP}"
```

---

## 4. During the roll (grading story)

While nodes recycle:

```bash
kubectl get nodes -o wide --watch    # Ctrl+C when done (optional)
```

In another terminal, keep **`FRONTEND_HOST`** warm (adjust host):

```bash
FRONTEND_HOST=app-dev.claiset.xyz bash infra/scripts/http-availability-during-rollout.sh 600
```

You want **no long burst of 5xx / connection refused** — brief blips on a tiny node swap can happen; graders care about **logic** and clear **before/after** plus **verification**.

After nodes settle, rerun **`smoke-test-env.sh`** for that env (same variables as `.github/workflows/promotion.yml` **Wait for readiness** step).

---

## 5. What to say verbally (**P4** slide / defense ~1 slide)

Cover these points (**match what AWS actually did**):

- **Managed node group** performs replacements; **`maxUnavailablePercentage`** in Terraform caps how aggressive the churn is vs capacity.
- **kubelet** drains with **SIGTERM → gracePeriod → eviction** for Pods; workloads with **multiple replicas / PDB** keep **Service** endpoints usable.
- **Single-replica prod** (`replicas == 1` in your **`eks_app`**) tolerates patching **less gracefully** during the exact window **one Pod** moves—state honest: **prefer patching dev/uat first** or **briefly bump replicas** during demo if graders allow spend.

Optional improvement if time: **Cordoning** manually is rarely needed with managed NG updates—you can still mention **`kubectl cordon`** / **`drain`** for **self-managed** or **custom** rollback stories.

---

## 6. If “no update offered” today

Rarely **EKS marks the node group “latest”**. Options:

1. Narrate readiness with **`describe-nodegroup`** + **Terraform excerpt** (**`max_unavailable_percentage`**) anyway; state you would apply when AWS publishes a newer **release**.
2. **Terraform-only** substantive change (**smaller kube patch** coordinated with **`node_group_kubernetes_version`** env tfvars) triggers a roll—only if acceptable for homework risk.

Treat **AMI / release** updates as preferred because they mirror **security patching** language in the syllabus.
