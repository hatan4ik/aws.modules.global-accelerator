# Advisory checks: they warn on every plan and apply but never block. Each
# describes a configuration that is valid yet usually unintended.

check "flow_logs_disabled" {
  assert {
    condition     = local.flow_logs_enabled
    error_message = "Flow logs are disabled (flow_logs is null). Turn them on with an S3 bucket you own to record connection-level records for this accelerator."
  }
}

check "single_region_endpoint_groups" {
  assert {
    condition     = length(local.endpoint_group_regions) >= 2
    error_message = "Only one region is present in endpoint_groups. ADR 0004 calls for two regional public ALBs behind this accelerator for active-active steering; a single-region accelerator is valid but may be a mid-rollout state rather than the intended shape."
  }
}

check "health_check_settings_ignored_for_load_balancer_endpoints" {
  assert {
    condition     = length(local.health_check_ignored_groups) == 0
    error_message = "Endpoint group(s) ${join(", ", local.health_check_ignored_groups)} set health_check_* or threshold_count away from the defaults, but every endpoint in them is an ALB or NLB. Global Accelerator ignores endpoint-group health-check settings for load balancer endpoints and uses the load balancer's own target-group health checks instead; configure health on the target groups (for example through aws.modules.alb) and leave these at their defaults."
  }
}

check "health_check_path_requires_http_protocol" {
  assert {
    condition     = length(local.health_check_path_on_tcp_groups) == 0
    error_message = "Endpoint group(s) ${join(", ", local.health_check_path_on_tcp_groups)} set health_check_path while health_check_protocol is TCP. A path is only used by HTTP and HTTPS health checks; set health_check_protocol to HTTP or HTTPS, or drop health_check_path."
  }
}
