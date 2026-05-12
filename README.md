# Claiset

Claiset is a **React + Go microservices** app for tracking wardrobe **items**, building **outfits**, and assigning outfits to days on a **calendar**. It runs locally with in-memory storage (fast dev) or PostgreSQL, and deploys to **EKS + RDS** via Terraform.

## Repository layout

```
.
├── web/                  # React SPA (Vite)
├── cmd/
│   ├── items-service/    # Items API (Go)
│   ├── outfits-service/  # Outfits API (Go)
│   ├── schedule-service/ # Assignments API (Go)
│   └── migrate/          # DB schema migrator (schema.sql)
├── internal/             # Shared auth / HTTP helpers
├── infra/                # Terraform (VPC, EKS, RDS, ECR, app deploy)
└── tests/                # Go tests
```

## Tech stack & architecture

- **Frontend:** React + Vite (`web/`). In production the SPA calls **same-origin** (`window.location.origin`) so it works behind an ALB Ingress at `/api/v1/...`.
- **HEIC images:** converted client-side via `heic-to` when needed (`web/src/heicConvert.ts`).
- **Backend:** three Go services (Chi) under `cmd/*-service/`: **items**, **outfits**, **schedule**.
- **Database:** PostgreSQL schema in `cmd/migrate/schema.sql`, applied by `cmd/migrate` and by a Kubernetes **migrate Job** in cluster environments.
- **Cloud:** Terraform modules under `infra/` (VPC, EKS, RDS, ECR, ALB Ingress Controller, ExternalDNS, workloads, optional observability stack).

## CI/CD and environments

Promotion is automated with GitHub Actions ([`.github/workflows/promotion.yml`](.github/workflows/promotion.yml)):

- **Dev:** push to `main` builds and pushes images and applies Terraform for `infra/envs/dev`.
- **QA:** nightly schedule (plus manual **Run workflow**).
- **UAT:** after a successful dev job when the pushed commit indicates a release-candidate style message or a **merge into `main`** from an in-repo PR (see workflow conditions); squash merges can use an `RC`-style prefix in the commit subject.
- **Prod:** version tags matching `v*` (and gated manual dispatch).

Unit tests run in [`.github/workflows/go-tests.yml`](.github/workflows/go-tests.yml).

**Tips**

- **`[skip-dev]`** in the **tip commit message** on `main` skips the dev job for infra-only or doc-only pushes.
- **ECR image promotion** (`dev` → `qa`, etc.) treats `ImageAlreadyExistsException` as success so reruns stay idempotent.
- Terraform in CI uses **`terraform_wrapper: false`** on the HashiCorp setup action to avoid misleading exit codes.

## Rollouts and traffic shaping

Workloads use Kubernetes **RollingUpdate** with readiness and liveness probes; **UAT** and **prod** use tighter surge and **minReadySeconds** soak than dev/QA. **PodDisruptionBudgets** apply when replica count is above one.

Optionally, **UAT** can enable an **ALB weighted forward** on the SPA path `/` only (stable `web` vs `web-canary`), configured via Terraform in [`infra/modules/eks-app`](infra/modules/eks-app) and repo **Actions variables** (`ALB_CANARY_<ENV>_…` in the workflow). Rationale and tuning notes: [docs/partial-canary-justification.md](docs/partial-canary-justification.md).

## Observability (optional per environment)

When enabled in Terraform, the platform module can install **kube-prometheus-stack** (Prometheus, Alertmanager, Grafana), **Loki**, and **Promtail** on the cluster, with Grafana behind HTTPS and **Google OAuth** (form login disabled). SMTP variables configure Alertmanager email. Setup and variables: [`infra/README.md`](infra/README.md).

## Remote state: `eks_app` module rename

If remote state still lists `module.app_bluegreen.*` after the rename to `eks_app`, run once per environment (after `terraform init` against the same S3 backend CI uses).

From the repo root, with **`TF_STATE_BUCKET`**, **`TF_LOCK_TABLE`**, and AWS credentials set:

```bash
export TF_STATE_BUCKET=… TF_LOCK_TABLE=…
export AWS_REGION=us-east-1   # if different from default

bash infra/scripts/terraform-migrate-remote-state-for-eks-app-rename.sh dev
bash infra/scripts/terraform-migrate-remote-state-for-eks-app-rename.sh qa
bash infra/scripts/terraform-migrate-remote-state-for-eks-app-rename.sh prod
# If UAT state still exists from before teardown, run for uat; skip if UAT is recreated from empty state.
```

Manual equivalent (per env): `terraform init -reconfigure` with the same backend flags as [`.github/workflows/promotion.yml`](.github/workflows/promotion.yml), then `bash ../../scripts/terraform-state-mv-module-to-eks-app.sh`.

Terraform guard helpers (after `terraform init`): `infra/scripts/terraform-vpc-guard.sh`, `terraform-eks-import-guard.sh`, `terraform-k8s-import-guard.sh` — useful on fresh state or duplicate-VPC avoidance.

---

## Run locally

