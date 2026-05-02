variable "project" {
  type = string
}

variable "env" {
  type = string
}

variable "region" {
  type        = string
  description = "AWS region (used by controllers)."
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name."
}

variable "vpc_id" {
  type        = string
  description = "VPC ID (used by ALB controller)."
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "domain_root" {
  type    = string
  default = ""
}

variable "hosted_zone_id" {
  type        = string
  description = "If set, use this Route53 hosted zone ID (required when multiple zones share the same domain name)."
  default     = ""
}

variable "create_hosted_zone" {
  type        = bool
  default     = false
  description = "If true, create a new public hosted zone for domain_root. If false and hosted_zone_id is empty, look up an existing zone by name (fails if none or if multiple match)."
}

variable "frontend_subdomain" {
  type    = string
  default = "app"
}

variable "wait_for_acm_validation" {
  type        = bool
  default     = true
  description = "When false, Terraform does not wait for aws_acm_certificate_validation (use if DNS/delegation is not ready yet). Ingress TLS may stay pending until you validate and re-apply."
}

