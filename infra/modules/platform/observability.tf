locals {
  # OAuth secret cannot participate in `for_each`/`count` conditionals without marking them sensitive-derived.
  observability_enabled = (
    var.enable_observability_stack &&
    trimspace(var.domain_root) != "" &&
    trimspace(var.grafana_google_client_id) != "" &&
    var.wait_for_acm_validation
  )
  grafana_host = local.observability_enabled ? "grafana-${var.env}.${var.domain_root}" : ""

  # Static for_each keys (see frontend cert in main.tf); ACM validation option values are unknown until apply.
  grafana_cert_validation_records_by_domain = local.observability_enabled ? {
    for dvo in aws_acm_certificate.grafana[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      values = [dvo.resource_record_value]
    }
  } : {}

  grafana_ini_google = merge(
    {
      enabled       = true
      allow_sign_up = true
      client_id     = var.grafana_google_client_id
      scopes        = "openid email profile"
      auth_url      = "https://accounts.google.com/o/oauth2/auth"
      token_url     = "https://accounts.google.com/o/oauth2/token"
      use_pkce      = true
    },
    trimspace(var.grafana_google_allowed_domains) != "" ? { allowed_domains = var.grafana_google_allowed_domains } : {}
  )

  alertmanager_enabled = trimspace(var.alertmanager_email_to) != "" && trimspace(var.alertmanager_smtp_smarthost) != ""

  alertmanager_smtp_global = merge(
    {
      smtp_smarthost   = var.alertmanager_smtp_smarthost
      smtp_from        = var.alertmanager_smtp_from != "" ? var.alertmanager_smtp_from : "alerts@${var.domain_root}"
      smtp_require_tls = true
    },
    trimspace(var.alertmanager_smtp_user) != "" ? {
      smtp_auth_username = var.alertmanager_smtp_user
    } : {}
  )
}

resource "kubernetes_namespace" "monitoring" {
  count = local.observability_enabled ? 1 : 0

  metadata {
    name = "monitoring"
    labels = {
      "app.kubernetes.io/part-of" = var.project
      "env"                       = var.env
    }
  }

  depends_on = [helm_release.aws_load_balancer_controller]
}

resource "kubernetes_secret" "grafana_google_oauth" {
  count = local.observability_enabled ? 1 : 0

  metadata {
    name      = "grafana-google-oauth"
    namespace = kubernetes_namespace.monitoring[0].metadata[0].name
  }

  # Provider base64-encodes Secret data; do not wrap in base64encode() or Grafana OAuth breaks.
  data = {
    secret = var.grafana_google_client_secret
  }

  type = "Opaque"

  depends_on = [kubernetes_namespace.monitoring]
}

