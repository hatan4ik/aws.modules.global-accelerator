# ---------------------------------------------------------------------------
# Accelerator
# ---------------------------------------------------------------------------

variable "name" {
  description = "Name of the accelerator, unique within the account and Region."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9-]{1,64}$", var.name))
    error_message = "name must be 1-64 characters: letters, digits, and hyphens."
  }
}

variable "ip_address_type" {
  description = "IP address type of the accelerator's static anycast IP addresses: IPV4 or DUAL_STACK."
  type        = string
  default     = "IPV4"
  nullable    = false

  validation {
    condition     = contains(["IPV4", "DUAL_STACK"], var.ip_address_type)
    error_message = "ip_address_type must be IPV4 or DUAL_STACK."
  }
}

variable "enabled" {
  description = "Whether the accelerator routes traffic. Setting this to false stops traffic at the static IP addresses without deleting the accelerator, its listeners, or its endpoint groups."
  type        = bool
  default     = true
  nullable    = false
}

variable "flow_logs" {
  description = "Flow log destination. bucket_name is an existing S3 bucket the caller owns and creates (the same ownership boundary as aws.modules.alb's access_logs and aws.modules.cloudfront's logging); prefix is an optional key prefix within it. null (the default) disables flow logs; a check block advises turning them on."
  type = object({
    bucket_name = string
    prefix      = optional(string)
  })
  default = null

  validation {
    condition     = var.flow_logs == null ? true : can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.flow_logs.bucket_name))
    error_message = "flow_logs.bucket_name must be a bucket name: 3-63 lowercase letters, digits, dots, or hyphens, starting and ending with a letter or digit."
  }

  validation {
    condition     = var.flow_logs == null ? true : (var.flow_logs.prefix == null ? true : !startswith(var.flow_logs.prefix, "/"))
    error_message = "flow_logs.prefix must not start with /."
  }
}

# ---------------------------------------------------------------------------
# Listeners
# ---------------------------------------------------------------------------

variable "listeners" {
  description = "Listeners keyed by a short logical name (no \"/\"), referenced by the listener half of each endpoint_groups key. protocol defaults to TCP; port_ranges is one or more inclusive port ranges the listener accepts; client_affinity defaults to NONE (SOURCE_IP pins a client to one endpoint for the accelerator's stickiness window). At least one entry is required."
  type = map(object({
    protocol = optional(string, "TCP")
    port_ranges = list(object({
      from_port = number
      to_port   = number
    }))
    client_affinity = optional(string, "NONE")
  }))
  nullable = false

  validation {
    condition     = length(var.listeners) > 0
    error_message = "listeners must contain at least one entry."
  }

  validation {
    condition     = alltrue([for key in keys(var.listeners) : can(regex("^[^/]+$", key))])
    error_message = "Every listeners key must be non-empty and must not contain \"/\", which separates the listener key from the region in endpoint_groups keys."
  }

  validation {
    condition     = alltrue([for listener in values(var.listeners) : contains(["TCP", "UDP"], listener.protocol)])
    error_message = "Every listener's protocol must be TCP or UDP."
  }

  validation {
    condition     = alltrue([for listener in values(var.listeners) : contains(["NONE", "SOURCE_IP"], listener.client_affinity)])
    error_message = "Every listener's client_affinity must be NONE or SOURCE_IP."
  }

  validation {
    condition     = alltrue([for listener in values(var.listeners) : length(listener.port_ranges) > 0])
    error_message = "Every listener must declare at least one entry in port_ranges."
  }

  validation {
    condition = alltrue(flatten([
      for listener in values(var.listeners) : [
        for range in listener.port_ranges :
        range.from_port >= 1 && range.from_port <= 65535 && range.to_port >= 1 && range.to_port <= 65535 && range.from_port <= range.to_port
      ]
    ]))
    error_message = "Every port_ranges entry must have from_port and to_port between 1 and 65535, with from_port <= to_port."
  }
}

# ---------------------------------------------------------------------------
# Endpoint groups
# ---------------------------------------------------------------------------