### Prerequisites

- **Go** 1.23+ (`go.mod`)
- **Node.js** 20+ and npm (for `web/`)
- Optional: **PostgreSQL** if you want all three APIs on DB locally (otherwise they use **in-memory** stores).

### Backend services (Go)

Configuration is via **environment variables** (no CLI flags):

| Variable | Required | Meaning |
| -------- | -------- | ------- |
| `DATABASE_URL` | No\* | Postgres DSN (`postgres://…`). If omitted, APIs use memory (dev convenience). |
| `GOOGLE_CLIENT_ID` | No\*\* | OAuth Web Client ID — enables Google JWT verification. |
| `PORT` | No | Listen port (**without** `:`, e.g. `8082`). Defaults: 8081 / 8082 / 8083 |

\* Migrate **requires** `DATABASE_URL`.  
\*\* If unset, the API treats the bearer string as **raw user id** (fine for quick `curl`; do not rely on this in prod).

Example — three terminals from the **repository root**:

```bash
# Optional: Postgres (omit DATABASE_URL entirely to use in-memory APIs)
export DATABASE_URL='postgres://user:pass@localhost:5432/onlinecloset?sslmode=disable'
export GOOGLE_CLIENT_ID='YOUR_GOOGLE_OAUTH_WEB_CLIENT_ID.apps.googleusercontent.com'

export PORT=8081 && go run ./cmd/items-service
```

```bash
export DATABASE_URL="$DATABASE_URL" GOOGLE_CLIENT_ID="$GOOGLE_CLIENT_ID"
export PORT=8082 && go run ./cmd/outfits-service
```

```bash
export DATABASE_URL="$DATABASE_URL" GOOGLE_CLIENT_ID="$GOOGLE_CLIENT_ID"
export PORT=8083 && go run ./cmd/schedule-service
```

Apply DB schema (once Postgres is reachable):

```bash
export DATABASE_URL='postgres://user:pass@localhost:5432/onlinecloset?sslmode=disable'
go run ./cmd/migrate
```

### Frontend (`web/`)

```bash
cd web
cp .env.example .env
# Fill VITE_* and VITE_GOOGLE_CLIENT_ID then:
npm ci
npm run dev
```

### Tests

```bash
go test -v ./tests/...
```

---

## Deploying (high level)

1. **Build & push** container images to ECR (`items`, `outfits`, `schedule`, `web`, `migrate`). Dockerfiles: `cmd/*/Dockerfile`, `web/Dockerfile`. Build context is usually the **repo root** because Dockerfiles use `COPY web/`:

   ```bash
   docker build -f web/Dockerfile -t YOUR_ECR_REPO/web:dev .
   docker build -f cmd/items-service/Dockerfile -t YOUR_ECR_REPO/items:dev .
   docker build -f cmd/outfits-service/Dockerfile -t YOUR_ECR_REPO/outfits:dev .
   docker build -f cmd/schedule-service/Dockerfile -t YOUR_ECR_REPO/schedule:dev .
   docker build -f cmd/migrate/Dockerfile -t YOUR_ECR_REPO/migrate:dev .
   ```

2. **Terraform** in `infra/envs/<env>`: configure remote backend, variables (`domain_root`, OAuth, image tags, etc.), then `terraform apply`. conventions and bootstrap: **`infra/README.md`**.

---

## Tearing down to save AWS costs

EKS, NAT gateways, RDS, and ALBs dominate spend. Scripts remove app Ingress (and observability Ingress in `monitoring` where applicable) before destroy to reduce stuck ENIs.

### All environments (`dev`, `qa`, `uat`, `prod`)

From the repo root:

```bash
export TF_STATE_BUCKET=YOUR_STATE_BUCKET
export TF_LOCK_TABLE=YOUR_LOCK_TABLE
export AWS_REGION=us-east-1

./infra/scripts/terraform-destroy-all.sh        # all envs
# or one env:
./infra/scripts/terraform-destroy-all.sh dev
```

### Non-prod only (optional: keep `dev`)

```bash
export TF_STATE_BUCKET=YOUR_STATE_BUCKET
export TF_LOCK_TABLE=YOUR_LOCK_TABLE
export AWS_REGION=us-east-1

./infra/scripts/terraform-destroy-nonprod.sh    # qa, uat, prod
```

Optional — after non-prod destroy, shrink dev nodes:

```bash
export PAUSE_DEV_NODES=1
./infra/scripts/terraform-destroy-nonprod.sh
```

Avoid running these while a workflow is actively applying Terraform for the same stacks.

---

## Operations docs

- Day 2 runbook (patching + schema): [`docs/day2-runbook.md`](docs/day2-runbook.md)
- Node patching detail: [`docs/day2-os-node-patching.md`](docs/day2-os-node-patching.md)
- Failure playbook: [`docs/failure-playbook.md`](docs/failure-playbook.md)
- Zero-downtime promotion evidence helpers: [`docs/zero-downtime-promotion-evidence.md`](docs/zero-downtime-promotion-evidence.md)
