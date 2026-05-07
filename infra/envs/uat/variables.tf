variable "aws_region" {
  type        = string
  description = "AWS region for this environment."
  default     = "us-east-1"
}

variable "env" {
  type        = string
  description = "Environment name (dev, qa, uat, prod)."
  default     = "uat"
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
  description = "EKS node instance types (passed to infra/modules/eks). t3.small avoids ~4-pod/node cap on t3.micro (VPC CNI) that blocks platform controllers + app."
  default     = ["t3.small"]
}

variable "node_group_desired_size" {
  type        = number
  description = "EKS managed node group desired capacity. Steady-state headroom for ALB controller, external-dns, autoscaler, and app without waiting on CA."
  default     = 2
}

variable "node_group_min_size" {
  type        = number
  description = "EKS managed node group minimum capacity. Keep 1 when idle so Cluster Autoscaler can scale down for cost."
  default     = 1
}

variable "node_group_max_size" {
  type        = number
  description = "EKS managed node group maximum capacity. Must exceed peak pod demand; CA uses this ceiling during rollouts."
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
  default     = "app-uat"
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

