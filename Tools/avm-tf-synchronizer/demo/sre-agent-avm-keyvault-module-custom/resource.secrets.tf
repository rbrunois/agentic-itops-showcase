resource "azurerm_key_vault_secret" "this" {
  for_each = var.secrets

  key_vault_id    = azurerm_key_vault.this.id
  name            = each.value.name
  content_type    = each.value.content_type
  expiration_date = each.value.expiration_date
  not_before_date = each.value.not_before_date
  tags            = merge(each.value.tags, local.tags)
  value           = var.secrets_value[each.key]

  depends_on = [
    azurerm_private_endpoint.this,
    azurerm_private_endpoint.this_unmanaged_dns_zone_groups,
    time_sleep.wait_for_rbac_before_secret_operations
  ]
}

resource "azurerm_role_assignment" "secrets" {
  for_each = local.secret_role_assignments

  principal_id                           = each.value.role_assignment.principal_id
  scope                                  = azurerm_key_vault_secret.this[each.value.secret_key].resource_versionless_id
  condition                              = each.value.role_assignment.condition
  condition_version                      = each.value.role_assignment.condition_version
  delegated_managed_identity_resource_id = each.value.role_assignment.delegated_managed_identity_resource_id
  principal_type                         = each.value.role_assignment.principal_type
  role_definition_id                     = strcontains(lower(each.value.role_assignment.role_definition_id_or_name), lower(local.role_definition_resource_substring)) ? each.value.role_assignment.role_definition_id_or_name : null
  role_definition_name                   = strcontains(lower(each.value.role_assignment.role_definition_id_or_name), lower(local.role_definition_resource_substring)) ? null : each.value.role_assignment.role_definition_id_or_name
  skip_service_principal_aad_check       = each.value.role_assignment.skip_service_principal_aad_check
}

resource "time_sleep" "wait_for_rbac_before_secret_operations" {
  count = length(var.role_assignments) != 0 && length(var.secrets) != 0 ? 1 : 0

  create_duration  = var.wait_for_rbac_before_secret_operations.create
  destroy_duration = var.wait_for_rbac_before_secret_operations.destroy
  triggers = {
    role_assignments = jsonencode(var.role_assignments)
  }

  depends_on = [
    azurerm_role_assignment.this
  ]
}
