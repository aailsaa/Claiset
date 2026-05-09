# Evidence media checklist (screenshots & recordings)

Use this list to **capture everything before teardown** or on the next healthy env (**dev**/**uat**/**prod**—adjust hostnames accordingly). Prefer **silent screen recordings** for long flows; narrate live over them during the defense per the rubric.

**Cross-links:** [REQUIREMENTS_CHECKLIST.md](../REQUIREMENTS_CHECKLIST.md) · [REQUIREMENTS.md](../REQUIREMENTS.md) · [final-defense-script.md](final-defense-script.md)

---

## Pre-capture (once)

- [ ] Create a folder, e.g. `submission-media/2026-05-09/` (dated), and drop all files there with short names: `01-app-home.png`, `02-rds-console.png`, etc.
- [ ] Note **which environment** each capture is from (`dev` / `uat` / `prod`) in a `README.txt` in that folder.
- [ ] Save **URLs** to green **GitHub Actions** runs (dev, UAT merge, prod dispatch) in a text file for your slide deck.

---

## Architecture & Terraform (≈20% + part of 15%)

| # | Artifact | What to show |
|---|----------|----------------|
| A1 | **Screenshot** | App **homepage** + one **inner page** (items/outfits/calendar). URL bar visible with **HTTPS** lock. |
| A2 | **Screenshot** | **AWS RDS** console: instance **identifier**, engine, **Available**, same region as EKS. |
| A3 | **Screenshot or terminal paste** | `terraform state list` (excerpt) showing **RDS** + **EKS**-related resources, or `module.rds.*` / `module.eks.*` lines. |
| A4 | **Screenshot** | `kubectl -n <env> get deploy` showing **`items`**, **`outfits`**, **`schedule`** (and `web` if you want). |
| A5 | **Screenshot** | **Ingress**: `kubectl -n <env> get ingress` (or AWS console ALB listener **HTTPS**) showing hostname / certificate in use. |
| A6 | **Screenshot(s)** | **IDE or GitHub**: `infra/modules/` tree OR 1–2 module files proving **VPC / EKS / RDS / IAM** live under Terraform—not required to be flashy. |

---

## CI/CD & Git-driven promotion (≈15%)

| # | Artifact | What to show |
|---|----------|----------------|
| C1 | **Screenshot** | GitHub Actions **workflow graph** for **promotion** (`promotion.yml`)—at least one **successful** path (e.g. dev + UAT or prod). |
| C2 | **Screenshot / link** | Run triggered by **`pull_request`** **merged** → **UAT** (shows merge commit / PR number in summary). |
| C3 | **Screenshot / link** | **Prod** (or gated prod) triggered by **`workflow_dispatch`** / tag—**Summary** showing **Inputs** (`target: prod`) and **no AWS Console deploy** narrative in slide. |
| C4 | **Screenshot or snippet** | **Terraform apply** log excerpt (green) from Actions **or** terminal—proves automation. |
| C5 | **Slide or cite README** | **Canary-style rolling** strategy: one slide pointing to **[README.md](../README.md)** “Deployment strategy for EKS” (no separate recording required beyond rubric ). |
| C6 | **Short clip OR logs** (**zero-downtime row**) | Prefer: **silent** screen record of **deployment rollout** with **kubectl** `rollout status` **or** workflow step “rollout succeeded” **plus** a **health** probe (curl 2xx to `/health` / front page) **during** the rollout window. Alternate: Grafana **HTTP 5xx** panel flat at 0 over rollout if you have it. |

---

## Day 2: schema migration (≈10%)

| # | Artifact | What to show |
|---|----------|----------------|
| D1 | **Screenshot** | `kubectl -n <env> get jobs` with **`migrate`** **Complete** or recent. |
| D2 | **Screenshot or terminal paste** | `kubectl -n <env> describe job migrate` (key lines: completion, backoff). |
| D3 | **Optional short clip** | You explaining **migrate image** runs **before** app Deployments rely on schema (can be narrated slide + `schema.sql`/migrate reference). |

