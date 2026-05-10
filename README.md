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

#### Progressive rollout strategy (EKS)

**Written justification (submission-ready prose):** [docs/partial-canary-justification.md](docs/partial-canary-justification.md)

[REQUIREMENTS.md](REQUIREMENTS.md) asks you to **pick and justify** a deployment strategy between **Blue/Green–style** ideas and **Canary**. This project implements a **hosted-service canary**: **progressive replacement** of Pods using native **`RollingUpdate`**, without running two full immutable stacks or doing a single hard traffic flip. **UAT** additionally enables an **ALB weighted forward** split on the **SPA path `/` only** (stable **`web`** vs **`web-canary`**), so a **percentage of browser traffic** hits the canary Service while **API** routes stay on stable Deployments—see [docs/partial-canary-justification.md](docs/partial-canary-justification.md) §5.

##### What is implemented (partial canary)

| Mechanism | Role in “canary” terms |
| --- | --- |
| **`RollingUpdate` + `maxUnavailable: 0`** | Old Pods are not removed until **new** Pods are **Ready**; you never intentionally drop below declared capacity during the roll. |
| **`maxSurge: 1`** in **UAT** and **Prod** (see `infra/envs/uat/main.tf`, `infra/envs/prod/main.tf`) | Limits how many **extra** Pods of the new revision run at once—**one wave at a time** when `replicas > 1` (UAT default), and explicit single-Pod burst when `replicas == 1`. **Dev/QA** keep the module default **`maxSurge: 25%`** for faster inner loops. |
| **`minReadySeconds` soak** (**20s** UAT, **30s** Prod) | After `/health` succeeds, the new Pod must stay **Ready** for this window before the Deployment controller advances; catches **flapping** or **slow failures** that a one-shot readiness check might miss—a lightweight **“observe before promote”** gate. |
| **Readiness / liveness HTTP probes** | **Service endpoints exclude** Pods until readiness passes; only healthy revision serves traffic. |
| **`PodDisruptionBudget`** (`replicas > 1`) | Caps **voluntary** eviction during node drains so you do not lose an entire service surface at once—complements rollout safety during **cluster** changes. |
| **ALB weighted forward (`/` only)** | **Per-env Terraform** (defaults **on** in **UAT**, **off** elsewhere): ALB splits **browser** traffic between **`web`** and **`web-canary`** by weight. While enabled, **`web-canary` runs at least two** nginx Pods so rollouts never leave the canary target group empty. **API** paths unchanged—no duplicate Go services. Override any apply with **`TF_VAR_*`** (see **`.github/workflows/promotion.yml`** `uat` job comments). |

##### Justification (why this counts as canary for the assignment)

- **Progressive exposure:** New code is introduced in **small increments** (bounded surge + ordered replacement), not all-at-once cutover.
- **Automated promotion gate:** **Readiness** + **`minReadySeconds`** act as successive checks before the controller retires old Pods—the same *idea* as canary stages, expressed with **Kubernetes-native** knobs instead of an external rollout controller.
- **Operational fit:** Managed node groups and **budget** favors **minimal extra capacity**; we avoid **double-deploy** Blue/Green for every microservice simultaneously.
- **HTTP share where it matters:** **ALB weights** on **`/`** give **measurable** canary exposure for the SPA without multiplying **items/outfits/schedule** Pods.

##### Defaults vs environment policy

All knobs live on module [`infra/modules/eks-app`](infra/modules/eks-app) (`rolling_update_*`, `rollout_*`, PDB, **`enable_alb_weighted_canary_for_web`** / **`alb_web_canary_traffic_percent`** / **`web_canary_replicas`**). **Prod** (and **UAT** once rebuilt) use **stricter** stepping/soak; **dev/QA** prioritize **iteration speed** and leave **ALB % canary** off by default.

##### Future hardening (beyond ALB SPA split)

**Argo Rollouts**, **Flagger**, or a **mesh** for **metric-driven** ramps and **per-API** revision splits—see [docs/partial-canary-justification.md](docs/partial-canary-justification.md) §6.

Workloads and Ingress live in Terraform module **`eks_app`** ([`infra/modules/eks-app`](infra/modules/eks-app)).

**State after the `eks_app` rename:** If remote state still lists `module.app_bluegreen.*`, run once per env (after `terraform init` against the same S3 backend GitHub Actions uses).

From the repo root, with **`TF_STATE_BUCKET`** and **`TF_LOCK_TABLE`** set (your Actions secrets) and AWS credentials in the environment:

```bash
export TF_STATE_BUCKET=… TF_LOCK_TABLE=…
export AWS_REGION=us-east-1   # if different from default

bash infra/scripts/terraform-migrate-remote-state-for-eks-app-rename.sh dev
bash infra/scripts/terraform-migrate-remote-state-for-eks-app-rename.sh qa
bash infra/scripts/terraform-migrate-remote-state-for-eks-app-rename.sh prod
# If you still have a UAT state object in S3 from before teardown, run for uat too; skip if UAT will be created from an empty state.
```

