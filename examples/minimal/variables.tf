variable "region" {
  description = "AWS region the accelerator's control-plane resources are created in. Global Accelerator itself is a global service; this is where the Terraform provider operates."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name of the accelerator."
  type        = string
  default     = "minimal-example"
}

variable "endpoint_id" {
  description = "ALB/NLB ARN (in region), Elastic IP allocation ID, or EC2 instance ID of the single endpoint to accelerate, such as an existing ALB's ARN."
  type        = string
}
