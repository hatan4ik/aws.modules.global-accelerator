variable "name_prefix" {
  description = "Prefix used to tag the disposable Elastic IP fixture."
  type        = string
  default     = "ga-it"

  validation {
    condition     = can(regex("^[a-z0-9-]{1,32}$", var.name_prefix))
    error_message = "name_prefix must be 1-32 lowercase letters, digits, or hyphens."
  }
}

variable "tags" {
  description = "Tags applied to the Elastic IP fixture in addition to the identifying defaults."
  type        = map(string)
  default     = {}
}
