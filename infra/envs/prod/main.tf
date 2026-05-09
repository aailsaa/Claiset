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

module "platform" {
  source            = "../../modules/platform"
  project           = var.project
  env               = var.env
  tags              = local.tags
  region            = var.aws_region
  cluster_name      = module.eks.cluster_name
  vpc_id            = module.network.vpc_id
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_issuer_url   = module.eks.oidc_issuer_url

  domain_root             = var.domain_root
  hosted_zone_id          = var.route53_hosted_zone_id
  frontend_subdomain      = var.frontend_subdomain
  wait_for_acm_validation = var.wait_for_acm_validation
  create_hosted_zone      = var.create_hosted_zone

  enable_observability_stack     = var.enable_observability_stack
  grafana_google_client_id       = var.grafana_google_client_id
  grafana_google_client_secret   = var.grafana_google_client_secret
  grafana_google_allowed_domains = var.grafana_google_allowed_domains
  alertmanager_email_to          = var.alertmanager_email_to
  alertmanager_smtp_smarthost    = var.alertmanager_smtp_smarthost
  alertmanager_smtp_from         = var.alertmanager_smtp_from
  alertmanager_smtp_user         = var.alertmanager_smtp_user
  alertmanager_smtp_password     = var.alertmanager_smtp_password
}

module "app_bluegreen" {
  source  = "../../modules/app-bluegreen"
  project = var.project
  env     = var.env
  tags    = local.tags

  enable_kubernetes_app = var.enable_kubernetes_app
  depends_on            = [module.platform]
  # Free-tier node constraints are tight; keep one replica per service in prod for deterministic scheduling.
  replicas              = 1

  aws_region               = var.aws_region
  domain_root              = var.domain_root
  frontend_subdomain       = var.frontend_subdomain
  frontend_certificate_arn = module.platform.frontend_certificate_arn
  google_client_id         = var.google_client_id

  database_url = "postgres://${module.rds.username}:${module.rds.password}@${module.rds.address}:${module.rds.port}/${module.rds.db_name}?sslmode=require"

  images = {
    items    = "${local.ecr_repository_urls.items}:prod"
    outfits  = "${local.ecr_repository_urls.outfits}:prod"
    schedule = "${local.ecr_repository_urls.schedule}:prod"
    web      = "${local.ecr_repository_urls.web}:prod"
    migrate  = "${local.ecr_repository_urls.migrate}:prod"
  }

  include_apex_and_www_in_external_dns = true
}

