locals {
  name = "${var.project}-${var.env}"
}

# Placeholder module: in follow-ups we will add Kubernetes resources for:
# - blue + green namespaces (or a single env namespace with color labels)
# - Deployments/Services for items/outfits/schedule/web for each color
# - Ingress that routes to the "active" color
# - A single Terraform variable to flip traffic (active_color = "blue"|"green")
#
# This lets you demo: deploy green -> flip traffic -> keep blue for rollback.

resource "kubernetes_namespace" "app" {
  metadata {
    name = var.env
    labels = {
      "app.kubernetes.io/part-of" = var.project
      "env"                       = var.env
    }
  }
}

