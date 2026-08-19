locals {
  # Provider aliases become logical role boundaries when every alias points to
  # one subscription. Tag each taggable resource so Cost Analysis and Azure
  # Resource Graph can still separate the simulated platform responsibilities.
  role_tags = {
    management   = merge(var.tags, { "alz-role" = "management" })
    connectivity = merge(var.tags, { "alz-role" = "connectivity" })
    corp_dev     = merge(var.tags, { "alz-role" = "corp-dev" })
    security     = merge(var.tags, { "alz-role" = "security" })
    sandbox      = merge(var.tags, { "alz-role" = "sandbox" })
  }
}