---

## Day 2: OS / security patching (≈10%)

| # | Artifact | What to show |
|---|----------|----------------|
| P1 | **Screenshot(s)** | **Before**: EKS **node group** (console or CLI) AMI / release version / launch template version. |
| P2 | **Screenshot(s)** | **After** a roll or AMI update—the field **changed**. |
| P3 | **Recording or logs** | **Smoke/tests still pass** during/after rotation (workflow green **or** `kubectl get nodes` + app **Ready**). |
| P4 | **1 slide** | **Your spoken logic**: cordon/drain/maxUnavailable / surge / why users still get healthy pods—match what you actually did (managed node group update, etc.). |

---

## Observability & logging (≈15%)

Record **one continuous silent screen capture** (**3–8 min**) if possible; split into clips if easier.

| # | Artifact | What to show |
|---|----------|----------------|
| O1 | **Screenshot** | `kubectl -n monitoring get pods`—**Prometheus / Grafana / Loki** (and **Alertmanager** if enabled) **Running**. |
| O2 | **Recording** | **Grafana** on **`https://grafana-<env>.<domain>`**—**URL bar** visible. |
| O3 | **Recording** | **Google OAuth**: click **Sign in with Google** → **redirect** → **land in Grafana** (no password-as-primary story). |
| O4 | **Recording** | **Explore → Prometheus**: one query with data (e.g. `up`, or node CPU). |
| O5 | **Recording** | **Node metrics**: **CPU**, **memory**, and **disk** (dashboard or Explore—rubric asks for all three). |
| O6 | **Recording** | **Explore → Loki**: `{namespace="<env>",container="items"}` then **outfits**, **schedule**; then `{namespace="<env>"}` or combined filter. Time range **Last 15m** / **1h** after hitting APIs. |
| O7 | **Screenshot** | **Alertmanager → email** (**or Slack**): **received** notification after **`infra/scripts/alert-drill.sh`** (or your drill). Include **terminal** output of drill command if needed. |

---

## Presentation format (≈15% rubric bucket)

| # | Artifact | What to show |
|---|----------|----------------|
| S1 | **Silent video** | **Long-running** parts only: Terraform apply / nodegroup update / **`terraform destroy`** excerpt—**no voice on file** per assignment. |
| S2 | **Prepared deck** | Slides embedding **thumbnail + link** to recordings; bullets from **[final-defense-script.md](final-defense-script.md)**. |
| S3 | **Practice** | **Timed** **chaos story** (below)—**2-minute** rehearsal with a timer. |

---

## Live demo only (minimal—do live)

Do **not** rely on prod staying up for these **during** grading; rehearse against **dev/uat** or **dry-run** Grafana if needed.

| # | Live item | Why it’s live |
|---|-----------|----------------|
| L1 | **Narration** | Rubric expects you to **narrate** over the silent / pre-recorded material—**your voice**, not new clicking. |
| L2 | **Chaos defense (~1–2 min)** | Instructor gives a **random failure**; you **live** use **metrics + logs** to **diagnose** and **explain recovery** (e.g. pending pod + events, Loki query, Prometheus alert, rollout). **Prepare** 2–3 “likely” scenarios and **bookmark** Explore queries; **avoid** depending on a cold prod cluster. |
| L3 | **Q&A** | Short **live** answers; optional: show **one** pre-opened Grafana tab if network allows—**not** required if clips already prove it. |

**Optional** (only if asked): single **live** `kubectl get pods -n <env>` or **one** Grafana query—keep a **fallback screenshot** if Wi‑Fi fails.

---

## Quick “done” gate

- [ ] Every **unchecked** row in [REQUIREMENTS_CHECKLIST.md](../REQUIREMENTS_CHECKLIST.md) has at least one **file** or **URL** in your bundle.
- [ ] **Self-grading** comments filled (template at bottom of checklist).
- [ ] **Chaos** rehearsed **twice** with timer.
