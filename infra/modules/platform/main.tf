locals {
  name = "${var.project}-${var.env}"
  zone_id = var.hosted_zone_id != "" ? var.hosted_zone_id : try(aws_route53_zone.this[0].zone_id, null)
}

# DNS hosted zone (Terraform-managed). You still need to update your registrar
# to use the Route53 nameservers that Terraform creates.
resource "aws_route53_zone" "this" {
  count = var.domain_root != "" && var.hosted_zone_id == "" ? 1 : 0
  name  = var.domain_root

  tags = var.tags
}

# ACM certificate for the frontend hostname (DNS validated in Route53).
resource "aws_acm_certificate" "frontend" {
  count             = var.domain_root != "" ? 1 : 0
  domain_name       = "${var.frontend_subdomain}.${var.domain_root}"
  validation_method = "DNS"
  tags              = var.tags
}

resource "aws_route53_record" "frontend_cert_validation" {
  for_each = var.domain_root != "" ? {
    for dvo in aws_acm_certificate.frontend[0].domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  } : {}

  zone_id = local.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "frontend" {
  count                   = var.domain_root != "" ? 1 : 0
  certificate_arn         = aws_acm_certificate.frontend[0].arn
  validation_record_fqdns = [for r in aws_route53_record.frontend_cert_validation : r.fqdn]
}

# Placeholder module: in follow-ups we will install:
# - AWS Load Balancer Controller (ALB Ingress)
# - external-dns (Route53 records)
# - cert-manager (or ACM wiring)
# - Prometheus + Grafana (OAuth2 only) + Alertmanager
# - Loki + Promtail (centralized logs)
#
# All installed via Terraform-managed `helm_release` and/or `kubernetes_manifest`.

resource "kubernetes_namespace" "platform" {
  metadata {
    name = "platform"
    labels = {
      "app.kubernetes.io/part-of" = var.project
      "env"                       = var.env
    }
  }
}

# AWS Load Balancer Controller (IngressClass: alb)
# Note: AWS Academy accounts often restrict IAM role creation (IRSA). This install
# relies on the node IAM role (LabRole) having permission.
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  # Avoid AWS Academy IAM/IRSA constraints by using node credentials (IMDS).
  # hostNetwork removes extra network hops to IMDS in some CNI setups.
  set {
    name  = "hostNetwork"
    value = "true"
  }
  set {
    name  = "dnsPolicy"
    value = "ClusterFirstWithHostNet"
  }

  set {
    name  = "clusterName"
    value = var.cluster_name
  }
  set {
    name  = "region"
    value = var.region
  }
  set {
    name  = "vpcId"
    value = var.vpc_id
  }
  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }
}

# ExternalDNS to create Route53 records from Ingress/Service annotations.
resource "helm_release" "external_dns" {
  count      = var.domain_root != "" ? 1 : 0
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  namespace  = kubernetes_namespace.platform.metadata[0].name

  set {
    name  = "hostNetwork"
    value = "true"
  }
  set {
    name  = "dnsPolicy"
    value = "ClusterFirstWithHostNet"
  }

  # The AWS SDK needs a region. Some environments (including restricted student accounts)
  # don't populate it automatically.
  set {
    name  = "env[0].name"
    value = "AWS_REGION"
  }
  set {
    name  = "env[0].value"
    value = var.region
  }
  set {
    name  = "env[1].name"
    value = "AWS_DEFAULT_REGION"
  }
  set {
    name  = "env[1].value"
    value = var.region
  }

  set {
    name  = "provider"
    value = "aws"
  }
  set {
    name  = "policy"
    value = "upsert-only"
  }
  set {
    name  = "domainFilters[0]"
    value = var.domain_root
  }
  set {
    name  = "txtOwnerId"
    value = aws_route53_zone.this[0].zone_id
  }
  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  set {
    name  = "serviceAccount.name"
    value = "external-dns"
  }
}

