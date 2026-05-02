locals {
  tags = {
    Project = var.project
    Env     = var.env
  }
}

data "aws_caller_identity" "current" {}

locals {
  ecr_suffixes = ["items", "outfits", "schedule", "web", "migrate"]
  ecr_repository_urls = {
    for s in local.ecr_suffixes :
    s => "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.ecr_repository_prefix}-${s}"
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

  create_iam_roles = false
  cluster_role_arn = "arn:aws:iam::973087143131:role/LabRole"
  node_role_arn    = "arn:aws:iam::973087143131:role/LabRole"
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

module "platform" {
  source       = "../../modules/platform"
  project      = var.project
  env          = var.env
  tags         = local.tags
  region       = var.aws_region
  cluster_name = module.eks.cluster_name
  vpc_id       = module.network.vpc_id

  domain_root                = var.domain_root
  hosted_zone_id             = var.route53_hosted_zone_id
  frontend_subdomain         = var.frontend_subdomain
  wait_for_acm_validation    = var.wait_for_acm_validation
  create_hosted_zone         = var.create_hosted_zone
}

module "app_bluegreen" {
  source  = "../../modules/app-bluegreen"
  project = var.project
  env     = var.env
  tags    = local.tags

  aws_region               = var.aws_region
  domain_root              = var.domain_root
  frontend_subdomain       = var.frontend_subdomain
  frontend_certificate_arn = module.platform.frontend_certificate_arn
  google_client_id         = var.google_client_id

  database_url = "postgres://${module.rds.username}:${module.rds.password}@${module.rds.address}:${module.rds.port}/${module.rds.db_name}?sslmode=require"

  images = {
    items    = "${local.ecr_repository_urls.items}:uat"
    outfits  = "${local.ecr_repository_urls.outfits}:uat"
    schedule = "${local.ecr_repository_urls.schedule}:uat"
    web      = "${local.ecr_repository_urls.web}:uat"
    migrate  = "${local.ecr_repository_urls.migrate}:uat"
  }
}

