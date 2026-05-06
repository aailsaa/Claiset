variable "aws_region" {
  type        = string
  description = "AWS region for Terraform state resources."
  default     = "us-east-1"
}

variable "state_bucket_name" {
  type        = string
  description = "Optional override. If empty, bootstrap will auto-generate a globally-unique S3 bucket name for Terraform state."
  default     = ""
}

variable "lock_table_name" {
  type        = string
  description = "DynamoDB table name to use for Terraform state locking."
  default     = ""
}

