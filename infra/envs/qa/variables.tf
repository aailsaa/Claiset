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

variable "frontend_subdomain" {
  type        = string
  description = "Subdomain for the frontend (e.g. app). Full name becomes app.<domain_root>."
  default     = "app-qa"
}

