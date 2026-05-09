# Justification: Partial (Hosted-Service) Canary on EKS

**Course requirement (summary):** Choose and justify **either** a Blue/Green-style deployment **or** a **Canary** deployment for applications on EKS.  
**This document:** Explains why **partial canary**—implemented as a **progressive `RollingUpdate`** with **readiness gates**, **bounded surge**, **post-readiness soak**, and **optional PodDisruptionBudgets**—is an appropriate, defensible choice and how it maps to the rubric.

**Where it is implemented:** Terraform module [`infra/modules/eks-app`](../infra/modules/eks-app), with **stricter** rollout parameters in **`infra/envs/uat/main.tf`** and **`infra/envs/prod/main.tf`**. A shorter overview also appears in the [README § Progressive rollout strategy](../README.md#progressive-rollout-strategy-eks).

---

## 1. What we chose (and what we did not)

We **did not** implement **classical Blue/Green** in the sense of maintaining **two full, simultaneously scaled “live” stacks** (e.g. duplicate Deployments per service under different labels) and **flipping** all traffic in one action. That pattern would roughly **double** transient capacity for **four** backend-style workloads plus a **web** frontend on the same cluster, which is costly and operationally heavy on **small managed node groups**—the same constraint called out in many student and small-team EKS setups.

We **did** implement a **canary-oriented** model that fits Kubernetes’ first-class primitive: the **Deployment** with **`RollingUpdate`**. The rubric’s “Canary” option is about **reducing blast radius** during promotion by **exposing new versions gradually** and **validating health** before fully committing. Native rolling update, when tuned carefully, delivers that outcome **without** a separate traffic-shaping product.

We also **did not** implement **HTTP percentage–based** canary (e.g. 5% → 50% → 100% of requests to the new revision via load balancer weights or a rollout controller). That would be a natural **Phase 2** (Argo Rollouts, ALB/Ingress canary annotations, or a mesh). The scope here is **deliberately** the **Kubernetes baseline**: progressive replacement of Pods with **strong health and timing gates**.

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

## 5. Optional future work (if “full” canary is required later)

- **Argo Rollouts** or **Flagger** for **metric-driven** promotion and **traffic splitting**.  
- **ALB / Ingress** canary or **weighted target groups** for **percentage** exposure per revision.

Until then, the **partial canary** described here is **intentionally complete**: it is **documented**, **encoded in Terraform**, and **gradable** as a **Canary** strategy aligned with native Kubernetes operations.
