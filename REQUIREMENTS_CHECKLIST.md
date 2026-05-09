# Assignment Requirements Checklist (Proof-Oriented)

**Back to project overview:** [README.md](README.md)  
**Source requirements (unaltered):** [REQUIREMENTS.md](REQUIREMENTS.md)

**Screenshots / recordings bundle:** curated list with embedded media → **[docs/evidence-media-checklist.md](docs/evidence-media-checklist.md)** · files under **`docs/evidence-media/`** · rename map → **`docs/evidence-media/MEDIA_MAPPING.txt`**

Use this file as the **requirements matrix** (status + what to capture + short notes). Use **`docs/evidence-media-checklist.md`** when you need the detailed media walkthrough.

**Status snapshot:** Dev + UAT have been green with recent fixes on **`main`**. Embed new captures in **`docs/evidence-media-checklist.md`** first, then summarize filenames or links in the fourth column below.

### Code & infrastructure vs evidence (full `%` HTTP canary intentionally out)

The following maps **syllabus implementation** (what ships in **`main`**) to **what you still owe for grading**. **Presentation (§5)** and **capturing screenshots/video** are separate from “is it built?” **Full traffic-weighted canary** is **not** implemented; **progressive RollingUpdate canary** is—see **`docs/partial-canary-justification.md`**.

| Syllabus topic | Implemented in repo | Still on you for a complete grade |
| --- | --- | --- |
| **§1 App + RDS + 3µs + HTTPS** | `web/`, `infra/modules/{rds,eks-app,platform}`, Ingress/ACM | Optional polish: **`A2`/`A3`/`A6`** media if graders dig into IaC screenshots |
| **§1 IaC + Day 1/Day 2 automation** | All AWS/K8s in **`infra/`**; **`promotion.yml`** | **`C1`–`C4`** URLs/stills optional but strong |
| **§2 Git promotion** | **dev**: push **`main`**; **qa**: schedule + **`workflow_dispatch`**; **uat**: merged same-repo **`pull_request`** to **`main`** or RC path + manual `uat`; **prod**: **`v*`** tags + **`workflow_dispatch`** (**requires** repo variable **`ALLOW_COSTLY_RUNS=true`** for prod dispatch) | Point graders at green runs |
| **§2 Canary (not dual-stack BG, not `%` HTTP)** | **`infra/modules/eks-app`** `RollingUpdate`, **`maxUnavailable` 0**, UAT/Prod **`maxSurge` 1** + **`minReadySeconds` soak**, PDB when **`replicas>1`**; **`docs/partial-canary-justification.md`** | Slide pointer + oral defense |
| **§2 Zero downtime** *(behavior)* | Probes + rollout strategy above + CI smoke **`smoke-test-env.sh`** | **Artifact:** **`C6`** recording or HTTP log (**`docs/zero-downtime-promotion-evidence.md`**) |
| **§3 OS patching** *(mechanism)* | **`aws_eks_node_group`** rolling **`max_unavailable_percentage`**; **`docs/day2-os-node-patching.md`**, **`eks-node-patch-evidence.sh`** | **Live/console proof** when AMI update exists (**P1–P3**) |
| **§3 Schema change** | **`cmd/migrate`**, **`schema.sql`**, K8s **`migrate` Job** before app Deployments | Explain narrative; optionally ship a trivial **`schema.sql`** addition so a future deploy visibly “did a migration” |
| **§4 Self-hosted Prometheus+Grafana** | **`infra/modules/platform/observability.tf`** `kube-prometheus-stack` when **`enable_observability_stack`** (+ CI **`ENABLE_OBSERVABILITY`** + secrets) | Keep observability **`true`** for demo env used in defense |
| **§4 Dashboards CPU / mem / disk** | Node exporter (when daemonset flags + **`ALLOW_COSTLY_RUNS`**), bundled rules/dashboards | Your existing **`O5`** captures |
| **§4 Alerts → email *(and/or Slack)*** | **Email:** Alertmanager + SMTP (**only if** **`ALERTMANAGER_*`** secrets populated in GitHub → `TF_VAR_*`) | **`O7`:** run **`infra/scripts/alert-drill.sh`**, inbox screenshot (**Slack** path not coded—**email alone** meets “and/or”) |
| **§4 Grafana external + OAuth only** | Google OAuth + **`disable_login_form`** in Helm Grafana values | Your **`O2–O6`** recording |
| **§4 Central logging + multi-service queries** | Loki + Promtail Helm; Grafana Loki datasource | **`O6`** clip section |
| **§5 Presentation / chaos** | *Not infra* | Silent video (**S1** quality check), live narration, timed chaos rehearsal |

