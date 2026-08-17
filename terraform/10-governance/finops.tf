locals {
  subscription_budgets = var.budget_start_date == null ? {} : var.subscription_ids
}

resource "azurerm_consumption_budget_subscription" "role" {
  for_each = local.subscription_budgets

  name            = "${var.prefix}-${replace(each.key, "_", "-")}-monthly-budget"
  subscription_id = "/subscriptions/${each.value}"
  amount          = lookup(var.monthly_budget_overrides, each.key, var.default_monthly_budget)
  time_grain      = "Monthly"

  time_period {
    start_date = var.budget_start_date
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThanOrEqualTo"
    threshold_type = "Actual"
    contact_emails = var.budget_contact_emails
    contact_roles  = ["Owner"]
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThanOrEqualTo"
    threshold_type = "Forecasted"
    contact_emails = var.budget_contact_emails
    contact_roles  = ["Owner"]
  }
}
