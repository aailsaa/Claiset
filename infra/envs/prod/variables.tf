variable "aws_region" {
  type        = string
  description = "AWS region for this environment."
  default     = "us-east-1"
}

variable "env" {
  type        = string
  description = "Environment name (dev, qa, uat, prod)."
  default     = "prod"
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
  description = "EKS node instance types. This account currently enforces free-tier-eligible node types, so keep this list to free-tier options only."
  default     = ["t3.micro", "t2.micro"]
}

variable "node_group_desired_size" {
  type        = number
  description = "EKS managed node group desired capacity."
  default     = 4
}

variable "node_group_min_size" {
  type        = number
  description = "EKS managed node group minimum capacity. Keep high enough that monitoring + apps fit without exhausting VPC-CNI pod density."
  default     = 2
}

variable "node_group_max_size" {
  type        = number
  description = "EKS managed node group maximum capacity."
  default     = 16
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
  description = "Subdomain for the frontend; must match Ingress/smoke (e.g. app-prod for https://app-prod.<domain_root>). QA/UAT use app-qa / app-uat."
  default     = "app-prod"
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
  description = <<-EOT
    Self-hosted Prometheus, Grafana (Google OAuth), Loki, Promtail. CI sets true via repository variable ENABLE_OBSERVABILITY and Grafana TF_VAR_* secrets.
    Defaults false locally so plans work without OAuth; for local terraform import of monitoring resources, set true plus grafana_google_client_id/secret (same as CI). See docs/failure-playbook.md §9.
  EOT
}

variable "enable_observability_daemonsets" {
  type        = bool
  default     = false
  description = <<-EOT
    Keep false on free-tier micro nodes: node-exporter/promtail DaemonSets consume scarce pod slots
    and can block app scheduling (Too many pods). Set true only when node size/capacity is increased.
  EOT
}

variable "grafana_google_client_id" {
  type        = string
  default     = ""
  description = "Grafana OAuth (Google) Web client ID. Add redirect https://grafana-prod.<domain>/login/google."
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

