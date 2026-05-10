# Justification: Partial (Hosted-Service) Canary on EKS

**Course requirement (summary):** Choose and justify **either** a Blue/Green-style deployment **or** a **Canary** deployment for applications on EKS.  
**This document:** Explains why **partial canary**—implemented as a **progressive `RollingUpdate`** with **readiness gates**, **bounded surge**, **post-readiness soak**, and **optional PodDisruptionBudgets**—is an appropriate, defensible choice and how it maps to the rubric.

**Where it is implemented:** Terraform module [`infra/modules/eks-app`](../infra/modules/eks-app), with **stricter** rollout parameters in **`infra/envs/uat/main.tf`** and **`infra/envs/prod/main.tf`**. A shorter overview also appears in the [README § Progressive rollout strategy](../README.md#progressive-rollout-strategy-eks).

---

## 1. What we chose (and what we did not)

We **did not** implement **classical Blue/Green** in the sense of maintaining **two full, simultaneously scaled “live” stacks** (e.g. duplicate Deployments per service under different labels) and **flipping** all traffic in one action. That pattern would roughly **double** transient capacity for **four** backend-style workloads plus a **web** frontend on the same cluster, which is costly and operationally heavy on **small managed node groups**—the same constraint called out in many student and small-team EKS setups.

We **did** implement a **canary-oriented** model that fits Kubernetes’ first-class primitive: the **Deployment** with **`RollingUpdate`**. The rubric’s “Canary” option is about **reducing blast radius** during promotion by **exposing new versions gradually** and **validating health** before fully committing. Native rolling update, when tuned carefully, delivers that outcome **without** a separate traffic-shaping product.

We **did not** duplicate **four Go microservices** behind percentage routing (cost and scheduling pressure on small node groups). We **did** add an **optional ALB weighted forward** path on **Ingress `/` only** (the React SPA): stable Service **`web`** vs **`web-canary`** share browser traffic by weight when enabled (see **§5**). **API** routes (`/api/v1/...`) stay single-target. **Mesh-wide** or **Argo Rollouts–style** automatic ramp remains optional **Phase 2** (§6).

---

## 2. How the implementation behaves (partial canary mechanics)

1. **`maxUnavailable: 0`**  
   During an image or spec change, the cluster does **not** deliberately terminate **Ready** Pods of the old revision until replacement Pods of the new revision are **Ready** (subject to scheduler and resource limits). There is no intentional “dip” in declared replica capacity for the rollout itself.

2. **`maxSurge: 1` in UAT and Production**  
   At most **one extra** Pod of the new revision may run beyond the desired count at a time. With **more than one** replica (UAT’s default), that means **stepped** replacement: a small **wave** of new capacity is tried before the controller retires old Pods. With **one** replica (current Production choice for node headroom), surge still allows the **new** Pod to come up alongside the **old** until the new Pod passes gates—then the old Pod is removed.

3. **`minReadySeconds` soak (20s UAT, 30s Prod)**  
   After a Pod becomes **Ready** (including passing the **HTTP `/health`** readiness probe on backends and **`/`** on `web`), it must **remain** Ready for the soak interval before the Deployment controller treats the ReplicaSet as having **progressed**. That is a lightweight **“observe before promote”** step: it catches **flapping** readiness, **slow leaks**, or **intermittent** faults that a single successful probe might not surface.

4. **Readiness and liveness probes**  
   **Services** only send traffic to Pods that are **Ready**. Unready Pods do not receive production traffic from the cluster Service in front of them, which is the core **safety** property graders expect from a canary story.

5. **`PodDisruptionBudget` when `replicas > 1`**  
   During **voluntary** disruption (node drain, upgrades), a minimum fraction of Pods stays available. That is not the same as an image rollout, but it **aligns** the overall story: **do not take the whole service down at once** when the platform moves underneath the workload.

6. **Dev / QA**  
   These environments keep **faster** defaults (`maxSurge` **25%**, `minReadySeconds` **0**) so **inner-loop** development and scheduled QA runs are not slowed by the same soak policy as pre-production and production.

---

## 3. Rubric alignment (why this is “Canary” for grading purposes)

- **Progressive change:** New software enters the cluster in **controlled steps** (bounded surge, ordered replacement), not as a **single** cutover of every Pod at once.  
- **Validation before commitment:** **Readiness** plus **`minReadySeconds`** are **automated promotion criteria** before old Pods are retired—functionally similar in spirit to **canary analysis** stages, expressed with **built-in** Kubernetes semantics.  
- **Blast radius:** A bad build is **more likely** to fail the rollout **before** all replicas run the bad revision, especially in UAT where **two** replicas and **PDB** interact with **surge 1**.  
- **Explicit tradeoff:** We state clearly that we are **not** claiming **traffic-percent** canary; we are claiming **instance-level progressive rollout canary**, which is a **standard** industry pattern when teams have not yet adopted a dedicated rollout controller.

---

## 4. Why not full Blue/Green here

Blue/Green is a **valid** rubric option, but it optimizes for **instant cutover** and **easy rollback** at the cost of **running two full versions** of every component (or complex shared-db semantics) during the switch. For **multiple microservices** on **shared** node groups, that cost is **high** relative to the **risk reduction** we need for this project. **Rolling partial canary** meets the **same risk-reduction intent** with **less** duplicate capacity and **less** orchestration code to maintain before deadlines and demos.

---

## 5. ALB traffic-weighted canary (browser SPA)

**Implemented** in [`infra/modules/eks-app`](../infra/modules/eks-app): variables **`enable_alb_weighted_canary_for_web`**, **`alb_web_canary_traffic_percent`**, and **`web_canary_replicas`**. When all are active, the **AWS Load Balancer Controller** applies an **`alb.ingress.kubernetes.io/actions.*`** **weighted `forward`** on the Ingress rule for **`/`** only, splitting traffic between Service **`web`** (stable) and **`web-canary`** (same image by default; separate Deployment so you can roll the SPA independently). **`web-canary`** is always defined when the app module is on, but runs **0 replicas** unless weighted canary is enabled—**no extra nginx cost** in dev/qa/prod defaults.

**UAT** defaults this on (**10%** canary) via **`infra/envs/uat/variables.tf`** (passed into `module "eks_app"`). **Prod/dev/qa** default **off** in their `variables.tf`. **GitHub Actions:** set repository **Variables** per env — **`ALB_CANARY_UAT_ENABLED`** (`false` disables; unset keeps canary on), **`ALB_CANARY_UAT_TRAFFIC_PERCENT`**, **`ALB_CANARY_UAT_WEB_REPLICAS`**; **`ALB_CANARY_DEV_*`**, **`ALB_CANARY_QA_*`**, **`ALB_CANARY_PROD_*`** with the same suffix pattern (`ENABLED`, `TRAFFIC_PERCENT`, `WEB_REPLICAS`). See **`.github/workflows/promotion.yml`** job `env` blocks. **Local** `terraform apply` can still use **`TF_VAR_enable_alb_weighted_canary_for_web`**, **`TF_VAR_alb_web_canary_traffic_percent`**, **`TF_VAR_web_canary_replicas`**.

**Availability:** While weighted routing is active, the module sets **`web-canary` replicas to max(your value, 2)** so **`RollingUpdate` + `maxUnavailable: 0`** never leaves the canary Service with **zero Ready** endpoints (which would make ALB drop the canary traffic share). Stable **`web`** keeps the same rollout semantics as before (**`maxUnavailable: 0`**, soak, **`preStop`**), so the **90%** stable path preserves the same **no intentional capacity dip** story during image promotion.

**Scaling / cost:** Canary adds **two** nginx Pods at minimum when the split is on (not one). Pod anti-affinity prefers spreading **`web`**, **`web-canary`**, and backends across nodes. If a promotion is tight on headroom, lower **`alb_web_canary_traffic_percent`** or set **`enable_alb_weighted_canary_for_web = false`** for that env.

## 6. Further optional hardening

- **Argo Rollouts** or **Flagger** for **metric-driven** promotion and **automatic** weight ramp.  
- **Service mesh** or **per-API** weighted rules if backends need revision-split traffic too.

Together, **§2–§5** are **documented** and **Terraform-encoded**: **rolling partial canary** for all workloads, plus **optional ALB % split** for the SPA where enabled—**gradable** as **Canary** without classical dual-stack Blue/Green for every microservice.
