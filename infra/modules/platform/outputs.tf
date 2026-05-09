output "route53_zone_id" {
  value       = local.zone_id
  description = "Hosted zone ID used for ACM/DNS (explicit, looked up by name, or newly created)."
}

output "route53_nameservers" {
  value = (
    length(aws_route53_zone.this) > 0 ? aws_route53_zone.this[0].name_servers : (
      length(data.aws_route53_zone.lookup) > 0 ? data.aws_route53_zone.lookup[0].name_servers : (
        length(data.aws_route53_zone.by_id) > 0 ? data.aws_route53_zone.by_id[0].name_servers : []
      )
    )
  )
  description = "Route53 delegation nameservers for this zone (empty if unknown)."
}

output "frontend_hostname" {
  value       = local.frontend_host
  description = "Public hostname for the frontend."
}

output "frontend_certificate_arn" {
  value = var.domain_root == "" ? null : (
    var.wait_for_acm_validation ? try(aws_acm_certificate_validation.frontend[0].certificate_arn, null) : try(aws_acm_certificate.frontend[0].arn, null)
  )
  description = "ACM certificate ARN (ISSUED after validation, or pending ARN if wait_for_acm_validation is false)."
}

output "grafana_url" {
  value       = local.observability_enabled ? "https://${local.grafana_host}" : null
  description = "Public Grafana URL when the self-hosted observability stack is enabled."
}

