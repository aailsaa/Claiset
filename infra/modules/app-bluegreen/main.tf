locals {
  name          = "${var.project}-${var.env}"
  frontend_host = var.domain_root != "" ? "${var.frontend_subdomain}.${var.domain_root}" : ""
  apex_host     = var.domain_root
  www_host      = var.domain_root != "" ? "www.${var.domain_root}" : ""
  # Keep count decisions based only on root input variables, not on values computed from
  # other modules during the same plan (e.g. RDS address/password, ACM ARN). Those can be
  # unknown at plan time and would make count invalid.
  enabled = var.enable_kubernetes_app
}

# Private ECR pulls from cluster nodes rely on IAM. AWS Academy LabRole often lacks AmazonECR*;
# an imagePullSecret from GetAuthorizationToken still works for terraform-driven deploys (token ~12h).
data "aws_caller_identity" "current" {
  count = local.enabled ? 1 : 0
}

data "aws_ecr_authorization_token" "pull" {
  count = local.enabled ? 1 : 0
}

locals {
  ecr_pull_host = local.enabled ? "${data.aws_caller_identity.current[0].account_id}.dkr.ecr.${var.aws_region}.amazonaws.com" : ""

  dockerconfigjson_payload = local.enabled ? jsonencode({
    auths = {
      (local.ecr_pull_host) = {
        auth = base64encode("AWS:${data.aws_ecr_authorization_token.pull[0].password}")
      }
    }
  }) : "{}"
}

resource "kubernetes_namespace" "app" {
  metadata {
    name = var.env
    labels = {
      "app.kubernetes.io/part-of" = var.project
      "env"                       = var.env
    }
  }
}

