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

variable "google_client_id" {
  type        = string
  description = "GOOGLE_CLIENT_ID env var for backend services."
  default     = ""
}

variable "database_url" {
  type        = string
  description = "DATABASE_URL for backend services (Postgres)."
  default     = ""
}

variable "aws_region" {
  type        = string
  description = "Region where ECR registries live (used to build ECR docker pull credentials when app is enabled)."
  default     = ""
}

variable "images" {
  type = object({
    items    = string
    outfits  = string
    schedule = string
    web      = string
    migrate  = string
  })
  description = "Container images for each service."
}

