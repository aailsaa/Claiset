# Assignment requirements

**Back to project overview:** [README.md](README.md)

---

## 1. Application architecture

- [x] **Frontend** — Single-page application
- [x] **Database** — AWS RDS (PostgreSQL) in cloud deployments
- [x] **Backend** — At least three microservices
- [x] **Custom DNS and HTTPS** — Public hostname with TLS
- [x] **Infrastructure as code** — VPC, EKS, RDS, containers, and app workloads defined and applied via Terraform
- [x] **Automation** — Changes applied via Terraform and CI (e.g. GitHub Actions), not ad hoc console provisioning

---

## 2. Deployment & CI/CD (git-driven promotion)

- [x] **Environments** — Clear path across non-production stages through production using git-based promotion
- [x] **UAT promotion** — Merging an in-repository pull request into default branch promotes to UAT (GitHub Actions). Direct pushes without a PR still support an explicit **`RC`** token commit message alternative.
- [x] **Production** — Release via version tags (`v*`); AWS Console deploy is not the primary promotion path
- [ ] **Rollout strategy** — Document and justify a chosen approach (e.g. blue/green or canary vs rolling) as required by the course
- [ ] **Availability during promotion** — Show or explain how updates avoid unacceptable user-visible downtime during deploys, per course expectations

---

## 3. Mandatory “Day 2” scenarios

- [ ] **OS / security patching** — Update EC2 worker nodes / AMIs without unnecessary service interruption
- [x] **Schema changes** — Migrations coordinated with deployments (migrate job/tooling before app rollouts)

---

## 4. Observability & logging (self-hosted only)

- [ ] **Metrics** — Prometheus and Grafana on-cluster (not AWS-managed observability as substitute)
- [ ] **Dashboards** — CPU, memory, and disk coverage for worker nodes
- [ ] **Alerts** — Notifications for critical thresholds (e.g. email or Slack)
- [ ] **Grafana access** — Reachable from outside AWS
- [ ] **Grafana authentication** — OAuth2 only (e.g. Okta, GitHub, or Google); no username/password
- [ ] **Centralized logging** — e.g. Loki or ELK/OpenSearch, or comparable self-hosted approach on EKS
- [ ] **Cross-service logs** — Query logs across all microservices

---

## 5. Presentation & defense

- [ ] **Presentation** — Deliver within assigned time (e.g. eight minutes); follow course rules for format
- [ ] **Recorded material** — If using video for longer portions, recording must meet course constraints (e.g. silent video where specified)
- [ ] **Live explanation** — Narrate or defend design and operational choices
- [ ] **Operational defense** — Demonstrate diagnosing and recovering from a failure using monitoring/logging as required by the assignment
