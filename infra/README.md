## Terraform infrastructure (EKS + RDS + Blue/Green)

This folder is the **only place** AWS / Kubernetes infrastructure is managed. No console click-ops.

### Layout
- `envs/dev`: first environment to stand up (us-east-1)
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
This repo includes a placeholder `backend.tf` in `envs/dev`.
For grading, you should use an S3 backend + DynamoDB lock (all via Terraform).

### Domain / HTTPS (required for rubric)
The frontend must be reachable at a custom DNS name over HTTPS.
This scaffolding expects:
- a Route53 hosted zone (Terraform-managed)
- an ALB Ingress with TLS (ACM or cert-manager/Let's Encrypt depending on what you choose)

