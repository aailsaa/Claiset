# Unmanage duplicate ECR module from this workspace without destroying AWS repos.
# Requires Terraform >= 1.7. If qa state never contained module.ecr, delete this file.
removed {
  from = module.ecr
  lifecycle {
    destroy = false
  }
}
