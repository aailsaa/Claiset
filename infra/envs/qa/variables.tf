variable "aws_region" {
  type        = string
  description = "AWS region for this environment."
  default     = "us-east-1"
}

variable "env" {
  type        = string
  description = "Environment name (dev, qa, uat, prod)."
  default     = "qa"
}

variable "project" {
  type        = string
  description = "Project name prefix used for resource names/tags."
  default     = "claiset"
}

variable "ecr_repository_prefix" {
  type        = string
  description = "Shared ECR repo prefix (must match infra/envs/dev and GitHub Actions)."
  default     = "claiset"
}

variable "eks_cluster_version" {
  type        = string
  description = "EKS Kubernetes version for this environment."
  default     = "1.31"
}

variable "google_client_id" {
  type        = string
  description = "OAuth Web Client ID used to validate Google ID tokens in backend services."
  default     = "551920137993-5re842ov91rtdbtil3o6vi8lglmvpool.apps.googleusercontent.com"
}

variable "domain_root" {
  type        = string
  description = "Root domain you control (e.g. example.com). Terraform can create a hosted zone, but you must update your registrar name servers."
  default     = "claiset.xyz"
}

variable "route53_hosted_zone_id" {
  type        = string
  description = "Use this zone ID when it is set. Strongly recommended if multiple hosted zones exist for the same domain."
  default     = ""
}

variable "create_hosted_zone" {
  type        = bool
  default     = false
  description = "If true, Terraform creates a new public zone for domain_root. If false, looks up an existing zone by name (or use route53_hosted_zone_id)."
}

variable "frontend_subdomain" {
  type        = string
  description = "Subdomain for the frontend (e.g. app). Full name becomes app.<domain_root>."
  default     = "app-qa"
}

variable "wait_for_acm_validation" {
  type        = bool
  default     = true
  description = "Set false if DNS/Route53 is not yet delegating correctly; avoids multi-hour apply waits (TLS may stay PENDING until fixed)."
}

variable "enable_kubernetes_app" {
  type        = bool
  default     = true
  description = "Set false only for targeted terraform import when app inputs may be unknown."
}