resource "kubernetes_secret" "ecr_pull" {
  count = local.enabled ? 1 : 0

  metadata {
    name      = "ecr-pull"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  type = "kubernetes.io/dockerconfigjson"

  # Plain JSON here: the provider base64-encodes `data` values for the Kubernetes API.
  # Wrapping with base64encode() would double-encode; the API then decodes once and
  # dockerconfigjson validation sees base64 text instead of JSON (invalid character 'e'...).
  data = {
    ".dockerconfigjson" = local.dockerconfigjson_payload
  }
}

resource "kubernetes_secret" "app_env" {
  count = local.enabled ? 1 : 0

  metadata {
    name      = "${var.project}-env"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  # Plain strings: the provider encodes Secret `data` for the API (do not base64encode here).
  data = {
    DATABASE_URL     = var.database_url
    GOOGLE_CLIENT_ID = var.google_client_id
  }
}

resource "kubernetes_job" "migrate" {
  count = local.enabled ? 1 : 0

  metadata {
    name      = "migrate"
    namespace = kubernetes_namespace.app.metadata[0].name
    labels    = { app = "migrate" }
  }

  spec {
    backoff_limit = 3
    template {
      metadata { labels = { app = "migrate" } }
      spec {
        restart_policy = "OnFailure"
        image_pull_secrets { name = kubernetes_secret.ecr_pull[0].metadata[0].name }
        container {
          name              = "migrate"
          image             = var.images.migrate
          image_pull_policy = "Always"

          env_from {
            secret_ref {
              name = kubernetes_secret.app_env[0].metadata[0].name
            }
          }
        }
      }
    }
  }

  timeouts {
    create = "20m"
    update = "20m"
  }

  depends_on = [
    kubernetes_secret.app_env,
    kubernetes_secret.ecr_pull,
  ]
}

resource "kubernetes_deployment" "items" {
  count = local.enabled ? 1 : 0

  metadata {
    name      = "items"
    namespace = kubernetes_namespace.app.metadata[0].name
    labels    = { app = "items" }
  }

  spec {
    replicas = 2
    selector {
      match_labels = { app = "items" }
    }
    template {
      metadata {
        labels = { app = "items" }
      }
      spec {
        image_pull_secrets {
          name = kubernetes_secret.ecr_pull[0].metadata[0].name
        }

        container {
          name              = "items"
          image             = var.images.items
          image_pull_policy = "Always"

          env_from {
            secret_ref {
              name = kubernetes_secret.app_env[0].metadata[0].name
            }
          }

          port { container_port = 8081 }

          readiness_probe {
            http_get {
              path = "/health"
              port = 8081
            }
            initial_delay_seconds = 3
            period_seconds        = 5
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8081
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }
        }
      }
    }
  }

  timeouts {
    create = "35m"
    update = "35m"
  }

  depends_on = [kubernetes_job.migrate]
}

resource "kubernetes_service" "items" {
  count = local.enabled ? 1 : 0

  metadata {
    name      = "items"
    namespace = kubernetes_namespace.app.metadata[0].name
    labels    = { app = "items" }
  }

  spec {
    selector = { app = "items" }
    port {
      name        = "http"
      port        = 80
      target_port = 8081
    }
    type = "ClusterIP"
  }
}

resource "kubernetes_deployment" "outfits" {
  count = local.enabled ? 1 : 0

  metadata {
    name      = "outfits"
    namespace = kubernetes_namespace.app.metadata[0].name
    labels    = { app = "outfits" }
  }

  spec {
    replicas = 2
    selector { match_labels = { app = "outfits" } }
    template {
      metadata { labels = { app = "outfits" } }
      spec {
        image_pull_secrets {
          name = kubernetes_secret.ecr_pull[0].metadata[0].name
        }

        container {
          name              = "outfits"
          image             = var.images.outfits
          image_pull_policy = "Always"

          env_from {
            secret_ref {
              name = kubernetes_secret.app_env[0].metadata[0].name
            }
          }

          port { container_port = 8082 }

          readiness_probe {
            http_get {
              path = "/health"
              port = 8082
            }
            initial_delay_seconds = 3
            period_seconds        = 5
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8082
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }
        }
      }
    }
  }

  timeouts {
    create = "35m"
    update = "35m"
  }

  depends_on = [kubernetes_job.migrate]
}

resource "kubernetes_service" "outfits" {
  count = local.enabled ? 1 : 0

  metadata {
    name      = "outfits"
    namespace = kubernetes_namespace.app.metadata[0].name
    labels    = { app = "outfits" }
  }

  spec {
    selector = { app = "outfits" }
    port {
      name        = "http"
      port        = 80
      target_port = 8082
    }
    type = "ClusterIP"
  }
}

resource "kubernetes_deployment" "schedule" {
  count = local.enabled ? 1 : 0

  metadata {
    name      = "schedule"
    namespace = kubernetes_namespace.app.metadata[0].name
    labels    = { app = "schedule" }
  }

  spec {
    replicas = 2
    selector { match_labels = { app = "schedule" } }
    template {
      metadata { labels = { app = "schedule" } }
      spec {
        image_pull_secrets {
          name = kubernetes_secret.ecr_pull[0].metadata[0].name
        }

        container {
          name              = "schedule"
          image             = var.images.schedule
          image_pull_policy = "Always"

          env_from {
            secret_ref {
              name = kubernetes_secret.app_env[0].metadata[0].name
            }
          }

          port { container_port = 8083 }

          readiness_probe {
            http_get {
              path = "/health"
              port = 8083
            }
            initial_delay_seconds = 3
            period_seconds        = 5
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8083
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }
        }
      }
    }
  }

  timeouts {
    create = "35m"
    update = "35m"
  }

  depends_on = [kubernetes_job.migrate]
}

resource "kubernetes_service" "schedule" {
  count = local.enabled ? 1 : 0

  metadata {
    name      = "schedule"
    namespace = kubernetes_namespace.app.metadata[0].name
    labels    = { app = "schedule" }
  }

  spec {
    selector = { app = "schedule" }
    port {
      name        = "http"
      port        = 80
      target_port = 8083
    }
    type = "ClusterIP"
  }
}

resource "kubernetes_deployment" "web" {
  count = local.enabled ? 1 : 0

  metadata {
    name      = "web"
    namespace = kubernetes_namespace.app.metadata[0].name
    labels    = { app = "web" }
  }

  spec {
    replicas = 2
    selector { match_labels = { app = "web" } }
    template {
      metadata { labels = { app = "web" } }
      spec {
        image_pull_secrets {
          name = kubernetes_secret.ecr_pull[0].metadata[0].name
        }

        container {
          name              = "web"
          image             = var.images.web
          image_pull_policy = "Always"

          port { container_port = 80 }

          readiness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 3
            period_seconds        = 5
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }
        }
      }
    }
  }

  timeouts {
    create = "35m"
    update = "35m"
  }

  depends_on = [kubernetes_job.migrate]
}

resource "kubernetes_service" "web" {
  count = local.enabled ? 1 : 0

  metadata {
    name      = "web"
    namespace = kubernetes_namespace.app.metadata[0].name
    labels    = { app = "web" }
  }

  spec {
    selector = { app = "web" }
    port {
      name        = "http"
      port        = 80
      target_port = 80
    }
    type = "ClusterIP"
  }
}

resource "kubernetes_ingress_v1" "app" {
  count = local.enabled ? 1 : 0

  metadata {
    name      = var.project
    namespace = kubernetes_namespace.app.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"               = "alb"
      "alb.ingress.kubernetes.io/scheme"          = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"     = "ip"
      "alb.ingress.kubernetes.io/listen-ports"    = "[{\"HTTP\":80},{\"HTTPS\":443}]"
      "alb.ingress.kubernetes.io/ssl-redirect"    = "443"
      "alb.ingress.kubernetes.io/certificate-arn" = var.frontend_certificate_arn
      "external-dns.alpha.kubernetes.io/hostname" = "${local.frontend_host},${local.apex_host},${local.www_host}"

      # Redirect apex/www → canonical frontend host (https://app.<domain>/)
      "alb.ingress.kubernetes.io/actions.redirect-to-frontend" = jsonencode({
        Type = "redirect"
        RedirectConfig = {
          Protocol   = "HTTPS"
          Port       = "443"
          Host       = local.frontend_host
          Path       = "/#{path}"
          Query      = "#{query}"
          StatusCode = "HTTP_301"
        }
      })
    }
  }

  spec {
    ingress_class_name = "alb"
    rule {
      host = local.frontend_host
      http {
        path {
          path      = "/api/v1/items"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.items[0].metadata[0].name
              port { number = 80 }
            }
          }
        }
        path {
          path      = "/api/v1/outfits"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.outfits[0].metadata[0].name
              port { number = 80 }
            }
          }
        }
        path {
          path      = "/api/v1/assignments"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.schedule[0].metadata[0].name
              port { number = 80 }
            }
          }
        }
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.web[0].metadata[0].name
              port { number = 80 }
            }
          }
        }
      }
    }

    # Redirect bare domain (https://claiset.xyz/*) to canonical frontend host.
    rule {
      host = local.apex_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "redirect-to-frontend"
              port { name = "use-annotation" }
            }
          }
        }
      }
    }

    # Redirect www (https://www.claiset.xyz/*) to canonical frontend host.
    rule {
      host = local.www_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "redirect-to-frontend"
              port { name = "use-annotation" }
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_service.web]
}

