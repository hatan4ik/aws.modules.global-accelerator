variable "region" {
  description = "AWS region the accelerator's control-plane resources are created in, and the region the weighted endpoint group is created in."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name of the accelerator."
  type        = string
  default     = "canary-example"
}

variable "stable_alb_arn" {
  description = "ARN of the ALB serving the stable release."
  type        = string
}

variable "canary_alb_arn" {
  description = "ARN of the ALB serving the canary release."
  type        = string
}

variable "canary_weight" {
  description = "Weight given to the canary endpoint, 0-255. The stable endpoint receives the remainder of the traffic split proportionally: with a canary weight of 26 against a stable weight of 230, roughly 10% of the group's traffic reaches the canary. Weight is relative within the group, not a percentage."
  type        = number
  default     = 26

  validation {
    condition     = var.canary_weight >= 0 && var.canary_weight <= 255
    error_message = "canary_weight must be between 0 and 255, the Global Accelerator bound."
  }
}
