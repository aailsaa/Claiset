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
  # Set to "" to use apex as canonical host (domain_root directly).
}

variable "include_apex_and_www_in_external_dns" {
  type        = bool
  default     = false
  description = "If true, Ingress external-dns hostname list includes apex and www. Use true only for prod so root DNS is not repointed by non-prod clusters."
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

variable "migrate_schema_sha" {
  type        = string
  default     = ""
  description = <<-EOT
    When non-empty (e.g. filesha256 of cmd/migrate/schema.sql), terraform_data replaces kubernetes_job.migrate when the schema file changes.
    OnlineCloset: infra/envs/{dev,qa,uat,prod} pass filesha256(schema.sql).
  EOT
}

variable "enable_kubernetes_app" {
  type        = bool
  default     = true
  description = "When false, skips counted app workloads so counts do not depend on database_url / ACM (e.g. terraform import). Re-enable for normal apply."
}

variable "replicas" {
  type        = number
  default     = 2
  description = "Replica count per service Deployment (items/outfits/schedule/web). Use 1 on tiny dev node groups to avoid pod-IP limits."
}

variable "rolling_update_max_surge" {
  type        = string
  default     = "25%"
  description = "Deployment RollingUpdate maxSurge (percentage or integer). Keeps replacements small; tighter values (e.g. \"1\") step one replica at a time when burst capacity matters."
}

variable "rolling_update_max_unavailable" {
  type        = string
  default     = "0"
  description = "Deployment RollingUpdate maxUnavailable. Zero favors availability during roll (new pods ready before old ones terminate)."
}

variable "rollout_min_ready_seconds" {
  type        = number
  default     = 0
  description = "Seconds a new Pod must stay Ready without failing before the rollout treats it stable (lightweight soak; 0 disables)."
}

variable "rollout_progress_deadline_seconds" {
  type        = number
  default     = 900
  description = "Fails the rollout controller if Pods do not make progress — surfaces stuck migrations or image pulls."
}

variable "web_rollout_prestop_sleep_seconds" {
  type        = number
  default     = 35
  description = "preStop sleep on web Pods so AWS LB controller can deregister target IPs before nginx stops (fewer rollout 502s)."
}

variable "web_pod_termination_grace_seconds" {
  type        = number
  default     = 90
  description = "Termination grace window; must comfortably exceed web_rollout_prestop_sleep_seconds."
}

variable "enable_pod_disruption_budget" {
  type        = bool
  default     = true
  description = "When true and replicas > 1, PDBs reserve capacity during voluntary evictions (node drain, cluster upgrades)."
}

variable "pod_disruption_min_available_percent" {
  type        = string
  default     = "50%"
  description = "PDB minAvailable as IntOrString (e.g. \"50%\" or \"1\"). Ignored unless enable_pod_disruption_budget and replicas > 1."
}

variable "enable_alb_weighted_canary_for_web" {
  type        = bool
  default     = false
  description = <<-EOT
    Per-environment Terraform toggle (set in infra/envs/<env>/main.tf or override with TF_VAR_enable_alb_weighted_canary_for_web in a promotion job).
    When true with alb_web_canary_traffic_percent > 0 and web_canary_replicas > 0, ALB splits browser traffic (Ingress path "/") between Service web and web-canary. APIs stay single-target (cost control).
  EOT
}

variable "alb_web_canary_traffic_percent" {
  type        = number
  default     = 0
  description = "Percent of SPA traffic sent to web-canary (1–50). Stable web receives 100 minus this value. Use 0 to disable split while keeping enable flag false in most envs."
  validation {
    condition     = var.alb_web_canary_traffic_percent >= 0 && var.alb_web_canary_traffic_percent <= 50
    error_message = "alb_web_canary_traffic_percent must be between 0 and 50."
  }
}

variable "web_canary_replicas" {
  type        = number
  default     = 0
  description = <<-EOT
    Desired minimum for Deployment web-canary when weighted canary is on. The module enforces max(your value, 2) while weighted routing is active so RollingUpdate never leaves the canary Service with zero Ready endpoints (ALB would drop that traffic share). When weighted canary is off, replicas are forced to 0 regardless of this input.
  EOT
  validation {
    condition     = var.web_canary_replicas >= 0 && var.web_canary_replicas <= 5
    error_message = "web_canary_replicas must be between 0 and 5."
  }
}

