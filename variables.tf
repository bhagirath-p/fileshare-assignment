variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "fileshare"
}

variable "tags" {
  description = "Tags applied to resources"
  type        = map(string)
  default     = {
    Project = "FileShare"
    Env     = "dev"
  }
}

variable "lambda_runtime" {
  type    = string
  default = "python3.11"
}

variable "lambda_timeout" {
  type    = number
  default = 30
}
