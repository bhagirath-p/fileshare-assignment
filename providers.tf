variable "primary_region" {
  description = "Primary AWS region (e.g. eu-west-1)"
  type        = string
  default     = "eu-west-1"
}

variable "secondary_region" {
  description = "Secondary AWS region for DR (e.g. eu-central-1)"
  type        = string
  default     = "eu-central-1"
}

provider "aws" {
  alias  = "primary"
  region = var.primary_region
}

provider "aws" {
  alias  = "secondary"
  region = var.secondary_region
}

# Default (unaliased) provider is primary region
provider "aws" {
  region = var.primary_region
}

provider "aws" {
  alias      = "replica"
  region     = "eu-west-1"
}