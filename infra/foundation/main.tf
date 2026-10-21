# Subscription-scoped on purpose: Databricks VMs and disks land in the workspace's *managed*
# resource group, so a budget on rg-capstone alone would miss most of the compute spend.
data "azurerm_subscription" "current" {}

resource "azurerm_consumption_budget_subscription" "this" {
  for_each = var.budgets_usd

  name            = "budget-capstone-${each.key}"
  subscription_id = data.azurerm_subscription.current.id
  amount          = each.value
  time_grain      = "Monthly"

  time_period {
    start_date = var.budget_start_date
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThanOrEqualTo"
    threshold_type = "Actual"
    contact_emails = [var.alert_email]
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThanOrEqualTo"
    threshold_type = "Forecasted"
    contact_emails = [var.alert_email]
  }
}
