variable "aws_region" {
  type        = string
  description = "AWS region for Terraform state resources."
  default     = "us-east-1"
}

variable "state_bucket_name" {
  type        = string
  description = "Globally unique S3 bucket name to store Terraform state."
}

variable "lock_table_name" {
  type        = string
  description = "DynamoDB table name to use for Terraform state locking."
  default     = "claiset-tf-locks"
}

