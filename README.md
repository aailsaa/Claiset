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


## Assignment rubric: what is implemented vs. pending

### 1. Application architecture

| Requirement | Status |
| ----------- | ------ |
| Frontend + backend + RDS (Postgres only) | **Done** |
| ≥ 3 microservices | **Done** (items, outfits, schedule) |
| Custom hostname + HTTPS (TLS on ALB) | **Infrastructure present** once domain/registrar/DNS verification are wired |
| Infra exclusively via Terraform (VPC, EKS, RDS, …) | **Done** under `infra/` |
| Fully automated multi-environment “Day 2” promotion story | **Partial** — `infra/envs/dev` exists; QA/UAT/Prod workspaces and scripted promotion flows are **not** in repo yet |

**Note:** The Terraform module directory name **`app-bluegreen`** reflects the intended grading strategy; today’s manifests use **rolling Kubernetes Deployments**, not two live stacks with an explicit weighted traffic flip (canonical blue/green or canary is still ahead if you implement it).

### 2. Deployment & CI/CD (git-driven promotion)

| Requirement | Status |
| ----------- | ------ |
| Dev → nightly QA → UAT → Prod pipelines | **Implemented (initial)** — see `.github/workflows/promotion.yml` |
| Auto promotion Dev/QA → UAT (Conventional Commits / PR merges) | **Implemented (initial)** — “RC” in commit message triggers UAT |
| UAT → Prod only via release tags / labels (no console click deploy) | **Implemented (initial)** — `v*` tags trigger prod |
| Documented choice: blue/green **or** canary | **Incomplete** |
| Rolling updates help avoid downtime **for in-place Deployments** when probes/replicas permit | **Partial** |

Current automation:
- Tests: [`.github/workflows/go-tests.yml`](.github/workflows/go-tests.yml)
- Promotion: [`.github/workflows/promotion.yml`](.github/workflows/promotion.yml)

### 3. Day 2 scenarios

| Scenario | Status |
| -------- | ------ |
| **Schema migrations** explainable demo | **Yes** — `schema.sql` + `migrate` job + incremental `ALTER … IF NOT EXISTS` |
| **Node OS / AMI patching** live demo narrative | **Not documented in repo** — EKS managed node group exists; you still need an explicit IaC/process story (AMI / release version rollout) |

### 4. Observability & logging

| Requirement | Status |
| ----------- | ------ |
| Self-hosted Prometheus + Grafana on-cluster | **Planned only** (comments in `infra/modules/platform/main.tf`) |
| Grafana external + **OAuth2** (no Grafana password login) | **Not implemented** |
| Dashboards CPU / memory / disk + alerts | **Not implemented** |
| Central logs (e.g. Loki/ELK) across all backends | **Not implemented** |

---

## Run locally

### Prerequisites

- **Go** 1.23+ (`go.mod`)
- **Node.js** 20+ and npm (for `web/`)
- Optional: **PostgreSQL** if you want all three APIs on DB locally (otherwise they use **in-memory** stores).

### Backend services (Go)

There are **no CLI flags**. Configuration is via **environment variables**:

| Variable | Required | Meaning |
| -------- | -------- | ------- |
| `DATABASE_URL` | No\* | Postgres DSN (`postgres://…`). If omitted, APIs use memory (dev convenience). |
| `GOOGLE_CLIENT_ID` | No\*\* | OAuth Web Client ID — enables Google JWT verification. |
| `PORT` | No | Listen port (**without** `:`, e.g. `8082`). Defaults: 8081 / 8082 / 8083. |

\*Migrate **requires** `DATABASE_URL`.  
\*\*If unset, the API treats the bearer string as **raw user id** (fine for quick `curl`; do not rely on this in prod).

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

1. **Build & push** container images tagged for your target ECR repos (`items`, `outfits`, `schedule`, `web`, `migrate`) — Dockerfiles live under **`cmd/*/Dockerfile`**, **`web/Dockerfile`**. Build context is usually the **repo root** because Dockerfiles reference `COPY web/`:

   ```bash
   docker build -f web/Dockerfile -t YOUR_ECR_REPO/web:dev .
   docker build -f cmd/items-service/Dockerfile -t YOUR_ECR_REPO/items:dev .
   docker build -f cmd/outfits-service/Dockerfile -t YOUR_ECR_REPO/outfits:dev .
   docker build -f cmd/schedule-service/Dockerfile -t YOUR_ECR_REPO/schedule:dev .
   docker build -f cmd/migrate/Dockerfile -t YOUR_ECR_REPO/migrate:dev .
   ```

2. **Terraform** (`infra/envs/dev`): configure backend state, secrets, **`google_client_id`**, **`domain_root`**, then `terraform apply` so EKS pulls the new tags defined in Terraform (often `:dev`; adjust as you evolve tagging).

Detailed layout and conventions: **`infra/README.md`**.

---

## Tearing down to save AWS costs

EKS control planes, NAT gateways, RDS, and ALBs are the main cost drivers. Use these scripts to shut things down when you’re not using them:

### Destroy all environments (dev, qa, uat, prod)

From the repo root:

```bash
export TF_STATE_BUCKET=YOUR_STATE_BUCKET        # from infra/bootstrap output
export TF_LOCK_TABLE=YOUR_LOCK_TABLE            # from infra/bootstrap output
export AWS_REGION=us-east-1                     # or your region

./infra/scripts/terraform-destroy-all.sh        # destroys dev, qa, uat, prod
# or just one env:
./infra/scripts/terraform-destroy-all.sh dev
```

### Destroy non-prod only (keep dev up)

```bash
export TF_STATE_BUCKET=YOUR_STATE_BUCKET
export TF_LOCK_TABLE=YOUR_LOCK_TABLE
export AWS_REGION=us-east-1

./infra/scripts/terraform-destroy-nonprod.sh    # destroys qa, uat, prod
```

**Important:** Make sure no GitHub Action is currently running Terraform for those environments when you call these scripts.

---

## Notes / architecture (implemented)

- **Frontend:** React + Vite (`web/`). In production it calls **same-origin** (`window.location.origin`) so it works behind an ALB Ingress at `/api/v1/...`.
- **HEIC:** converted client-side via `heic-to` when needed (`web/src/heicConvert.ts`).
- **Backend:** Go + Chi services under `cmd/*-service/`.
- **Database:** Postgres schema in `cmd/migrate/schema.sql` (applied by `cmd/migrate`).
- **Infra:** Terraform modules under `infra/` (EKS, RDS, ECR, ALB ingress controller, ExternalDNS, app deployments).

---

