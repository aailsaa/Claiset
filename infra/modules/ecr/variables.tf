variable "project" {
  type = string
}

variable "env" {
  type = string
}

variable "repository_name_prefix" {
  type        = string
  default     = null
  nullable    = true
  description = "Prefix for repo names (e.g. claiset-items). Defaults to project when null."
}

variable "repositories" {
  type        = list(string)
  description = "Repository name suffixes (prefixed by repository_name_prefix or project)."
}

variable "tags" {
  type    = map(string)
  default = {}
}

