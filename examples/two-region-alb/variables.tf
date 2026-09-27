variable "region" {
  description = "AWS region the accelerator's control-plane resources are created in. Global Accelerator itself is a global service."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name of the accelerator."
  type        = string
  default     = "public-api"
}

variable "flow_logs_bucket_name" {
  description = "Name of an existing S3 bucket the caller owns to receive flow logs. null leaves flow logs off."
  type        = string
  default     = null
}

# In a real composition these two ARNs come from two aws.modules.alb calls,
# one per region, for example:
#
#   module "alb_us_east_1" {
#     source    = "git::https://github.com/hatan4ik/aws.modules.alb.git?ref=<commit-sha>"
#     providers = { aws = aws.us_east_1 }
#     # ...
#   }
#
#   module "alb_eu_west_1" {
#     source    = "git::https://github.com/hatan4ik/aws.modules.alb.git?ref=<commit-sha>"
#     providers = { aws = aws.eu_west_1 }
#     # ...
#   }
#
# and this example's endpoint_id values would be module.alb_us_east_1.arn and
# module.alb_eu_west_1.arn. This module never calls aws.modules.alb itself —
# see docs/DESIGN.md for why — so the example takes the ARNs as plain strings
# to keep the composition visible without a live dependency.
variable "us_east_1_alb_arn" {
  description = "ARN of the regional public ALB in us-east-1 (what aws.modules.alb's arn output would provide)."
  type        = string
}

variable "eu_west_1_alb_arn" {
  description = "ARN of the regional public ALB in eu-west-1 (what aws.modules.alb's arn output would provide)."
  type        = string
}