Manual equivalent (per env directory): `terraform init -reconfigure` with the same `-backend-config=…` flags as [`.github/workflows/promotion.yml`](.github/workflows/promotion.yml), then `bash ../../scripts/terraform-state-mv-module-to-eks-app.sh`.

### 2. Deployment & CI/CD (git-driven promotion)

| Requirement | Status |
| ----------- | ------ |
| Dev → nightly QA → UAT → Prod | **Implemented** — [`promotion.yml`](.github/workflows/promotion.yml) (dev on push to `main`; QA on schedule + manual; **UAT on PR merged to `main` (same repo) or `RC` in commit message**; prod on `v*` tags + manual) |
| Dev/QA → UAT (Conventional Commits / PR merge) | **Implemented** — Merging an in-repo PR into `main` promotes to UAT. Optional **`RC` token** in the tip merge commit subject/body still works for direct pushes. Fork PR merges are skipped (deploy via `workflow_dispatch` → UAT instead). |
| UAT → Prod via tags (no console deploy) | **Implemented (initial)** — `v*` tags + `workflow_dispatch` prod |
| Documented rollout strategy (rubric) | **Done (written)** — Progressive **hosted-service canary** above (UAT/Prod `maxSurge: 1` + `minReadySeconds` soak); code in [`infra/modules/eks-app`](infra/modules/eks-app) |
| Zero downtime | **Partial** — rollout settings + probes gate traffic; capture workflow/Grafana evidence during a promotion |

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
| **Node OS / AMI patching** without interrupting service | **Runbook + scripts** — [docs/day2-os-node-patching.md](docs/day2-os-node-patching.md), [`infra/scripts/eks-node-patch-evidence.sh`](infra/scripts/eks-node-patch-evidence.sh); you still **capture Console/CLI proof** (**P1–P3**) when a patch is available |

### 4. Observability & logging

| Requirement | Status |
| ----------- | ------ |
| Self-hosted Prometheus + Grafana on-cluster | **Implemented** (optional per env) — [`infra/modules/platform/observability.tf`](infra/modules/platform/observability.tf), `kube-prometheus-stack` |
| Grafana external + **OAuth2** (no password login) | **Implemented** when observability stack is enabled — Google OAuth; see env vars / secrets in platform module |
| Dashboards CPU / memory / disk + alerts | **Implemented** — node metrics via stack; Alertmanager SMTP when configured; **capture alert receipt** for grading |
| Central logs (e.g. Loki) across all backends | **Implemented** when enabled — Loki + Promtail; optional per env |

---

## What still needs to be done (assignment checklist)

See **[REQUIREMENTS_CHECKLIST.md](REQUIREMENTS_CHECKLIST.md)** and unchecked items in **[REQUIREMENTS.md](REQUIREMENTS.md)**. Highest impact next:

1. **Observability evidence (15%)** — Screenshots/recording: Grafana OAuth, dashboards, Loki queries; run **alert drill** and save **email/Slack proof**.
2. **Day 2 OS patching (10%)** — Follow [docs/day2-os-node-patching.md](docs/day2-os-node-patching.md): run nodegroup AMI/release update **or** narrate readiness; grab **before/after** + **`http-availability-during-rollout.sh`** transcript if possible.
3. **Day 2 schema change (10%)** — You have migrate; prepare a **graded narrative**: show a schema change, how it ships, and how rollback / safety works.
4. **Zero-downtime evidence** — Use [docs/zero-downtime-promotion-evidence.md](docs/zero-downtime-promotion-evidence.md) + [`infra/scripts/http-availability-during-rollout.sh`](infra/scripts/http-availability-during-rollout.sh); refresh **`C6`** clip or log snippet.
5. **Presentation & chaos defense** — Silent video allowed for long runs; **live narration**; practice using metrics/logs to find a failure in 1–2 minutes.

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

`terraform-destroy-all.sh` best-effort deletes **app Ingress** in the **`dev`/`qa`/`uat`/`prod`** namespace and **every Ingress (and LB Services) in `monitoring`** before Terraform destroys `module.platform` — that includes Grafana’s observability ALB so VPC teardown is less likely to stick on ENIs.

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

---

## Operations docs

- Day 2 runbook (node patching + schema change): [`docs/day2-runbook.md`](docs/day2-runbook.md)
- Failure playbook (common incidents + fixes): [`docs/failure-playbook.md`](docs/failure-playbook.md)

---

## Notes / architecture (implemented)

- **Frontend:** React + Vite (`web/`). In production it calls **same-origin** (`window.location.origin`) so it works behind an ALB Ingress at `/api/v1/...`.
- **HEIC:** converted client-side via `heic-to` when needed (`web/src/heicConvert.ts`).
- **Backend:** Go + Chi services under `cmd/*-service/`.
- **Database:** Postgres schema in `cmd/migrate/schema.sql` (applied by `cmd/migrate`).
- **Infra:** Terraform modules under `infra/` (EKS, RDS, ECR, ALB ingress controller, ExternalDNS, app deployments).

---

