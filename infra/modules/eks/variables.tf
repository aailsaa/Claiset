variable "project" {
  type = string
}

variable "env" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "cluster_version" {
  type        = string
  description = "EKS Kubernetes version."
  default     = "1.31"
}

variable "create_iam_roles" {
  type        = bool
  description = "Whether to create EKS IAM roles (AWS Academy often denies iam:CreateRole)."
  default     = true
}

variable "cluster_role_arn" {
  type        = string
  description = "Existing IAM role ARN for the EKS control plane (required if create_iam_roles=false)."
  default     = ""
}

variable "node_role_arn" {
  type        = string
  description = "Existing IAM role ARN for the EKS node group (required if create_iam_roles=false)."
  default     = ""
}

variable "node_instance_types" {
  type        = list(string)
  description = "Node instance types."
  default     = ["t3.medium"]
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to resources."
  default     = {}
}

