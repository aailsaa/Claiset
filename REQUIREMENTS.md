## Assignment requirements

### Overview

- **Presentation length**: 8 minutes per student

### 1. Application Architecture

- **Original application**: Must consist of a **Frontend** (make it nice), a **Database** (**AWS RDS only**), and a **Backend** with **at least 3 microservices**.
- **Frontend requirements**: Must be accessible via a **custom DNS name** with **SSL (HTTPS)** fully configured.
- **Infrastructure as Code (IaC)**: Every resource (**EKS, RDS, VPC**) must be managed **exclusively via Terraform**. **Day 1** (initial setup) and **Day 2** (updates) must be **fully automated**.

### 2. Deployment & CI/CD (Git-Driven Promotion)

- **Promotion flow**: Dev → Nightly Build (QA) → UAT → Prod
- **Automation logic**:
  - **Dev/QA → UAT**: Triggered automatically via **Conventional Commits** (e.g. `RC1`, `RC2`, …) or **Pull Request merges**
  - **UAT → Production**: Triggered via **Release Labels/Tags** (e.g. `v1.0.1`). Manual “click-to-deploy” in the AWS Console is **prohibited**.
- **Strategy**: Pick and justify either **Blue/Green** or **Canary** for EKS.
- **Zero downtime**: All promotions and updates must result in **zero dropped requests**.

### 3. Mandatory “Day 2” Scenarios

Students must demonstrate these scenarios live or via narrated video. They will be graded on the logic and thought process used to maintain stability:

- **OS/Security patching**: Update the underlying EC2 worker nodes (AMIs) with the latest patches **without interrupting service**.
- **Schema changes**: Deploy a backend change that updates the RDS database schema.
  - **Requirement**: Students must explain and demonstrate how DB schema changes are applied.

### 4. Observability & Logging (Self-Hosted Only)

- **Monitoring**: Deploy **Prometheus** and **Grafana** inside the cluster (no AWS managed services).
- **Dashboards**: Track **CPU**, **Memory**, and **Disk Space** for all nodes.
- **Alerts**: Email (and/or Slack) notifications for critical resource thresholds.
- **External access & security**:
  - Grafana must be reachable from outside AWS
  - Username/password is prohibited; must implement **OAuth2** (Okta, GitHub, or Google)
- **Centralized logging**:
  - Deploy your own stack (**Loki** or **ELK/OpenSearch**) or use a self-hosted 3rd party (e.g. **Sentry**) on EKS
  - Must support centralized queries across the backend and all 3 microservices

### 5. Presentation & Defense

- **Video rule**: Video is permitted for long-running processes (like Day 1 provisioning), but the video must be **silent**.
- **Mandatory narration**: Students must narrate live over the video to explain their technical decisions and workflow.
- **Live chaos defense**: The instructor will trigger a random “Chaos” scenario. Students must use monitoring and logging tools to diagnose the failure and explain recovery in real-time.

---

## Rubric

| Category | Weight | Criteria |
|---|---:|---|
| Infrastructure (Terraform) | 20% | All resources (EKS, RDS, IAM, VPC) managed via Terraform. State is managed properly. No “ClickOps” detected. Module structure is clean and reusable. |
| Application & Networking | 15% | 3+ microservices running. SSL/TLS is active and DNS is correctly mapped to a custom domain. Zero downtime achieved during rollout. |
| CI/CD & GitOps Logic | 15% | Seamless flow from Dev to Prod. Conventional Commits trigger UAT; Release Tags trigger Prod. Pipeline is fully automated and gate-checked. |
| Day 2: OS/Security Patching | 10% | Demonstration of AMI/Node rotation without service interruption. Logic for draining nodes and replacing them is clear and automated. |
| Day 2: Schema Changes | 10% | Clear explanation of DB Schema changes. |
| Observability & Logging | 15% | Self-hosted (EKS) Prometheus/Loki/Grafana. Alerts fire to email. OAuth2 (Google/GitHub, Okta) is the only way to access Grafana. Multi-service log querying works. |
| Presentation & Defense | 15% | Students narrated live over silent video. Successful “Chaos Defense”; students used logs/metrics to identify a random failure within 1–2 minutes. Presentation soft-skills: eye-contact, enunciation & pace, minimize verbal fillers (“um”, “like”, “uh”, “you know”), strategic pausing. |

### Presentation soft-skills (expanded)

- The “So What?” Factor (Impact Reporting)
- Handling “Technical Friction”
- Narrative Arc (The “Hero’s Journey”)
- Visual Command
- Confidence in the “Unknown”

---

## WOW-Factor

If you impress me, you will get an A or A+ for the class... No other considerations will be evaluated!

---

## Submission note (self-grading)

Provide your comments on the accomplishment for each point and submit them.

