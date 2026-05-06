variable "project" {
  type = string
}

variable "env" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "eks_node_sg_id" {
  type        = string
  description = "Security group ID for EKS nodes; allowed to connect to Postgres."
}

variable "postgres_version" {
  type    = string
  default = "16"
}

variable "instance_class" {
  type        = string
  default     = "db.t3.micro"
  description = "Default db.t3.micro is a micro class often covered under RDS free tier for new accounts (confirm for your account/region)."
}

variable "allocated_storage_gb" {
  type    = number
  default = 20
}

variable "max_allocated_storage_gb" {
  type        = number
  default     = 30
  description = "Autoscale cap for gp storage; lower default to limit surprise bills."
}

variable "db_name" {
  type    = string
  default = "claiset"
}

variable "db_username" {
  type    = string
  default = "closet"
}

variable "tags" {
  type    = map(string)
  default = {}
}

