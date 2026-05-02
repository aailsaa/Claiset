## Terraform infrastructure (EKS + RDS + Blue/Green)

This folder is the **only place** AWS / Kubernetes infrastructure is managed. No console click-ops.

### Layout
- `envs/dev`: first environment to stand up (us-east-1)
- `envs/qa`, `envs/uat`, `envs/prod`: promotion environments (same modules; different image tags and hostnames)
- `modules/*`: reusable building blocks (VPC, EKS, RDS, platform add-ons, app blue/green)

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

### Promotion workflow (git-driven)
CI/CD is implemented via GitHub Actions in [`.github/workflows/promotion.yml`](../.github/workflows/promotion.yml):
- **Dev**: push to `main` builds/pushes images tagged `:dev` and applies Terraform in `envs/dev`
- **QA (nightly)**: scheduled run retags `:dev` → `:qa` and applies Terraform in `envs/qa`
- **UAT**: commits to `main` containing `RC` retag `:qa` → `:uat` and applies Terraform in `envs/uat`
- **Prod**: pushing a tag like `v1.0.1` retags `:uat` → `:prod` and applies Terraform in `envs/prod`

You must configure repo secrets:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN` (required for AWS Academy/Vocareum sessions)

(See also state/backend secrets and `ROUTE53_HOSTED_ZONE_ID` in the list above.)

### Domain / HTTPS (required for rubric)
The frontend must be reachable at a custom DNS name over HTTPS.
This scaffolding expects:
- a Route53 hosted zone (Terraform-managed)
- an ALB Ingress with TLS (ACM or cert-manager/Let's Encrypt depending on what you choose)

