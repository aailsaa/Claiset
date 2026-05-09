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

variable "node_group_kubernetes_version" {
  type        = string
  default     = null
  nullable    = true
  description = <<-EOT
    If set, pins the managed node group's Kubernetes version and Terraform will upgrade
    worker kubelet when this changes. Leave null (recommended) so the node group is created
    aligned with the cluster and launch-template-only updates do not call UpdateNodegroupVersion
    with a Kubernetes version change in the same request (AWS can return
    InvalidParameterException: "You must continue to not specify an instance type within the launch template").
    After a control plane upgrade, upgrade workers with a follow-up apply setting this to the new
    version, or use: aws eks update-nodegroup-version --cluster-name ... --nodegroup-name ...
  EOT
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
  description = "Instance types for the managed node group (not the EC2 launch template). EKS requires these here when the launch template omits InstanceType. Default t3.micro aligns with free-tier–eligible sizes where applicable."
  default     = ["t3.micro"]

  validation {
    condition     = length(var.node_instance_types) > 0 && length([for t in var.node_instance_types : t if trimspace(t) != ""]) == length(var.node_instance_types)
    error_message = "node_instance_types must be a non-empty list of non-blank instance type names."
  }
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

