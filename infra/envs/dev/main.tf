locals {
  tags = {
    Project = var.project
    Env     = var.env
  }
}

module "network" {
  source  = "../../modules/network"
  project = var.project
  env     = var.env
  region  = var.aws_region
  tags    = local.tags
}

module "eks" {
  source          = "../../modules/eks"
  project         = var.project
  env             = var.env
  region          = var.aws_region
  vpc_id          = module.network.vpc_id
  subnet_ids      = module.network.private_subnet_ids
  cluster_version = var.eks_cluster_version
  tags            = local.tags

  # IAM user / own account: Terraform creates cluster + node IAM roles.
  # AWS Academy (LabRole): set create_iam_roles=false and set cluster_role_arn / node_role_arn.
  create_iam_roles = true

  node_instance_types     = var.node_instance_types
  node_group_desired_size = var.node_group_desired_size
  node_group_min_size     = var.node_group_min_size
  node_group_max_size     = var.node_group_max_size
}

module "rds" {
  source             = "../../modules/rds"
  project            = var.project
  env                = var.env
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
  eks_node_sg_id     = module.eks.node_security_group_id
  tags               = local.tags
}

module "ecr" {
  source  = "../../modules/ecr"
  project = var.project
  env     = var.env
  tags    = local.tags

  repository_name_prefix = var.ecr_repository_prefix
  repositories           = ["items", "outfits", "schedule", "web", "migrate"]
}

# Cluster add-ons that the rubric expects (Ingress/ALB, DNS, certs, monitoring/logging)
# will live here, installed via Terraform (helm_release / kubernetes_manifest).
module "platform" {
  source       = "../../modules/platform"
  project      = var.project
  env          = var.env
  tags         = local.tags
  region       = var.aws_region
  cluster_name = module.eks.cluster_name
  vpc_id       = module.network.vpc_id

  # Domain wiring is scaffolded but optional until you create a domain.
  domain_root             = var.domain_root
  hosted_zone_id          = var.route53_hosted_zone_id
  frontend_subdomain      = var.frontend_subdomain
  wait_for_acm_validation = var.wait_for_acm_validation
  create_hosted_zone      = var.create_hosted_zone
}

# Blue/Green deployment scaffolding (two stacks + traffic switch) will live here.
module "app_bluegreen" {
  source  = "../../modules/app-bluegreen"
  project = var.project
  env     = var.env
  tags    = local.tags

  enable_kubernetes_app = var.enable_kubernetes_app
  depends_on            = [module.platform]
  replicas              = 1

  # Will be used for Ingress hostnames once domain is configured.
  aws_region               = var.aws_region
  domain_root              = var.domain_root
  frontend_subdomain       = var.frontend_subdomain
  frontend_certificate_arn = module.platform.frontend_certificate_arn
  google_client_id         = var.google_client_id

  database_url = "postgres://${module.rds.username}:${module.rds.password}@${module.rds.address}:${module.rds.port}/${module.rds.db_name}?sslmode=require"

  images = {
    items    = "${module.ecr.repository_urls.items}:dev"
    outfits  = "${module.ecr.repository_urls.outfits}:dev"
    schedule = "${module.ecr.repository_urls.schedule}:dev"
    web      = "${module.ecr.repository_urls.web}:dev"
    migrate  = "${module.ecr.repository_urls.migrate}:dev"
  }
}

