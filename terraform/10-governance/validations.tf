resource "terraform_data" "configuration_validation" {
  lifecycle {
    precondition {
      condition = (
        var.allow_shared_subscription_ids && !var.allow_logical_workload_subscription_ids &&
        length(distinct(values(var.subscription_ids))) == 1
        ) || (
        var.allow_logical_workload_subscription_ids && !var.allow_shared_subscription_ids &&
        length(distinct([
          var.subscription_ids.management,
          var.subscription_ids.connectivity,
          var.subscription_ids.identity,
          var.subscription_ids.security,
        ])) == 4 &&
        length(distinct([
          var.subscription_ids.corp_dev,
          var.subscription_ids.corp_prod,
          var.subscription_ids.online_dev,
          var.subscription_ids.online_prod,
          var.subscription_ids.sandbox,
        ])) == 1 &&
        !contains([
          var.subscription_ids.management,
          var.subscription_ids.connectivity,
          var.subscription_ids.identity,
          var.subscription_ids.security,
        ], var.subscription_ids.corp_dev)
        ) || (
        !var.allow_shared_subscription_ids && !var.allow_logical_workload_subscription_ids &&
        length(distinct(values(var.subscription_ids))) == length(values(var.subscription_ids))
      )
      error_message = "Choose exactly one profile: nine unique role IDs for multi-subscription mode; one ID for every role with allow_shared_subscription_ids; or four distinct platform IDs plus one distinct workload ID with allow_logical_workload_subscription_ids."
    }

    precondition {
      condition     = !var.allow_logical_workload_subscription_ids || !var.move_subscriptions_into_hierarchy || var.allow_protected_workload_policy_inheritance
      error_message = "Quota-limited mode keeps the existing workload subscription outside the management-group hierarchy by default. Set allow_protected_workload_policy_inheritance = true only after an owner-approved inventory and inheritance review."
    }
  }
}
