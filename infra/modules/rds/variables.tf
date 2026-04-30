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
  type    = string
  default = "db.t4g.micro"
}

variable "allocated_storage_gb" {
  type    = number
  default = 20
}

variable "max_allocated_storage_gb" {
  type    = number
  default = 100
}

variable "db_name" {
  type    = string
  default = "onlinecloset"
}

variable "db_username" {
  type    = string
  default = "closet"
}

variable "tags" {
  type    = map(string)
  default = {}
}

