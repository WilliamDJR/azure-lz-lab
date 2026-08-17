resource "terraform_data" "configuration_validation" {
  lifecycle {
    precondition {
      condition     = !var.enable_simulated_onprem || var.enable_vpn_gateway
      error_message = "enable_simulated_onprem requires enable_vpn_gateway = true."
    }

    precondition {
      condition     = !var.enable_simulated_onprem || var.vpn_shared_key != null
      error_message = "Set vpn_shared_key locally before enabling the simulated on-premises connection."
    }
  }
}
