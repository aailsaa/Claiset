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

variable "oidc_provider_arn" {
  type        = string
  description = "EKS cluster OIDC provider ARN (for IRSA)."
  default     = ""
}

variable "oidc_issuer_url" {
  type        = string
  description = "EKS cluster OIDC issuer URL (for IRSA)."
  default     = ""
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
  # Set to "" to issue ACM cert for apex (domain_root) instead of app.domain_root.
}

variable "wait_for_acm_validation" {
  type        = bool
  default     = true
  description = "When false, Terraform does not wait for aws_acm_certificate_validation (use if DNS/delegation is not ready yet). Ingress TLS may stay pending until you validate and re-apply."
}

variable "enable_observability_stack" {
  type        = bool
  default     = false
  description = "Self-hosted metrics/logging: kube-prometheus-stack (Prometheus, Grafana, Alertmanager), Loki, Promtail. Requires domain, ACM wait, and Grafana Google OAuth credentials."

  validation {
    condition = !var.enable_observability_stack || (
      trimspace(var.grafana_google_client_id) != "" &&
      length(trimspace(var.grafana_google_client_secret)) > 0
    )
    error_message = "When enable_observability_stack is true, set non-empty grafana_google_client_id and grafana_google_client_secret."
  }
}

variable "grafana_google_client_id" {
  type        = string
  default     = ""
  description = "Google OAuth Web client ID for Grafana. Add authorized redirect: https://grafana-<env>.<domain_root>/login/google"
}

variable "grafana_google_client_secret" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Google OAuth client secret for Grafana."
}

variable "grafana_google_allowed_domains" {
  type        = string
  default     = ""
  description = "Optional comma-separated Google allowed domains for Grafana sign-in (empty = any account allowed by your OAuth client configuration)."
}

variable "alertmanager_email_to" {
  type        = string
  default     = ""
  description = "Optional alert email recipient; set with SMTP fields below."
}

variable "alertmanager_smtp_smarthost" {
  type        = string
  default     = ""
  description = "SMTP relay host:port, e.g. smtp.gmail.com:587"
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

