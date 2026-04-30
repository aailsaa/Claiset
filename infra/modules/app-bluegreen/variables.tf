variable "project" {
  type = string
}

variable "env" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "domain_root" {
  type    = string
  default = ""
}

variable "frontend_subdomain" {
  type    = string
  default = "app"
}

variable "frontend_certificate_arn" {
  type        = string
  description = "ACM certificate ARN for the frontend hostname (for ALB Ingress TLS)."
  default     = ""
}