**Bottom line:** **Implementation requirements** (excluding full `%` canary and presentation) are **covered by the codebase** assuming **Observability** and **SMTP** secrets are configured where you demo. Left work is **`O7` evidence**, **`C6` evidence**, **`P1–P3` evidence**, **`S1`/chaos rehearsal**, optional **`A*`/`C*` stills**, and self-grading comments at the bottom of this file.

---

## 1) Application Architecture

| Requirement | Status | Required proof (exact artifact to capture) | Current evidence / notes |
| --- | --- | --- | --- |
| Frontend exists and is polished | [x] | App homepage **and** one other functional page; rubric cites prod — in defense note **dev**/prod parity. | **`A1-app-home.png`**, **`A1-app-inner.png`** + extras — see **`### A1`** in [docs/evidence-media-checklist.md](docs/evidence-media-checklist.md). |
| Database is AWS RDS only | [x] | AWS console RDS **Available** + `terraform state list` showing RDS. | **`A2-rds-console.png`**, **`A3-terraform-state.png`** — [evidence-media-checklist.md](docs/evidence-media-checklist.md) §A2–A3. |
| Backend has at least 3 microservices | [x] | `kubectl get deploy` **`items`**, **`outfits`**, **`schedule`**. | **`A4-kubectl-deploy.png`** (also shows **`web`**) — see **`### A4`** in [docs/evidence-media-checklist.md](docs/evidence-media-checklist.md). |
| Frontend on custom DNS with HTTPS | [x] | Browser HTTPS lock + Ingress/ALB mapping. | **`A5-kubectl-ingress.png`**; HTTPS extras under **`### A1`** in [docs/evidence-media-checklist.md](docs/evidence-media-checklist.md). |
| EKS / RDS / VPC / IAM managed by Terraform | [x] | `terraform state list` excerpt + **`infra/modules/`** tree or file samples. | **`A3-terraform-state.png`** (+ continuation) — [evidence-media-checklist.md](docs/evidence-media-checklist.md) §A3; **A6** still optional in §A6. |
| Day 1 + Day 2 automated | [x] | GitHub Actions runs + Terraform apply logs. | Silent slice: **`S1-terraform-apply-or-infra-recording.mov`**; **`C1`**, **`C2`**, **`C4`** stills in [evidence-media-checklist.md](docs/evidence-media-checklist.md) §C1–C4. |

---

## 2) Deployment & CI/CD (Git-Driven Promotion)

