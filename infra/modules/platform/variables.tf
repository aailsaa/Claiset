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
  description = "If set, reuse an existing Route53 hosted zone instead of creating a new one."
  default     = ""
}

variable "frontend_subdomain" {
  type    = string
  default = "app"
}

