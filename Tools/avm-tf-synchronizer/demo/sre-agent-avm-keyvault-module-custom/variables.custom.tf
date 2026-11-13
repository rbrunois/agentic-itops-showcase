variable "cost_center" {
  type        = string
  description = "Cost center the Key Vault is billed to. Applied as the mandatory `cost_center` tag."
  nullable    = false

  validation {
    condition     = length(trimspace(var.cost_center)) > 0
    error_message = "The cost_center must not be empty."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment. Possible values are `dev`, `test` and `prod`. Applied as the mandatory `environment` tag."
  nullable    = false

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "The environment must be one of `dev`, `test` or `prod`."
  }
}

variable "owner" {
  type        = string
  description = "Owner (team or contact) responsible for the Key Vault. Applied as the mandatory `owner` tag."
  nullable    = false

  validation {
    condition     = length(trimspace(var.owner)) > 0
    error_message = "The owner must not be empty."
  }
}
