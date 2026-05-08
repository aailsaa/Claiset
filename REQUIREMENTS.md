# Assignment requirements (course brief)

**Back to project overview:** [README.md](README.md)

Use the **Your notes** column when you self-grade / submit comments.

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
| **Flow** — **Dev → Nightly QA → UAT → Prod** | [x] | QA scheduled + manual; teardown optional for cost |
| **Dev/QA → UAT** — **Conventional Commits** (e.g. `RC1`) **or** **PR merges** must trigger UAT automatically | [x] | **PR merge → UAT** (same repo). **RC** token on `main` still works for direct pushes. Add `RC1`-style in message if grader wants explicit conventional examples. |
| **UAT → Prod** — **Release tags** (e.g. `v1.0.1`); **no** primary path via **click-to-deploy in AWS Console** | [x] | `v*` tags + manual workflow target |
| **Strategy** — Choose and **justify** **Blue/Green** *or* **Canary** for EKS | [ ] | Module name `app-bluegreen`; implementation is **rolling Deployments** — document mapping + justification. |
| **Zero downtime** — Promotions/updates must **not drop requests** | [ ] | Rolling + probes; prepare **demo/narration** per rubric. |

---

## 3. Mandatory “Day 2” scenarios (live or narrated video)

| Requirement | Done? | Your notes |
| ----------- | ----- | ---------- |
| **OS / security patching** — EC2 worker **AMI** updates **without interrupting service** | [ ] | Document + **demo** (drain / roll / verify). |
| **Schema changes** — Deploy change that **updates RDS schema**; **explain + demonstrate** how migrations apply | [x] | `cmd/migrate` + Job; still need grader-facing **walkthrough**. |

---

## 4. Observability & logging (**self-hosted on EKS only**)

| Requirement | Done? | Your notes |
| ----------- | ----- | ---------- |
| **Prometheus + Grafana** on-cluster (**no** AWS-managed observability as substitute) | [x] | `kube-prometheus-stack` deploys via Terraform/Helm in `monitoring`; validated in dev and promotion workflow. |
| **Dashboards** — **CPU, memory, disk** for **all nodes** | [x] | Node Exporter + Prometheus targets available from kube-prometheus-stack; node metrics visible in Grafana dashboards. |
| **Alerts** — **Email** and/or **Slack** at critical thresholds | [ ] | Optional SMTP/GitHub Secrets for Alertmanager (`alertmanager_*` variables). |
| **Grafana** — reachable **from outside AWS** | [x] | Public ALB ingress at `https://grafana-<env>.<domain>` (OAuth-protected). |
| **Grafana auth** — **OAuth2 only** (Okta/GitHub/Google); **no** username/password as primary UX | [x] | Google OAuth configured for Grafana; redirect URI allowlist required per env (`/login/google`). |
| **Centralized logging** — **Loki** or ELK/OpenSearch **or** self-hosted Sentry on EKS | [x] | Loki + Promtail deployed on-cluster; Terraform/Helm tuned for stable install in small clusters. |
| **Multi-service logs** — Query across **all 3** Go backends | [x] | Loki push/query smoke test passed (`hello` entries retrievable); cross-service query available via labels in Explore. |

---

## 5. Presentation & defense

| Requirement | Done? | Your notes |
| ----------- | ----- | ---------- |
| **Silent video rule** — Long-running parts (e.g. Day 1) may use **silent** video only | [ ] | |
| **Live narration** — Explain technical decisions and workflow over demo/video | [ ] | |
| **Live chaos defense** — Instructor triggers failure; you use **monitoring + logging** to diagnose and explain recovery **in ~1–2 minutes** | [ ] | Requires section 4 in place for full credit story. |

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
