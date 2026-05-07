# Claiset

Claiset is a **React + Go microservices** app for tracking wardrobe **items**, building **outfits**, and assigning outfits to days on a **calendar**. It runs locally with in-memory storage (fast dev) or PostgreSQL, and deploys to **EKS + RDS** via Terraform.

**Course assignment (full checklist with `[x]` / `[ ]` status):** [REQUIREMENTS.md](REQUIREMENTS.md)

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

For the **canonical checklist** (checkboxes + rubric mapping), open **[REQUIREMENTS.md](REQUIREMENTS.md)**. Summary below.

### 1. Application architecture

| Requirement | Status |
| ----------- | ------ |
| Frontend + backend + RDS (Postgres only) | **Done** |
| ≥ 3 microservices | **Done** (items, outfits, schedule) |
| Custom hostname + HTTPS (TLS on ALB) | **Done** when `domain_root` + Route53 + ACM validate; Ingress uses ACM on ALB |
| Infra exclusively via Terraform (VPC, EKS, RDS, …) | **Done** under `infra/` |
| Multi-environment Terraform | **Done** — `infra/envs/{dev,qa,uat,prod}` + remote S3/DynamoDB state |

**Note:** The Terraform module **`app-bluegreen`** is named for the rubric; workloads today use **rolling Kubernetes Deployments** (not two live stacks + weighted traffic flip). You still need a **written justification** for blue/green *or* canary per the assignment.

### 2. Deployment & CI/CD (git-driven promotion)

| Requirement | Status |
| ----------- | ------ |
| Dev → nightly QA → UAT → Prod | **Implemented** — [`.github/workflows/promotion.yml`](.github/workflows/promotion.yml) (dev on push to `main`; QA on schedule + manual; UAT on **`RC` token** in commit message; prod on `v*` tags + manual) |
| Dev/QA → UAT (Conventional Commits / PR) | **Partial** — UAT triggers when the **tip commit message** contains **`RC` as its own word** (e.g. `chore: RC` or `… RC …`), not substrings like `resources`. PR-merge automation is not wired separately. |
| UAT → Prod via tags (no console deploy) | **Implemented (initial)** — `v*` tags + `workflow_dispatch` prod |
| Documented choice: blue/green **or** canary | **Still to do** (doc + how it maps to your rollout) |
| Zero downtime | **Partial** — rolling updates + probes; formal demo/narrative still expected |

**Operational notes (recent work):**

- **`[skip-dev]`** in the **tip commit message** on `main` skips the dev job so you can push infra-only changes without a full dev deploy.
- **Guards** (after `terraform init`): `terraform-vpc-guard.sh`, `terraform-eks-import-guard.sh`, `terraform-k8s-import-guard.sh` — idempotent imports / duplicate VPC protection; safe on **fresh env** (empty state).
- **ECR promote** (`dev → qa`, etc.) treats **`ImageAlreadyExistsException`** as success (safe reruns).
- **Cost / rollout:** dev and QA apply steps can **burst** the managed node group during Phase 2, then scale back down; **Cluster Autoscaler** is installed from Terraform where OIDC is configured.
- Terraform in CI uses **`terraform_wrapper: false`** to avoid misleading exit-code noise from the HashiCorp action wrapper.

Current automation:

- Tests: [`.github/workflows/go-tests.yml`](.github/workflows/go-tests.yml)
- Promotion: [`.github/workflows/promotion.yml`](.github/workflows/promotion.yml)

### 3. Day 2 scenarios

| Scenario | Status |
| -------- | ------ |
| **Schema migrations** | **Implemented** — `cmd/migrate` + Kubernetes `migrate` Job before app Deployments; you still need a **clear demo/explanation** for graders |
| **Node OS / AMI patching** without interrupting service | **Not documented / not demonstrated** — EKS managed node group + launch template exist; add process (drain / roll nodegroup / AMI release version) and narrate it |

### 4. Observability & logging

| Requirement | Status |
| ----------- | ------ |
| Self-hosted Prometheus + Grafana on-cluster | **Planned only** (comments in `infra/modules/platform/main.tf`) |
| Grafana external + **OAuth2** (no password login) | **Not implemented** |
| Dashboards CPU / memory / disk + alerts | **Not implemented** |
| Central logs (e.g. Loki/ELK) across all backends | **Not implemented** |

---

## What still needs to be done (assignment checklist)

See **unchecked** items in **[REQUIREMENTS.md](REQUIREMENTS.md)** for what is still open. Highest impact next:

1. **Observability (15%)** — Largest gap: self-hosted **Prometheus + Grafana** on EKS, **OAuth2-only** Grafana access, dashboards (CPU/memory/disk), **alerts** (email/Slack), and **centralized logging** (e.g. **Loki** or ELK) with queries across all three Go services.
2. **Day 2 OS patching (10%)** — Document and **demo** rolling EKS node updates (AMI / nodegroup version) **without** killing traffic (drain, surge, verification).
3. **Day 2 schema change (10%)** — You have migrate; prepare a **graded narrative**: show a schema change, how it ships, and how rollback / safety works.
4. **CI/CD narrative (15%)** — Align wording with the brief: optional **PR-based** UAT trigger if graders expect it; document the exact promotion path (dev → QA nightly → UAT `RC` → prod tag).
5. **Blue/green or canary (written)** — Pick one, justify it, and relate it to how you deploy (even if implementation stays rolling for now).
6. **Presentation & chaos defense** — Silent video allowed for long runs; **live narration**; practice using metrics/logs to find a failure in 1–2 minutes.

**Cost tip:** Tear down **`qa` / `uat` / `prod`** when not demoing (`./infra/scripts/terraform-destroy-nonprod.sh` or per-env destroy). NAT + second RDS + second EKS add up quickly.

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

Optional — after destroying non-prod, **scale dev down to one node** to reduce EC2 cost while keeping the cluster:

```bash
export PAUSE_DEV_NODES=1
./infra/scripts/terraform-destroy-nonprod.sh
```

**Important:** Make sure no GitHub Action is currently running Terraform for those environments when you call these scripts.

### Skip dev on a push (infra-only commits)

If the **tip commit message** on `main` contains **`[skip-dev]`**, the **dev** job in `promotion.yml` is skipped (manual **Run workflow → dev** still runs dev). Use when you only need QA/UAT/prod or doc-only pushes.

---

## Notes / architecture (implemented)

- **Frontend:** React + Vite (`web/`). In production it calls **same-origin** (`window.location.origin`) so it works behind an ALB Ingress at `/api/v1/...`.
- **HEIC:** converted client-side via `heic-to` when needed (`web/src/heicConvert.ts`).
- **Backend:** Go + Chi services under `cmd/*-service/`.
- **Database:** Postgres schema in `cmd/migrate/schema.sql` (applied by `cmd/migrate`).
- **Infra:** Terraform modules under `infra/` (EKS, RDS, ECR, ALB ingress controller, ExternalDNS, app deployments).

---

