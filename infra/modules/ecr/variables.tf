variable "project" {
  type = string
}

variable "env" {
  type = string
}

variable "repositories" {
  type        = list(string)
  description = "Repository name suffixes (prefixed by project)."
}

variable "tags" {
  type    = map(string)
  default = {}
}

