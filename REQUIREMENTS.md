# Assignment requirements

**Back to project overview:** [README.md](README.md)

---

## Overview

- [ ] **Presentation** — 8 minutes per student (prepare silent video + live narration per rules below)

---

## 1. Application architecture

- [x] **Frontend** — Single-page app (`web/`, React/Vite)
- [x] **Database** — **AWS RDS (PostgreSQL)** only in cloud deploy (`infra/modules/rds`)
- [x] **Backend** — **≥ 3 microservices** (items, outfits, schedule — `cmd/*-service`)
- [x] **Custom DNS + HTTPS** — ALB Ingress + ACM + Route53 wired in Terraform (`infra/modules/platform`, `infra/modules/app-bluegreen`) when `domain_root` / hosted zone are configured
- [x] **IaC exclusive** — **VPC, EKS, RDS**, ECR, and app workloads managed via **Terraform** (`infra/`)
- [x] **Day 1 & Day 2 automation** — Changes applied via **Terraform** and **GitHub Actions** (`.github/workflows/promotion.yml`), not one-off console provisioning

---

## 2. Deployment & CI/CD (git-driven promotion)

- [x] **Promotion flow** — **Dev → QA (nightly + manual) → UAT (`RC` in tip commit) → Prod (`v*` tags + manual)** — see [`.github/workflows/promotion.yml`](.github/workflows/promotion.yml)
- [ ] **Dev/QA → UAT** — Brief asks **Conventional Commits** (e.g. `RC1`) **or** **PR merge** automation. **Current:** UAT runs when tip commit message contains **`RC` as its own token** (not substrings like `resources`). **PR-based trigger not wired.**
- [x] **UAT → Production** — **Release tags** (`v*`) and `workflow_dispatch`; **no** “click deploy” in AWS Console as primary path
- [ ] **Strategy** — **Pick and justify Blue/Green *or* Canary** for EKS (written doc; module name `app-bluegreen` — workloads today use **rolling Deployments**)
- [ ] **Zero downtime** — Rolling updates + probes in place; **still need** explicit demo / narrative that promotions don’t drop requests

---

## 3. Mandatory “Day 2” scenarios

- [ ] **OS / security patching** — Update **EC2 worker nodes / AMIs** **without** interrupting service. **Infra:** EKS managed node group exists. **Still need:** documented + demonstrated process (drain, roll, verify).
- [x] **Schema changes** — **Code:** `cmd/migrate` + `schema.sql` + Kubernetes **migrate Job** before app Deployments
- [ ] **Schema changes (grading)** — **Explain and demonstrate** how schema changes are applied (live or narrated video)

---

## 4. Observability & logging (self-hosted only)

- [ ] **Prometheus + Grafana** on-cluster (no AWS-managed observability as substitute)
- [ ] **Dashboards** — CPU, memory, and **disk** for **all nodes**
- [ ] **Alerts** — Email and/or Slack for critical thresholds
- [ ] **Grafana external access** — Reachable from outside AWS
- [ ] **Grafana auth** — **OAuth2 only** (Okta, GitHub, or Google); **no** username/password
- [ ] **Centralized logging** — e.g. **Loki** or **ELK/OpenSearch**, or self-hosted Sentry on EKS
- [ ] **Multi-service logs** — Central queries across **all three** Go microservices

---

## 5. Presentation & defense

- [ ] **Silent video** — Allowed for long runs (e.g. Day 1); video must be **silent**
- [ ] **Live narration** — Narrate over video / demo to explain decisions
- [ ] **Live chaos defense** — Use monitoring + logging to diagnose a random failure and explain recovery **in real time**

---

## Rubric (quick mapping)

Use this table with your self-grading comments (see submission note at bottom).

| Category | Weight | Done in repo? (high level) |
| -------- | -----: | -------------------------- |
| Infrastructure (Terraform) | 20% | [x] Modules, remote state, multi-env — keep avoiding ClickOps |
| Application & networking | 15% | [x] 3 services + TLS/DNS path — [ ] formal zero-downtime proof |
| CI/CD & GitOps | 15% | [x] Dev→QA→UAT→Prod path — [ ] full “conventional commit / PR → UAT” as written |
| Day 2: OS patching | 10% | [ ] Demo + automation story |
| Day 2: Schema | 10% | [x] Tooling — [ ] grader-facing explanation |
| Observability & logging | 15% | [ ] Not yet implemented |
| Presentation & defense | 15% | [ ] Your delivery |

### Presentation soft-skills (expanded)

- The “So What?” Factor (Impact Reporting)
- Handling “Technical Friction”
- Narrative Arc (The “Hero’s Journey”)
- Visual Command
- Confidence in the “Unknown”

