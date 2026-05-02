locals {
  # Share one canonical set of repos across envs (prefix usually "claiset") while
  # module.project can differ for VPC/EKS naming (e.g. onlinecloset-dev-*).
  repository_name_prefix = coalesce(var.repository_name_prefix, var.project)
}

resource "aws_ecr_repository" "this" {
  for_each = toset(var.repositories)

  name                 = "${local.repository_name_prefix}-${each.value}"
  image_tag_mutability = "MUTABLE"
  # Required when Terraform replaces repos (e.g. onlinecloset-* → claiset-*): AWS
  # otherwise rejects DeleteRepository if any images remain.
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
}

