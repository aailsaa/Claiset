# Assignment requirements (course brief)

**Back to project overview:** [README.md](README.md)
---

## 1. Application architecture

| Requirement | Done? | Your notes |
| ----------- | ----- | ---------- |
| **Frontend** — polished UI | [x] | |
| **Database** — **AWS RDS only** in cloud (no “local DB in prod”) | [x] | |
| **Backend** — **≥ 3 microservices** | [x] | |
| **Frontend on custom DNS with SSL (HTTPS) fully configured** | [x] | |
| **IaC** — **Every** resource for **EKS, RDS, VPC, IAM** (and related wiring) via **Terraform only** — no ClickOps as the primary path | [x] | |
| **Day 1 + Day 2 automation** — initial setup and updates **fully automated** (Terraform + CI) | [x] | |

---

## 2. Deployment & CI/CD (git-driven promotion)

| Requirement | Done? | Your notes |
| ----------- | ----- | ---------- |
| **Flow** — **Dev → Nightly QA → UAT → Prod** | [x] | Implemented in Actions workflow; nightly QA and manual targets verified. Prod trigger via tag/manual is implemented; final green evidence run still being stabilized under free-tier capacity constraints. |
| **Dev/QA → UAT** — **Conventional Commits** (e.g. `RC1`) **or** **PR merges** must trigger UAT automatically | [x] | **PR merge → UAT** (same repo). **RC** token on `main` still works for direct pushes. Add `RC1`-style in message if grader wants explicit conventional examples. |
| **UAT → Prod** — **Release tags** (e.g. `v1.0.1`); **no** primary path via **click-to-deploy in AWS Console** | [x] | `v*` tags + manual workflow target |
| **Strategy** — Choose and **justify** **Blue/Green** *or* **Canary** for EKS | [ ] | Currently implemented as **rolling Deployments** (module name `app-bluegreen`). Add write-up + demo narrative mapping this to the chosen strategy (or implement true blue/green/canary). |
| **Zero downtime** — Promotions/updates must **not drop requests** | [ ] | Controls are in place (rolling deploy + readiness/liveness probes + staged smoke checks), but grader-proof evidence still needed: continuous request stream + no 5xx during rollout. |

---

## 3. Mandatory “Day 2” scenarios (live or narrated video)

| Requirement | Done? | Your notes |
| ----------- | ----- | ---------- |
| **OS / security patching** — EC2 worker **AMI** updates **without interrupting service** | [ ] | Runbook approach prepared (nodegroup rolling replacement + readiness/smoke validation). Need one recorded/live execution with before/after node versions and no user-facing downtime. |
| **Schema changes** — Deploy change that **updates RDS schema**; **explain + demonstrate** how migrations apply | [x] | Implemented via `migrate` Kubernetes Job (`claiset-migrate` image) before app deployment. For demo: show Job creation/completion and resulting app behavior. |

---

## 4. Observability & logging (**self-hosted on EKS only**)

| Requirement | Done? | Your notes |
| ----------- | ----- | ---------- |
| **Prometheus + Grafana** on-cluster (**no** AWS-managed observability as substitute) | [x] | Deployed via Terraform/Helm in `monitoring`. Verified in dev/qa/uat and repeatedly exercised in prod troubleshooting. Capture one clean prod screenshot set for final rubric proof. |
| **Dashboards** — **CPU, memory, disk** for **all nodes** | [x] | Node Exporter + Prometheus dashboards are present; metrics visible in non-prod. Final evidence needed: prod node metrics screenshots (CPU/memory/disk) during/after rollout. |
| **Alerts** — **Email** and/or **Slack** at critical thresholds | [ ] | SMTP wiring completed in Terraform/workflow (`TF_VAR_alertmanager_*`). Remaining proof: trigger drill, show received email, then revert drill. |
| **Grafana** — reachable **from outside AWS** | [x] | External ALB ingress + DNS configured. Non-prod confirmed; prod URL has been provisioned in runs and needs one final stable screenshot proof in final demo. |
| **Grafana auth** — **OAuth2 only** (Okta/GitHub/Google); **no** username/password as primary UX | [x] | **Google OAuth** end-to-end in **dev, QA, UAT**; repo preflight + smoke checks catch empty OAuth secrets. Confirm **prod** after release. |
| **Centralized logging** — **Loki** or ELK/OpenSearch **or** self-hosted Sentry on EKS | [x] | Loki + Promtail installed via Terraform and validated in non-prod; prod hardening complete (timeouts/capacity/CNI guardrails). Final evidence capture pending stable prod run screenshots. |
| **Multi-service logs** — Query across **all 3** Go backends | [x] | Query path implemented and tested; final deliverable is screenshot/video of one query per service (items/outfits/schedule) plus combined filter in prod. |

---

## 5. Presentation & defense

| Requirement | Done? | Your notes |
| ----------- | ----- | ---------- |
| **Silent video rule** — Long-running parts (e.g. Day 1) may use **silent** video only | [ ] | |
| **Live narration** — Explain technical decisions and workflow over demo/video | [ ] | |
| **Live chaos defense** — Instructor triggers failure; you use **monitoring + logging** to diagnose and explain recovery **in ~1–2 minutes** | [ ] | Story is prepared from real incident history (pod-slot exhaustion, CNI limits, rollout recovery). Need one timed practice run with commands + explanation flow. |

---

## Rubric (for self-grading comments)

| Category | Weight | Aligns with sections |
| -------- | -----: | --------------------- |
| Infrastructure (Terraform) | 20% | Section 1 + state hygiene, modules |
| Application & networking | 15% | Section 1 TLS/DNS + section 2 zero downtime |
| CI/CD & GitOps logic | 15% | Section 2 |
| Day 2: OS patching | 10% | Section 3 patching |
| Day 2: Schema | 10% | Section 3 schema |
| Observability & logging | 15% | Section 4 |
| Presentation & defense | 15% | Section 5 + soft-skills listed in syllabus |

### Presentation soft-skills (from syllabus)

The “So What?” factor • Handling friction • Narrative arc • Visual command • Confidence in the unknown • Delivery (eye contact, pace, fillers, pauses).

**WOW-factor:** Discretionary note from instructor (“no other considerations”).

---

### Your accomplishment comments (submission)

_Use this subsection or attach separately per course instructions._

- **Architecture:**
- **CI/CD:**
- **Day 2:**
- **Observability:**
- **Presentation / chaos:**  
