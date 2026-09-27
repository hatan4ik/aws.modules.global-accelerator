# Disposable prerequisite for the smoke suite: Global Accelerator needs at
# least one real endpoint to accept an endpoint group, and an unattached
# Elastic IP is the cheapest real endpoint available (a small hourly public
# IPv4 charge independent of this module, unrelated to Global Accelerator's
# own hourly charge). data.aws_region.current lets the suite key
# endpoint_groups by the exact region the fixture and the provider resolved
# to, rather than guessing or hard-coding one.

data "aws_region" "current" {}

locals {
  tags = merge(var.tags, {
    Name            = "${var.name_prefix}-endpoint"
    IntegrationTest = "aws.modules.global-accelerator"
    Disposable      = "true"
  })
}

resource "aws_eip" "endpoint" {
  domain = "vpc"

  tags = local.tags
}
