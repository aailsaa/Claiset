output "route53_zone_id" {
  value       = module.platform.route53_zone_id
  description = "Route53 hosted zone ID for the domain (if created)."
}

output "route53_nameservers" {
  value       = module.platform.route53_nameservers
  description = "Set these as your registrar nameservers (Name.com)."
}

output "frontend_hostname" {
  value       = module.platform.frontend_hostname
  description = "Intended public hostname for the frontend."
}

output "frontend_certificate_arn" {
  value       = module.platform.frontend_certificate_arn
  description = "ACM certificate ARN for app.<domain> (once validated)."
}

output "ecr_repository_urls" {
  value       = local.ecr_repository_urls
  description = "ECR repo URLs (repos created in envs/dev; shared across environments)."
}

output "grafana_url" {
  value       = module.platform.grafana_url
  description = "Grafana URL when observability stack is enabled."
}

