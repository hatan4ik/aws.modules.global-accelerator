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