resource "aws_acm_certificate" "grafana" {
  count = local.observability_enabled ? 1 : 0

  domain_name       = local.grafana_host
  validation_method = "DNS"
  tags              = merge(var.tags, { Name = "${local.name}-grafana" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "grafana_cert_validation" {
  for_each = local.observability_enabled ? toset([local.grafana_host]) : toset([])

  zone_id         = local.zone_id
  name            = local.grafana_cert_validation_records_by_domain[each.value].name
  type            = local.grafana_cert_validation_records_by_domain[each.value].type
  records         = local.grafana_cert_validation_records_by_domain[each.value].values
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "grafana" {
  count = local.observability_enabled ? 1 : 0

  certificate_arn         = aws_acm_certificate.grafana[0].arn
  validation_record_fqdns = [for r in aws_route53_record.grafana_cert_validation : r.fqdn]

  timeouts {
    create = "25m"
  }
}

resource "helm_release" "kube_prometheus_stack" {
  count = local.observability_enabled ? 1 : 0

  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "59.1.0"
  namespace  = kubernetes_namespace.monitoring[0].metadata[0].name

  # First installs on micro-node clusters can exceed 30m and frequently trigger Helm
  # timeout/uninstall loops with atomic=true. Let Terraform continue and rely on the
  # downstream readiness/smoke checks for convergence validation.
  timeout         = 5400
  wait            = false
  atomic          = false
  cleanup_on_fail = false
  replace         = true
  depends_on = [
    helm_release.aws_load_balancer_controller,
    aws_acm_certificate_validation.grafana,
    kubernetes_secret.grafana_google_oauth,
  ]

  values = [yamlencode({
    prometheus = {
      prometheusSpec = {
        scrapeInterval     = "60s"
        evaluationInterval = "60s"
        retention          = "5d"
        resources = {
          requests = { cpu = "200m", memory = "512Mi" }
        }
      }
    }

    kubeStateMetrics = { enabled = true }

    nodeExporter = { enabled = var.enable_observability_daemonsets }

    defaultRules = {
      create = true
      rules = {
        alertmanager            = local.alertmanager_enabled
        etcd                    = false
        kubeControllerManager   = false
        kubeSchedulerAlerting   = false
        kubernetesSystemKubelet = true
      }
    }

    # Starter custom alerts for grading/demo evidence.
    additionalPrometheusRulesMap = {
      claiset-custom = {
        groups = [
          {
            name = "claiset.custom.rules"
            rules = [
              {
                alert = "ClaisetBackendPodNotReady"
                expr  = "sum by (namespace) (kube_pod_status_ready{namespace=~\"dev|qa|uat|prod\",condition=\"false\",pod=~\"items-.*|outfits-.*|schedule-.*\"}) > 0"
                for   = "10m"
                labels = {
                  severity = "critical"
                  service  = "backend"
                }
                annotations = {
                  summary     = "One or more Claiset backend pods are NotReady"
                  description = "Backend pod readiness has been failing for at least 10 minutes in {{$labels.namespace}}."
                }
              }
            ]
          }
        ]
      }
    }

    # Keep a consistent object shape for `config` so Terraform's type checker
    # doesn't fail on conditional type mismatches.
    alertmanager = {
      enabled = local.alertmanager_enabled
      alertmanagerSpec = {
        resources = {
          requests = { cpu = "50m", memory = "128Mi" }
        }
      }
      config = {
        global = local.alertmanager_smtp_global
        route = {
          receiver        = "null"
          group_wait      = "30s"
          group_interval  = "5m"
          repeat_interval = "4h"
          # Only route critical alerts to email when alerting is enabled.
          routes = local.alertmanager_enabled ? [
            {
              receiver = "email"
              matchers = ["severity=\"critical\""]
            }
          ] : []
        }
        receivers = [
          { name = "null" },
          {
            name = "email"
            email_configs = [
              {
                to            = local.alertmanager_enabled ? var.alertmanager_email_to : ""
                send_resolved = true
              }
            ]
          }
        ]
      }
    }

    grafana = {
      enabled       = true
      adminPassword = "do-not-use-oauth-required"
      rbac          = { create = true }
      ingress = {
        enabled          = true
        ingressClassName = "alb"
        annotations = {
          "kubernetes.io/ingress.class"               = "alb"
          "alb.ingress.kubernetes.io/scheme"          = "internet-facing"
          "alb.ingress.kubernetes.io/target-type"     = "ip"
          "alb.ingress.kubernetes.io/listen-ports"    = "[{\"HTTP\":80},{\"HTTPS\":443}]"
          "alb.ingress.kubernetes.io/ssl-redirect"    = "443"
          "alb.ingress.kubernetes.io/certificate-arn" = aws_acm_certificate_validation.grafana[0].certificate_arn
          "external-dns.alpha.kubernetes.io/hostname" = local.grafana_host
        }
        hosts    = [local.grafana_host]
        path     = "/"
        pathType = "Prefix"
      }
      envValueFrom = {
        GF_AUTH_GOOGLE_CLIENT_SECRET = {
          secretKeyRef = {
            name = kubernetes_secret.grafana_google_oauth[0].metadata[0].name
            key  = "secret"
          }
        }
      }
      # kube-prometheus passes this into the Grafana subchart as grafana.ini
      "grafana.ini" = {
        server = {
          domain    = local.grafana_host
          root_url  = "https://${local.grafana_host}/"
          http_port = 3000
        }
        auth = {
          disable_login_form = true
        }
        "auth.anonymous" = {
          enabled = false
        }
        "auth.google" = local.grafana_ini_google
        users = {
          auto_assign_org      = true
          auto_assign_org_role = "Editor"
          viewers_can_edit     = false
        }
      }
      resources = {
        requests = { cpu = "100m", memory = "384Mi" }
      }
      additionalDataSources = [
        {
          name      = "Loki"
          type      = "loki"
          url       = "http://loki.monitoring.svc.cluster.local:3100"
          access    = "proxy"
          isDefault = false
        }
      ]
    }
  })]

  # Keep SMTP auth password out of the main Helm values/state where possible.
  dynamic "set_sensitive" {
    for_each = local.observability_enabled && local.alertmanager_enabled && trimspace(var.alertmanager_smtp_user) != "" && trimspace(var.alertmanager_smtp_password) != "" ? [1] : []
    content {
      name  = "alertmanager.config.global.smtp_auth_password"
      value = var.alertmanager_smtp_password
    }
  }
}

resource "helm_release" "loki" {
  count = local.observability_enabled ? 1 : 0

  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = "6.6.2"
  namespace  = kubernetes_namespace.monitoring[0].metadata[0].name

  depends_on = [helm_release.kube_prometheus_stack]

  # Loki can take a while to become Ready on first install on micro-node clusters.
  # Avoid long wait/rollback loops; readiness is validated by downstream smoke checks.
  timeout         = 2400
  wait            = false
  atomic          = false
  cleanup_on_fail = false
  replace         = true
  values = [yamlencode({
    deploymentMode = "SingleBinary"

    # For small/dev clusters, disable memcached caches (they can request huge memory).
    # This keeps Helm `wait=true` from timing out on Pending cache StatefulSets.
    chunksCache  = { enabled = false }
    resultsCache = { enabled = false }
    # Keep footprint small on free-tier node types.
    lokiCanary = { enabled = false }
    gateway    = { enabled = false }
    test       = { enabled = false }

    singleBinary = {
      replicas = 1
      # Loki (especially ruler/storage modules) expects a writable /var/loki.
      # Disabling persistence can leave /var/loki on a read-only filesystem in the chart's container.
      persistence = { enabled = false }
      # Chart has `readOnlyRootFilesystem: true`; mount writable storage at /var/loki.
      extraVolumes = [
        {
          name     = "loki-storage"
          emptyDir = {}
        }
      ]
      extraVolumeMounts = [
        {
          name      = "loki-storage"
          mountPath = "/var/loki"
        }
      ]
      resources = {
        requests = { cpu = "50m", memory = "384Mi" }
      }
    }

    # Chart defaults deploymentMode SimpleScalable (write/read/backend replicas); must zero them for SingleBinary.
    backend = { replicas = 0 }
    read    = { replicas = 0 }
    write   = { replicas = 0 }

    ingester       = { replicas = 0 }
    querier        = { replicas = 0 }
    queryFrontend  = { replicas = 0 }
    queryScheduler = { replicas = 0 }
    distributor    = { replicas = 0 }
    compactor      = { replicas = 0 }
    indexGateway   = { replicas = 0 }
    bloomCompactor = { replicas = 0 }
    bloomGateway   = { replicas = 0 }

    loki = {
      # Loki 6.x requires schemaConfig unless this test flag is set; matches ephemeral singleBinary + no PVC.
      useTestSchema = true
      auth_enabled  = false
      commonConfig = {
        replication_factor = 1
      }
      storage = {
        type = "filesystem"
      }
    }
  })]
}

resource "helm_release" "promtail" {
  count = local.observability_enabled && var.enable_observability_daemonsets ? 1 : 0

  name       = "promtail"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "promtail"
  version    = "6.15.5"
  namespace  = kubernetes_namespace.monitoring[0].metadata[0].name

  depends_on = [helm_release.loki]

  # DaemonSet readiness can flap while autoscaling nodes join; avoid blocking/rollback loops.
  timeout         = 1800
  wait            = false
  atomic          = false
  cleanup_on_fail = false
  replace         = true
  values = [yamlencode({
    resources = {
      requests = { cpu = "40m", memory = "96Mi" }
    }
    config = {
      clients = [
        { url = "http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push" }
      ]
    }
  })]
}
