variable "subscription_id" {
  description = "Azure subscription ID (dedicated to this project)."
  type        = string
}

variable "alert_email" {
  description = "Where budget alerts go."
  type        = string
}

variable "budget_start_date" {
  description = "First day of the first budget month, RFC3339, e.g. 2026-11-01T00:00:00Z."
  type        = string
}

variable "budgets_usd" {
  description = "Monthly subscription budgets. warn = look closer; stop = stop and investigate."
  type        = map(number)
  default = {
    warn = 50
    stop = 100
  }
}
