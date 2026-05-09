# Final Defense Script (2-3 minutes)


## 0:00 - 0:20 | Problem and architecture

"My project is OnlineCloset. It has a React frontend, three Go microservices (`items`, `outfits`, `schedule`), and PostgreSQL on AWS RDS.  
Everything in cloud infrastructure is Terraform-managed: VPC, EKS, RDS, IAM, ingress, certificates, DNS, and observability."

## 0:20 - 0:50 | CI/CD and promotion logic

"The delivery model is Git-driven promotion: dev -> nightly QA -> UAT -> prod.  
UAT is triggered by PR merge or RC-style commit flow. Prod is tag-driven with `v*` release tags, not console click deploys.  
The workflow uses staged Terraform applies, image retagging across environments, readiness checks, and smoke tests."

## 0:50 - 1:25 | Day-2 operations

"For schema change management, migrations run through the dedicated `migrate` job/image in Kubernetes before app traffic is validated.  
For OS/security patching, nodegroup rolling replacement is used with readiness gates and post-rollout smoke checks so service health is verified after node updates."

## 1:25 - 2:05 | Observability and logging

"Observability is fully self-hosted on EKS: Prometheus, Grafana, Alertmanager, Loki, and Promtail.  
Grafana is externally reachable with HTTPS and Google OAuth only.  
Logging is centralized in Loki with cross-service queries for all backend services.  
Alerting is routed through Alertmanager email using SMTP variables and can be demonstrated with the alert drill script."

## 2:05 - 2:40 | Bottleneck, diagnosis, and engineering response

"The biggest bottleneck in prod was pod scheduling failure: repeated `Too many pods` and CNI IP allocation limits on free-tier micro nodes.  
I diagnosed this from rollout failures, scheduler events, and pending pod states.  
I implemented production guardrails: higher nodegroup capacity during rollout, CNI prefix delegation, non-destructive Helm behavior for observability charts, and stronger rollout diagnostics.  
That changed failures from opaque timeouts into actionable signals and stabilized repeatability under constrained account limits."

## 2:40 - 3:00 | Impact / close

"The key outcome is repeatable infrastructure and promotion logic under strict cost and account constraints, with clear operational observability and runbooks for Day-2 maintenance and chaos-style debugging."

---

## Quick Demo Order (optional prompt card)

1. Show pipeline trigger source (PR/RC/tag path).  
2. Show prod URL + HTTPS + app route health.  
3. Show Grafana OAuth login path.  
4. Show node CPU/memory/disk dashboard.  
5. Show Loki query across services.  
6. Show alert drill trigger/revert and email proof.  
7. Explain one incident and the guardrail added.
