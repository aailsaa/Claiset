locals {
  name = "${var.project}-${var.env}"
  # Prefer explicit ID (avoids ambiguity when duplicate zones exist for the same domain).
  create_new_zone     = var.domain_root != "" && var.hosted_zone_id == "" && var.create_hosted_zone
  lookup_zone_by_name = var.domain_root != "" && var.hosted_zone_id == "" && !var.create_hosted_zone
}

data "aws_route53_zone" "by_id" {
  count   = var.hosted_zone_id != "" ? 1 : 0
  zone_id = var.hosted_zone_id
}

data "aws_route53_zone" "lookup" {
  count = local.lookup_zone_by_name ? 1 : 0

  name         = var.domain_root
  private_zone = false
}

# Only when explicitly requested — otherwise we reuse hosted_zone_id or lookup by domain_root.
resource "aws_route53_zone" "this" {
  count         = local.create_new_zone ? 1 : 0
  name          = var.domain_root
  force_destroy = true
  tags          = var.tags
}

locals {
  # coalesce avoids referencing lookup[0] when that data source has count = 0.
  zone_id = var.domain_root == "" ? null : coalesce(
    var.hosted_zone_id != "" ? var.hosted_zone_id : null,
    length(aws_route53_zone.this) > 0 ? aws_route53_zone.this[0].zone_id : null,
    length(data.aws_route53_zone.lookup) > 0 ? data.aws_route53_zone.lookup[0].zone_id : null,
  )
}

# ACM certificate for the frontend hostname (DNS validated in Route53).
#
# If aws_acm_certificate_validation hangs for many minutes, ACM cannot see the
# validation CNAME publicly. Typical causes: duplicate Route53 zones (records go
# into the wrong zone_id), or your registrar still points at different nameservers
# than the hosted zone in `route53_hosted_zone_id`. Fix public NS/DNS, then re-apply.
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
  count = var.domain_root != "" && var.wait_for_acm_validation ? 1 : 0

  certificate_arn         = aws_acm_certificate.frontend[0].arn
  validation_record_fqdns = [for r in aws_route53_record.frontend_cert_validation : r.fqdn]

  timeouts {
    create = "25m"
  }
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
#
# Recovery: "cannot re-use a name that is still in use" → a failed prior release.
#   helm uninstall aws-load-balancer-controller -n kube-system
# or import: terraform import 'module.platform.helm_release.aws_load_balancer_controller' 'kube-system/aws-load-balancer-controller'
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  timeout         = 1800
  atomic          = true
  cleanup_on_fail = true
  replace         = true

  # With hostNetwork enabled this chart binds fixed host ports; running >1 replica can
  # fail to schedule on small node groups ("didn't have free ports"). One replica is
  # enough for this project and keeps costs low.
  set {
    name  = "replicaCount"
    value = "1"
  }

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

  depends_on = [helm_release.aws_load_balancer_controller]

  # 30m: CI sometimes waits on new nodes + image pull; 20m flakes with atomic=true.
  timeout         = 1800
  atomic          = true
  cleanup_on_fail = true
  replace         = true

  set {
    name  = "replicaCount"
    value = "1"
  }

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
    value = local.zone_id
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

# Cluster Autoscaler (scales managed nodegroup up/down automatically).
# This prevents "Too many pods" hangs on tiny nodes by adding capacity only when required.
locals {
  enable_cluster_autoscaler = var.oidc_provider_arn != "" && var.oidc_issuer_url != ""
}

data "aws_iam_policy_document" "cluster_autoscaler_assume" {
  count = local.enable_cluster_autoscaler ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:cluster-autoscaler"]
    }
  }
}

resource "aws_iam_role" "cluster_autoscaler" {
  count              = local.enable_cluster_autoscaler ? 1 : 0
  name               = "${local.name}-cluster-autoscaler"
  assume_role_policy = data.aws_iam_policy_document.cluster_autoscaler_assume[0].json
  tags               = var.tags
}

data "aws_iam_policy_document" "cluster_autoscaler" {
  count = local.enable_cluster_autoscaler ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeTags",
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "ec2:DescribeLaunchTemplateVersions",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "cluster_autoscaler" {
  count  = local.enable_cluster_autoscaler ? 1 : 0
  name   = "${local.name}-cluster-autoscaler"
  role   = aws_iam_role.cluster_autoscaler[0].id
  policy = data.aws_iam_policy_document.cluster_autoscaler[0].json
}

resource "helm_release" "cluster_autoscaler" {
  count      = local.enable_cluster_autoscaler ? 1 : 0
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"

  timeout         = 1200
  atomic          = true
  cleanup_on_fail = true
  replace         = true

  set {
    name  = "autoDiscovery.clusterName"
    value = var.cluster_name
  }
  set {
    name  = "awsRegion"
    value = var.region
  }

  # Cost-efficient defaults: scale down when idle, but not so fast that rollouts lose pod slots.
  set {
    name  = "extraArgs.balance-similar-node-groups"
    value = "true"
  }
  set {
    name  = "extraArgs.scale-down-enabled"
    value = "true"
  }
  set {
    name  = "extraArgs.scale-down-unneeded-time"
    value = "10m"
  }
  set {
    name  = "extraArgs.scale-down-delay-after-add"
    value = "10m"
  }

  set {
    name  = "rbac.serviceAccount.create"
    value = "true"
  }
  set {
    name  = "rbac.serviceAccount.name"
    value = "cluster-autoscaler"
  }
  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.cluster_autoscaler[0].arn
  }
}