| Requirement | Status | Required proof (exact artifact to capture) | Current evidence / notes |
| --- | --- | --- | --- |
| Dev → nightly QA → UAT → Prod flow | [x] | Workflow graph with successful transitions. | **`C1-actions-promotion-workflow.png`** — **`### C1`** in [docs/evidence-media-checklist.md](docs/evidence-media-checklist.md). |
| Dev/QA → UAT via conventional commit / PR merge | [x] | Run from merged PR **`or`** `RC` in commit message. | **`C2-pull-request-merged-uat-actions.png`** — **`### C2`** in [docs/evidence-media-checklist.md](docs/evidence-media-checklist.md). |
| UAT → Prod via tags / gated dispatch (no console deploy) | [x] | Tag or **`workflow_dispatch`** prod with refs visible. | **`C3-…`** — **`### C3`** in [docs/evidence-media-checklist.md](docs/evidence-media-checklist.md). |
| Blue/Green **or** Canary chosen and justified | [x] | README / slide + strategy reflected in infra code. | **Justification:** [docs/partial-canary-justification.md](docs/partial-canary-justification.md) · **Overview + table:** [README — progressive rollout](README.md#progressive-rollout-strategy-eks) · Code: **`infra/modules/eks-app`**, **`maxSurge: 1`** + **`minReadySeconds`** soak in **UAT/Prod**. *(Rubric: “Blue/Green or Canary”; we document progressive rolling canary, not dual-stack BG or HTTP % split.)* |
| Zero downtime during promotion | [ ] | Short video/log: no elevated 5xx during rollout + rollout succeeded. | **How-to:** **[docs/zero-downtime-promotion-evidence.md](docs/zero-downtime-promotion-evidence.md)** · **`infra/scripts/http-availability-during-rollout.sh`**. Artifacts: **`C6-rollout-or-deployment-recording.mov`** (dev), **`C6-uat-*.mov`** + **`C6-http-during-rollout-uat.txt`** (UAT); verify **[docs/evidence-media/MEDIA_MAPPING.txt](docs/evidence-media/MEDIA_MAPPING.txt)**. |

---

## 3) Mandatory Day-2 Scenarios

| Requirement | Status | Required proof (exact artifact to capture) | Current evidence / notes |
| --- | --- | --- | --- |
| OS/security patching of worker nodes without outage | [ ] | Before/after AMI or nodegroup + smoke during rotation. | **Runbook:** **[docs/day2-os-node-patching.md](docs/day2-os-node-patching.md)** · **`infra/scripts/eks-node-patch-evidence.sh`**. Evidence filenames: **`P1`** / **`P2`** / **`P3`** section in **[docs/evidence-media-checklist.md](docs/evidence-media-checklist.md)**. |
| Schema change deployment (migrate job) + explanation | [x] | `kubectl get jobs` migrate **Complete** + `describe job migrate`. | **`D1-migrate-job.png`**, **`D2-migrate-describe.png`** — **`### D1` / `D2`** in [docs/evidence-media-checklist.md](docs/evidence-media-checklist.md). |

---

## 4) Observability & Logging (Self-Hosted on EKS)

| Requirement | Status | Required proof (exact artifact to capture) | Current evidence / notes |
| --- | --- | --- | --- |
| Prometheus + Grafana self-hosted on EKS | [x] | `kubectl -n monitoring get pods` + Grafana in UI/recording. | **`O1-monitoring-pods.png`**, **`EXTRA-O1-…`**; tour **`O2-O6-grafana-and-observability.mov`**. |
| Dashboard: node CPU / memory / **disk** | [x] | Panels or Explore proving all three. | **`EXTRA-O5-grafana-node-exporter-cpu-mem.png`**, **`EXTRA-O5-grafana-dashboard-disk-io-disk-space-empty.png`**, **`O5-disk-capacity-explore.png`**. |
| Alerts to Email / Slack | [ ] | Alert drill output + **received** notification. | Run **`infra/scripts/alert-drill.sh`**; add **`O7-…`** — **`### O7`** in [docs/evidence-media-checklist.md](docs/evidence-media-checklist.md). |
| Grafana externally reachable | [x] | `https://grafana-<env>.<domain>` from outside AWS. | URL bar + flow in **`O2-O6-…`** (e.g. **grafana-dev**); narrate env in defense. |
| Grafana OAuth2 (no password-primary login) | [x] | Google OAuth path into Grafana. | **`EXTRA-app-dev-login-google.png`** + **`O2-O6-…`**. |
| Centralized logging (Loki stack) | [x] | Datasource / Explore path to Loki. | **`loki`** pod in **`O1`** ; queries in **`O2-O6-…`** — see **Observability** section headers in [docs/evidence-media-checklist.md](docs/evidence-media-checklist.md). |
| Query logs across all three backends | [x] | **`items`** / **`outfits`** / **`schedule`** filters + broader query. | Demonstrated in **`O2-O6-…`** — **`### O6`** in [docs/evidence-media-checklist.md](docs/evidence-media-checklist.md). |

---

## 5) Presentation & Defense

| Requirement | Status | Required proof (exact artifact to capture) | Current evidence / notes |
| --- | --- | --- | --- |
| Silent video — long-running parts | [ ] | Submitted silent provision/deploy/destruct excerpt. | **`S1-terraform-apply-or-infra-recording.mov`** (verify content). |
| Live narration over video / demo | [ ] | You speak live over silent clips during grading. | Talking points: **[docs/final-defense-script.md](docs/final-defense-script.md)**. |
| Live chaos defense (~1–2 min) | [ ] | Timed practice — failure → diagnosis → mitigation with metrics/logs. | Bookmarks/queries only; rehearsal, not a second recording. |

---

## Final Evidence Bundle (before submission)

- **Media index (with embeds):** [docs/evidence-media-checklist.md](docs/evidence-media-checklist.md)
- **Plain files:** `docs/evidence-media/*.png`, `*.mov`
- Still **recommended** if graders ask: RDS console (**A2**), **`terraform state list`** (**A3**), **`infra/modules`** tree (**A6**), Actions graph / dispatch shots (**C1–C4**), alert inbox (**O7**); **§3 patching** runbook **[docs/day2-os-node-patching.md](docs/day2-os-node-patching.md)**; **zero downtime** **[docs/zero-downtime-promotion-evidence.md](docs/zero-downtime-promotion-evidence.md)**

---

## Rubric Reference

| Category | Weight | Maps to sections |
| --- | ---: | --- |
| Infrastructure (Terraform) | 20% | Section 1 |
| Application & networking | 15% | Sections 1–2 |
| CI/CD & GitOps logic | 15% | Section 2 |
| Day 2: OS patching | 10% | Section 3 |
| Day 2: Schema | 10% | Section 3 |
| Observability & logging | 15% | Section 4 |
| Presentation & defense | 15% | Section 5 |

### Submission comments template

- Architecture:
- CI/CD:
- Day 2:
- Observability:
- Presentation / chaos:
