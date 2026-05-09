## Terraform infrastructure (EKS + RDS + Kubernetes app)

This folder is the **only place** AWS / Kubernetes infrastructure is managed. No console click-ops.

### Layout
- `envs/dev`: first environment to stand up (us-east-1)
- `envs/qa`, `envs/uat`, `envs/prod`: promotion environments (same modules; different image tags and hostnames)
- `modules/*`: reusable building blocks (VPC, EKS, RDS, platform add-ons, **`eks-app`** workloads + Ingress)

### Quick start (dev)
1. Create an AWS profile / credentials with permission to create VPC/EKS/RDS/IAM/Route53/ACM.
2. From `infra/envs/dev`, run:

```bash
terraform init
terraform plan
terraform apply
```

### Remote state (required for rubric)
This repo uses an S3 backend + DynamoDB lock so **local** and **CI/CD** share the same Terraform state.

1. Create the remote state resources once:

```bash
cd infra/bootstrap
terraform init
terraform apply
```

2. Create GitHub Actions secrets (repo settings):
- `TF_STATE_BUCKET` (S3 bucket name)
- `TF_LOCK_TABLE` (DynamoDB lock table name)
- `ROUTE53_HOSTED_ZONE_ID` (public hosted zone ID for `domain_root`, e.g. `Z123...`; CI sets `TF_VAR_route53_hosted_zone_id`)

**Stuck state lock** (e.g. cancelled workflow): see [`docs/failure-playbook.md`](../docs/failure-playbook.md).

### Promotion workflow (git-driven)
CI/CD is implemented via GitHub Actions in [`.github/workflows/promotion.yml`](../.github/workflows/promotion.yml):
- **Dev**: push to `main` builds/pushes images tagged `:dev` and applies Terraform in `envs/dev`
- **QA (nightly)**: scheduled run retags `:dev` → `:qa` and applies Terraform in `envs/qa`
- **UAT**: PR merged into **`main`** (same repo), or **`push`** to **`main`** with an **`RC`**-style message (see workflow), **or** manual **Run workflow** → `uat`; retags `:qa` → `:uat` and applies `envs/uat`
- **Prod**: pushing a tag like `v1.0.1` retags `:uat` → `:prod` and applies Terraform in `envs/prod`

You must configure repo secrets:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN` — **omit** for a normal IAM user access key. Set only when using **temporary** credentials (AWS Academy/Vocareum, STS, etc.); the workflow does not require this input for IAM users.

(See also state/backend secrets and `ROUTE53_HOSTED_ZONE_ID` in the list above.)

### Domain / HTTPS (required for rubric)
The frontend must be reachable at a custom DNS name over HTTPS.
This scaffolding expects:
- a Route53 hosted zone (Terraform-managed)
- an ALB Ingress with TLS (ACM or cert-manager/Let's Encrypt depending on what you choose)

### Self-hosted observability (Prometheus, Grafana, Loki) — section 4 rubric
Terraform installs **kube-prometheus-stack** (Prometheus, Alertmanager, Node Exporter, kube-state-metrics, Grafana), **Loki** (single binary), and **Promtail** from `infra/modules/platform/observability.tf`. Nothing here replaces AWS with *managed* observability services; it is all workload-on-EKS.

**Turn it on (per environment, e.g. `infra/envs/dev`):**

1. Keep `domain_root` set and `wait_for_acm_validation = true` (Grafana gets its own ACM cert + Route53 validation, same as the app).
2. In `terraform.tfvars` (or CI `TF_VAR_*`), set:
   - `enable_observability_stack = true`
   - `grafana_google_client_id` / `grafana_google_client_secret` (Web application OAuth client)
   - Optional: `grafana_google_allowed_domains` (comma-separated, e.g. `your school.edu`)
   - Optional email alerts: `alertmanager_email_to`, `alertmanager_smtp_smarthost`, `alertmanager_smtp_from`, and if the relay needs auth: `alertmanager_smtp_user`, `alertmanager_smtp_password`

3. **Google Cloud Console → APIs & Services → Credentials:** create an OAuth **Web client**. Under **Authorized redirect URIs** add one URL **per environment** you enable (same client can list multiple redirects), for example:

   `https://grafana-dev.<your-domain>/login/google`  
   `https://grafana-qa.<your-domain>/login/google`  
   `https://grafana-uat.<your-domain>/login/google`  
   `https://grafana-prod.<your-domain>/login/google`

4. **Using Google’s downloaded JSON locally:** the file usually has a `web` object (Web client). From the repo root or `infra/envs/dev`:

   ```bash
   export TF_VAR_enable_observability_stack=true
   export TF_VAR_grafana_google_client_id="$(jq -r '.web.client_id' /path/to/client_secret_….json)"
   export TF_VAR_grafana_google_client_secret="$(jq -r '.web.client_secret' /path/to/client_secret_….json)"
   ```

   Desktop / `"installed"` clients are not the right type for Grafana’s web redirect flow; recreate a **Web application** credential if yours only has `"installed"`.

Grafana is exposed on **`https://grafana-<env>.<domain_root>`** via ALB Ingress; local login is disabled in favor of **Sign in with Google**.

**After apply:** use Grafana **Explore** with the **Loki** datasource; filter by container / namespace / pod labels to query logs from all microservices. For node **CPU / memory / disk**, use the bundled Kubernetes/Node dashboards or import a community Node Exporter dashboard (e.g. ID `1860`). Default Prometheus rules include many node and kube alerts; wire SMTP above so Alertmanager can email on firing alerts.

**GitHub Actions (all Terraform applies in [.github/workflows/promotion.yml](../.github/workflows/promotion.yml) inherit these env vars):**

| Setting | Type | Purpose |
|--------|------|--------|
| `ENABLE_OBSERVABILITY` | Repository **Variable** | Set exactly `true` so every **dev / qa / uat / prod** Terraform run gets `TF_VAR_enable_observability_stack=true`. Any other value or unset ⇒ stack off. |
| `GRAFANA_GOOGLE_CLIENT_ID` | Repository **Secret** | `TF_VAR_grafana_google_client_id` (same Web client as local testing). |
| `GRAFANA_GOOGLE_CLIENT_SECRET` | Repository **Secret** | `TF_VAR_grafana_google_client_secret`. |
| `GRAFANA_GOOGLE_ALLOWED_DOMAINS` | Optional repository **Variable** | Comma-separated domains → `TF_VAR_grafana_google_allowed_domains`. |

If `ENABLE_OBSERVABILITY` is `true` but Grafana secrets are empty, Terraform will fail validation. Register **every** Grafana redirect URI you need in Google Cloud before the first CI apply per environment.

**Stuck Helm / recover before apply:** If an apply was interrupted, charts can sit in Helm `pending-install` / `failed` / `pending-upgrade` / `pending-rollback` and the next Terraform run errors with **`cannot re-use a name that is still in use`**. The workflow runs [`scripts/helm-platform-reconcile.sh`](scripts/helm-platform-reconcile.sh) (unstuck uninstall + **`terraform import`** for healthy **deployed** platform charts missing from state) then [`scripts/helm-monitoring-reconcile.sh`](scripts/helm-monitoring-reconcile.sh) (same for `kube-prometheus-stack` / `loki` / `promtail` in `monitoring`). Run the same scripts locally from `infra/envs/<env>` after `terraform init`, with `EXPECTED_CLUSTER_NAME` set, if you see that error.

### Grading helpers (node patching / zero-downtime)

- **`scripts/eks-node-patch-evidence.sh`** — textual **before/after** snapshot (`describe-nodegroup` + nodes). Procedure: **[../docs/day2-os-node-patching.md](../docs/day2-os-node-patching.md)**.
- **`scripts/http-availability-during-rollout.sh`** — **`2xx`/error HTTP codes once per second** during a rollout for **C6**. Procedure: **[../docs/zero-downtime-promotion-evidence.md](../docs/zero-downtime-promotion-evidence.md)**.
