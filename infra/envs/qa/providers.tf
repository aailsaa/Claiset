provider "aws" {
  region = var.aws_region
}

# These are configured once the EKS cluster exists. During the very first apply,
# Terraform will create the cluster, then these providers will become usable in
# subsequent applies (or a single apply if your environment supports it).
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
  token                  = module.eks.cluster_auth_token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
    token                  = module.eks.cluster_auth_token
  }
}

