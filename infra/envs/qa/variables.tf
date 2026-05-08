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

variable "node_instance_types" {
  type        = list(string)
  description = "EKS node instance types (passed to infra/modules/eks). t3.small avoids ~4-pod/node cap on t3.micro (VPC CNI)."
  default     = ["t3.small"]
}

variable "node_group_desired_size" {
  type        = number
  description = "EKS managed node group desired capacity."
  default     = 2
}

variable "node_group_min_size" {
  type        = number
  description = "EKS managed node group minimum capacity."
  default     = 1
}

variable "node_group_max_size" {
  type        = number
  description = "EKS managed node group maximum capacity. CA + CI burst use this ceiling."
  default     = 6
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

variable "enable_observability_stack" {
  type        = bool
  default     = false
  description = "Self-hosted Prometheus, Grafana (Google OAuth), Alertmanager optional email, Loki, Promtail. CI sets TF_VAR_enable_observability_stack from repo variable ENABLE_OBSERVABILITY."
}

variable "grafana_google_client_id" {
  type        = string
  default     = ""
  description = "Grafana OAuth (Google) Web client ID. Add redirect https://grafana-qa.<domain>/login/google (per env)."
}

variable "grafana_google_client_secret" {
  type      = string
  default   = ""
  sensitive = true
}

variable "grafana_google_allowed_domains" {
  type    = string
  default = ""
}

variable "alertmanager_email_to" {
  type    = string
  default = ""
}

variable "alertmanager_smtp_smarthost" {
  type    = string
  default = ""
}

variable "alertmanager_smtp_from" {
  type    = string
  default = ""
}

variable "alertmanager_smtp_user" {
  type    = string
  default = ""
}

variable "alertmanager_smtp_password" {
  type      = string
  default   = ""
  sensitive = true
}

