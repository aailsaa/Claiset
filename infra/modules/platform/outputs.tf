output "route53_zone_id" {
  value       = var.hosted_zone_id != "" ? var.hosted_zone_id : try(aws_route53_zone.this[0].zone_id, null)
  description = "Hosted zone ID if a zone was created."
}

output "route53_nameservers" {
  value       = try(aws_route53_zone.this[0].name_servers, [])
  description = "Registrar nameservers to configure (Name.com)."
}

output "frontend_hostname" {
  value       = var.domain_root != "" ? "${var.frontend_subdomain}.${var.domain_root}" : ""
  description = "Public hostname for the frontend."
}

output "frontend_certificate_arn" {
  value       = try(aws_acm_certificate_validation.frontend[0].certificate_arn, null)
  description = "ACM certificate ARN for the frontend hostname (after DNS validation)."
}

