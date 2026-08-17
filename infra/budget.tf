# Tracks spend for just this project, filtered by the Project=brand tag that
# every resource here already carries and that's already an active cost
# allocation tag on the account. No notification block — matches the
# no-alerts stance in monitoring.tf; this is for glancing at the Budgets
# console, not for paging anyone.
#
# limit_amount only drives the progress-bar percentage shown in the console
# since there's no notification tied to it. $5/month is a generous ceiling
# for a low-traffic image CDN — actual spend should be cents.
resource "aws_budgets_budget" "brand" {
  name         = "${local.name_prefix}-monthly"
  budget_type  = "COST"
  limit_amount = "5"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name = "TagKeyValue"
    # format() avoids the $${...} literal-dollar escaping trap: writing the $
    # directly adjacent to an interpolation reads as Terraform's "literal ${"
    # escape sequence and would emit "Project${var.project_name}" verbatim.
    values = [format("user:Project$%s", var.project_name)]
  }

  tags = local.common_tags
}
