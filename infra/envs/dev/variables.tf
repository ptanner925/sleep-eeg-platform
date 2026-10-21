variable "subscription_id" {
  description = "Azure subscription ID (dedicated to this project)."
  type        = string
}

variable "location" {
  description = "Azure region for every resource; East US 2 is where the vCPU quota was requested."
  type        = string
  default     = "eastus2"
}

variable "prefix" {
  description = "Short name used in every resource name."
  type        = string
  default     = "capstone"
}

variable "owner" {
  description = "Value of the owner tag on every resource."
  type        = string
  default     = "paul"
}
