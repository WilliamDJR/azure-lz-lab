resource "terraform_data" "configuration_validation" {
  lifecycle {
    precondition {
      condition = var.allow_shared_subscription_ids ? (
        length(distinct(values(var.subscription_ids))) == 1
        ) : (
        length(distinct(values(var.subscription_ids))) == length(values(var.subscription_ids))
      )
      error_message = "Use nine unique subscription IDs for multi-subscription mode, or set allow_shared_subscription_ids = true and use exactly one ID for every role."
    }
  }
}
