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
  description = "First entry is used in the launch template. Default t3.micro aligns with EC2 free-tier–eligible sizes for new accounts (see AWS terms). EKS control plane is still billed separately."
  default     = ["t3.micro"]
}

variable "node_group_desired_size" {
  type        = number
  description = "Managed node group desired capacity. Default 1 minimizes EC2 hours; raise if pods pending/OOM."
  default     = 1
}

variable "node_group_min_size" {
  type        = number
  description = "Managed node group minimum."
  default     = 1
}

variable "node_group_max_size" {
  type        = number
  description = "Managed node group maximum."
  default     = 2
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to resources."
  default     = {}
}

