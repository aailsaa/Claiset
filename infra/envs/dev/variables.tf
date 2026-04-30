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
  default     = "onlinecloset"
}

variable "eks_cluster_version" {
  type        = string
  description = "EKS Kubernetes version for this environment."
  default     = "1.31"
}

variable "domain_root" {
  type        = string
  description = "Root domain you control (e.g. example.com). Terraform can create a hosted zone, but you must update your registrar name servers."
  default     = "claiset.xyz"
}

variable "frontend_subdomain" {
  type        = string
  description = "Subdomain for the frontend (e.g. app). Full name becomes app.<domain_root>."
  default     = "app"
}

