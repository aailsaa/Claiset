variable "project" {
  type = string
}

variable "env" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR for the VPC."
  default     = "10.60.0.0/16"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to resources."
  default     = {}
}

