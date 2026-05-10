variable "aws_region" {
  type        = string
  description = "AWS region for this environment."
  default     = "us-east-1"
}

variable "env" {
  type        = string
  description = "Environment name (dev, qa, uat, prod)."
  default     = "dev"
}

variable "project" {
  type        = string
  description = "Project name prefix used for resource names/tags."
  default     = "claiset"
}

variable "ecr_repository_prefix" {
  type        = string
  description = "Shared ECR repo prefix for this account (e.g. claiset-items). Must match Actions image repo names."
  default     = "claiset"
}

variable "eks_cluster_version" {
  type        = string
  description = "EKS Kubernetes version for this environment."
  default     = "1.31"
}

variable "eks_node_group_kubernetes_version" {
  type        = string
  default     = null
  nullable    = true
  description = "Optional. Pin managed node group kubelet to this version; leave null so LT-only updates are not bundled with UpdateNodegroupVersion (avoids AWS launch-template instance-type errors)."
}

variable "node_instance_types" {
  type        = list(string)
  description = "EKS node instance types (passed to infra/modules/eks). Dev uses t3.small to keep enough pod/IP capacity for always-on web availability between deploys."
  default     = ["t3.small"]
}

variable "node_group_desired_size" {
  type        = number
  description = "EKS managed node group desired capacity."
  # Raise baseline for reliability during normal dev access; manual scale-down can be used to save cost.
  default = 3
}

variable "node_group_min_size" {
  type        = number
  description = "EKS managed node group minimum capacity."
  # Keep at least 2 nodes so core platform + app pods avoid frequent Pending states.
  default = 2
}

variable "node_group_max_size" {
  type        = number
  description = "EKS managed node group maximum capacity."
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
  description = "Subdomain for the frontend. Use app-dev so apex (claiset.xyz) can stay on prod; empty uses apex as canonical (not recommended with shared zone)."
  default     = "app-dev"
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

variable "enable_alb_weighted_canary_for_web" {
  type        = bool
  default     = false
  description = "ALB weighted SPA canary (see infra/modules/eks-app). Default off in dev for cost; enable via true or TF_VAR_* on the dev promotion apply."
}

variable "alb_web_canary_traffic_percent" {
  type        = number
  default     = 0
  description = "Percent to web-canary when enable_alb_weighted_canary_for_web is true (1–50)."
}

variable "web_canary_replicas" {
  type        = number
  default     = 0
  description = "Desired floor for web-canary; module bumps to ≥2 when weighted canary is on."
}

variable "enable_observability_stack" {
  type        = bool
  default     = false
  description = "Self-hosted Prometheus, Grafana (Google OAuth), Alertmanager optional email, Loki, Promtail. Set true plus OAuth client + secret to deploy."
}

variable "grafana_google_client_id" {
  type        = string
  default     = ""
  description = "Grafana OAuth (Google) client ID — add redirect https://grafana-dev.<your-domain>/login/google"
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

