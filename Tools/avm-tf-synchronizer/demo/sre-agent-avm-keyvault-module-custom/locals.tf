locals {
  role_definition_resource_substring = "/providers/Microsoft.Authorization/roleDefinitions"
}

locals {
  mandatory_tags = {
    environment = var.environment
    owner       = var.owner
    cost_center = var.cost_center
    managed_by  = "terraform"
    module      = "sre-agent-avm-keyvault-module-custom"
  }
  tags = merge(var.tags, local.mandatory_tags)
}

# Private endpoint application security group associations
locals {
  private_endpoint_application_security_group_associations = { for assoc in flatten([
    for pe_k, pe_v in var.private_endpoints : [
      for asg_k, asg_v in pe_v.application_security_group_associations : {
        asg_key         = asg_k
        pe_key          = pe_k
        asg_resource_id = asg_v
      }
    ]
  ]) : "${assoc.pe_key}-${assoc.asg_key}" => assoc }
}

# Role assignments on keys and secrets (inlined from upstream modules/key and modules/secret)
locals {
  key_role_assignments = { for ra in flatten([
    for k_k, k_v in var.keys : [
      for ra_k, ra_v in k_v.role_assignments : {
        key_key         = k_k
        ra_key          = ra_k
        role_assignment = ra_v
      }
    ]
  ]) : "${ra.key_key}-${ra.ra_key}" => ra }
  secret_role_assignments = { for ra in flatten([
    for s_k, s_v in var.secrets : [
      for ra_k, ra_v in s_v.role_assignments : {
        secret_key      = s_k
        ra_key          = ra_k
        role_assignment = ra_v
      }
    ]
  ]) : "${ra.secret_key}-${ra.ra_key}" => ra }
}
