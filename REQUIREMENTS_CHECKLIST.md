# Assignment Requirements Checklist (Proof-Oriented)

**Back to project overview:** [README.md](README.md)  
**Source requirements (unaltered):** [REQUIREMENTS.md](REQUIREMENTS.md)

Use this as your final grading evidence matrix: each row maps to a concrete screenshot, log snippet, URL, or workflow run.

**Status snapshot:** Prod promotion and observability stack have completed successfully in a recent run; use your **Grafana prod screen recording** + **successful workflow run** URLs as primary evidence. **Prod teardown** may be in progress—save artifacts (screenshots, recordings, state list excerpts) *before* RDS/EKS are gone if you still need console proof.

---

## 1) Application Architecture

| Requirement | Status | Required proof (exact artifact to capture) | Current evidence / notes |
| --- | --- | --- | --- |
| Frontend exists and is polished | [x] | Screenshot of app homepage + one functional page in prod | Implemented; capture from prod URL or archival clip if stack is torn down |
| Database is AWS RDS only | [x] | AWS console screenshot of prod RDS instance + `terraform state list` showing RDS resources | Terraform-managed; screenshot **before** destroy if you are deleting prod RDS |
| Backend has at least 3 microservices | [x] | `kubectl -n prod get deploy` showing `items`, `outfits`, `schedule` | Terraform `module.app_bluegreen` / `infra/modules/app-bluegreen` |
| Frontend on custom DNS with HTTPS | [x] | Browser screenshot of `https://app-prod.<domain>` lock icon + ALB/Ingress hostname mapping | `app-prod.claiset.xyz` path verified in successful runs |
| EKS/RDS/VPC/IAM managed by Terraform | [x] | `terraform state list` excerpt + repo structure screenshots (`infra/modules/*`) | Terraform-first; `infra/modules/*` + env roots |
| Day 1 + Day 2 automated | [x] | GitHub Actions workflow run screenshots + Terraform apply logs | `promotion.yml` + apply logs from prod run |

---

## 2) Deployment & CI/CD (Git-Driven Promotion)

| Requirement | Status | Required proof (exact artifact to capture) | Current evidence / notes |
| --- | --- | --- | --- |
| Dev -> Nightly QA -> UAT -> Prod flow | [x] | Screenshot of workflow graph showing stages and successful transitions | Implemented in `.github/workflows/promotion.yml` |
| Dev/QA -> UAT via Conventional Commit or PR merge | [x] | One workflow run triggered by PR merge (or commit message containing `RC`) | PR merge trigger is active; RC path still supported |
| UAT -> Prod via release tags (no click deploy) | [x] | Workflow run triggered by tag/manual with git refs shown | Prod: `workflow_dispatch` with `ALLOW_COSTLY_RUNS` (still Git-driven; document in defense) |
| Blue/Green or Canary chosen and justified | [x] | 1 slide or README section explicitly stating strategy + rationale | **[README.md](README.md)** — **Canary-style** progressive rollout via **`RollingUpdate`** + probes (`infra/modules/app-bluegreen`); optional slide can mirror that section |
| Zero downtime during promotion | [ ] | Short video/log stream proving no 5xx during rollout + successful rollout status | `maxUnavailable=0` / `maxSurge=25%` + probes; attach **workflow** + health evidence during a rollout |

---

## 3) Mandatory Day-2 Scenarios

| Requirement | Status | Required proof (exact artifact to capture) | Current evidence / notes |
| --- | --- | --- | --- |
| OS/security patching of worker nodes without outage | [ ] | Before/after node AMI or node version + rollout/smoke success during rotation | Runbook exists; final demo evidence still needed |
| Schema change deployment with explanation | [x] | `kubectl -n prod get jobs` + `describe job migrate` + app/API behavior after migration | `migrate` job path exists and has completed in runs |

---

## 4) Observability & Logging (Self-Hosted on EKS)

| Requirement | Status | Required proof (exact artifact to capture) | Current evidence / notes |
| --- | --- | --- | --- |
| Prometheus + Grafana self-hosted on EKS | [x] | `kubectl -n monitoring get pods` + Grafana UI screenshot | `kube-prometheus-stack` via platform module; show in prod recording |
| Dashboard includes CPU/memory/disk node metrics | [x] | Grafana dashboard screenshots of node CPU, memory, disk panels | Include **CPU, memory, and disk** in prod Explore/dashboards clip |
| Alerts sent to Email/Slack | [ ] | Alert drill command output + received email/slack screenshot | Alertmanager SMTP wired; run `infra/scripts/alert-drill.sh` (or equivalent) and save **received** message screenshot |
| Grafana externally reachable | [x] | Browser screenshot of `https://grafana-prod.<domain>` reachable from outside AWS | `grafana-prod.claiset.xyz` + ALB; show URL bar in recording |
| Grafana uses OAuth2 (no username/password primary flow) | [x] | Screenshot/video of Google OAuth redirect and successful sign-in | **Prod:** capture Google sign-in in screen recording (not local admin login) |
| Centralized logging stack on EKS (Loki/ELK/Sentry) | [x] | Screenshot of Loki datasource + query result panel | Loki single-binary + Grafana datasource `uid=loki`; show Explore → Loki |
| Query logs across all 3 backend services | [x] | 3 service-specific queries (`items`, `outfits`, `schedule`) + one combined query screenshot | When `PROOF_LOKI_LOGS` is on, smoke script validates Loki **streams** for app namespace; clip: `{namespace="prod",container="items"}` (and outfits, schedule) + `{namespace="prod"}` |

---

## 5) Presentation & Defense

| Requirement | Status | Required proof (exact artifact to capture) | Current evidence / notes |
| --- | --- | --- | --- |
| Silent video for long-running parts | [ ] | Submitted silent clip (provision/deploy) | Record/export pending |
| Live narration over video/demo | [ ] | Final narrated recording or live demo notes | Script exists in `docs/final-defense-script.md` |
| Live chaos defense in ~1-2 min | [ ] | Timed practice capture (issue -> diagnosis -> mitigation) | Incident story is ready; rehearse once with timer |

---

## Final Evidence Bundle (create before submission)

- Architecture screenshots (frontend, DNS/HTTPS, RDS, microservices)—**grab RDS/console before prod destroy** if needed
- CI/CD workflow screenshots for Dev/QA/UAT/Prod promotion (include green prod job link)
- Day-2 evidence (schema migration, node patching flow)—patching row still open
- Observability: **silent or narrated screen recording** of prod Grafana (OAuth → Prometheus sample → **node CPU/memory/disk** → Loki queries for three backends)
- Alert receipt screenshot + chaos-defense practice clip or timestamped run notes

---

## Rubric Reference

| Category | Weight | Maps to sections |
| --- | ---: | --- |
| Infrastructure (Terraform) | 20% | Section 1 |
| Application & networking | 15% | Sections 1-2 |
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
