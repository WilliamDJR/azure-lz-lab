locals {
  # A single-subscription learning track must create one budget, not nine
  # conflicting budgets. Preserve role keys in multi-subscription mode so an
  # existing Terraform state does not see every budget address change.
  subscription_budgets = var.budget_start_date == null ? {} : (
    var.allow_shared_subscription_ids
    ? { shared = var.subscription_ids.management }
    : var.allow_logical_workload_subscription_ids
    ? {
      management   = var.subscription_ids.management
      connectivity = var.subscription_ids.connectivity
      identity     = var.subscription_ids.identity
      security     = var.subscription_ids.security
      workload     = var.subscription_ids.corp_dev
    }
    : var.subscription_ids
  )
}

resource "azurerm_consumption_budget_subscription" "role" {
  for_each = local.subscription_budgets

  name            = "${var.prefix}-${replace(each.key, "_", "-")}-monthly-budget"
  subscription_id = "/subscriptions/${each.value}"
  # The shared subscription hosts the management function, so its one budget
  # deliberately uses the management override. No role is selected implicitly
  # from map ordering.
  amount = var.allow_shared_subscription_ids ? (
    lookup(var.monthly_budget_overrides, "management", var.default_monthly_budget)
    ) : (
    lookup(var.monthly_budget_overrides, each.key, lookup(var.monthly_budget_overrides, each.key == "workload" ? "corp_dev" : each.key, var.default_monthly_budget))
  )
  time_grain = "Monthly"

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