variable "endpoint_groups" {
  description = "Endpoint groups keyed by \"<listener_key>/<region>\", for example \"api/us-east-1\": the part before the slash must name an entry in listeners and the part after it is the AWS region the group is created in. This mirrors the Global Accelerator rule of one endpoint group per (listener, region) pair, so M listeners and N regions compose into up to M x N groups. traffic_dial_percentage (default 100) is the share of listener traffic steered to this group; at least one group across the map must be non-zero, since an accelerator whose groups are all dialed to zero serves no traffic. Health checks: health_check_port (defaults to the listener's port when null), health_check_protocol, health_check_path, health_check_interval_seconds, and threshold_count take effect ONLY for Elastic IP and EC2 instance endpoints. For ALB and NLB endpoints, Global Accelerator ignores them and uses the load balancer's own target-group health checks, so configure health there; an advisory check warns when a group of only load balancers sets them away from their defaults. health_check_path is only used when health_check_protocol is HTTP or HTTPS (a second advisory check warns when it is paired with TCP). endpoint_configurations lists the endpoints in the group: endpoint_id is an ALB/NLB ARN in the group's region, an Elastic IP allocation ID (eipalloc-...), or an EC2 instance ID (i-...), validated by shape at plan time; weight (default 128) shares traffic within the group, and client_ip_preservation_enabled (default true) preserves the client's source IP to the endpoint where the endpoint type supports it. At least one entry is required, and every group needs at least one endpoint."
  type = map(object({
    traffic_dial_percentage       = optional(number, 100)
    health_check_port             = optional(number)
    health_check_protocol         = optional(string, "TCP")
    health_check_path             = optional(string)
    health_check_interval_seconds = optional(number, 30)
    threshold_count               = optional(number, 3)
    endpoint_configurations = list(object({
      endpoint_id                    = string
      weight                         = optional(number, 128)
      client_ip_preservation_enabled = optional(bool, true)
    }))
  }))
  nullable = false

  validation {
    condition     = length(var.endpoint_groups) > 0
    error_message = "endpoint_groups must contain at least one entry."
  }

  validation {
    condition     = alltrue([for key in keys(var.endpoint_groups) : can(regex("^[^/]+/[a-z]{2}-(gov-|iso-|isob-)?[a-z]+-[0-9]$", key))])
    error_message = "Every endpoint_groups key must be \"<listener_key>/<region>\", for example api/us-east-1, primary/eu-west-2, or vpn/us-gov-west-1."
  }

  validation {
    condition     = anytrue([for group in values(var.endpoint_groups) : group.traffic_dial_percentage > 0])
    error_message = "At least one endpoint group must have a non-zero traffic_dial_percentage; an accelerator with every group dialed to zero serves no traffic."
  }

  validation {
    condition     = alltrue([for group in values(var.endpoint_groups) : group.traffic_dial_percentage >= 0 && group.traffic_dial_percentage <= 100])
    error_message = "Every endpoint group's traffic_dial_percentage must be between 0 and 100."
  }

  validation {
    condition     = alltrue([for group in values(var.endpoint_groups) : contains(["TCP", "HTTP", "HTTPS"], group.health_check_protocol)])
    error_message = "Every endpoint group's health_check_protocol must be TCP, HTTP, or HTTPS."
  }

  validation {
    condition     = alltrue([for group in values(var.endpoint_groups) : group.health_check_port == null ? true : (group.health_check_port >= 1 && group.health_check_port <= 65535)])
    error_message = "Every endpoint group's health_check_port, when set, must be between 1 and 65535."
  }

  validation {
    condition     = alltrue([for group in values(var.endpoint_groups) : contains([10, 30], group.health_check_interval_seconds)])
    error_message = "Every endpoint group's health_check_interval_seconds must be 10 or 30, the only values Global Accelerator health checks accept."
  }

  validation {
    condition     = alltrue([for group in values(var.endpoint_groups) : group.threshold_count >= 1 && group.threshold_count <= 10 && floor(group.threshold_count) == group.threshold_count])
    error_message = "Every endpoint group's threshold_count must be a whole number between 1 and 10."
  }

  validation {
    condition     = alltrue([for group in values(var.endpoint_groups) : length(group.endpoint_configurations) > 0])
    error_message = "Every endpoint group must declare at least one entry in endpoint_configurations."
  }

  # The three endpoint ID shapes Global Accelerator accepts in an endpoint
  # group: an ALB or NLB ARN (any partition), an Elastic IP allocation ID, or
  # an EC2 instance ID (8 or 17 hex characters after the prefix). A target
  # group ARN, a load balancer name, or a Gateway Load Balancer ARN fails here
  # at plan rather than at apply.
  validation {
    condition = alltrue(flatten([
      for group in values(var.endpoint_groups) : [
        for endpoint in group.endpoint_configurations :
        can(regex("^arn:aws[a-z-]*:elasticloadbalancing:[a-z0-9-]+:[0-9]{12}:loadbalancer/(app|net)/[A-Za-z0-9-]{1,32}/[0-9a-f]+$", endpoint.endpoint_id)) ||
        can(regex("^eipalloc-([0-9a-f]{8}|[0-9a-f]{17})$", endpoint.endpoint_id)) ||
        can(regex("^i-([0-9a-f]{8}|[0-9a-f]{17})$", endpoint.endpoint_id))
      ]
    ]))
    error_message = "Every endpoint_configurations entry's endpoint_id must be an ALB or NLB ARN (arn:<partition>:elasticloadbalancing:<region>:<account>:loadbalancer/app|net/<name>/<id>), an Elastic IP allocation ID (eipalloc-<8 or 17 hex>), or an EC2 instance ID (i-<8 or 17 hex>)."
  }

  # An endpoint group only accepts load balancers in its own region. Compared
  # against the region half of the group's key; non-ARN IDs carry no region.
  validation {
    condition = alltrue(flatten([
      for key, group in var.endpoint_groups : [
        for endpoint in group.endpoint_configurations :
        !startswith(endpoint.endpoint_id, "arn:") || try(split(":", endpoint.endpoint_id)[3] == split("/", key)[1], false)
      ]
    ]))
    error_message = "Every load balancer ARN in endpoint_configurations must be in the same region as its endpoint group (the region half of the \"<listener_key>/<region>\" key)."
  }

  validation {
    condition = alltrue(flatten([
      for group in values(var.endpoint_groups) : [
        for endpoint in group.endpoint_configurations : endpoint.weight >= 0 && endpoint.weight <= 255
      ]
    ]))
    error_message = "Every endpoint_configurations entry's weight must be between 0 and 255, the Global Accelerator bound."
  }
}

# ---------------------------------------------------------------------------
# Tags
# ---------------------------------------------------------------------------

variable "tags" {
  description = "Tags applied to the accelerator. Listeners and endpoint groups are not taggable resources in the Global Accelerator API. The module adds a Name tag equal to name unless you set one; caller tags are never overridden."
  type        = map(string)
  default     = {}
  nullable    = false
}
