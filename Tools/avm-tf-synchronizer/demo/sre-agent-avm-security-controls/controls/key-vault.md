# Azure Key Vault – Security Controls

Derived from the Azure Policy [regulatory compliance controls for Azure Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/security-controls-policy). One control per Azure Policy definition.

| ID | Title | Severity |
| --- | --- | --- |
| [SC-KV-001](#sc-kv-001-enable-deletion-protection-on-key-vaults) | Enable deletion protection on Key Vaults | High |
| [SC-KV-002](#sc-kv-002-restrict-key-vault-access-to-virtual-network-service-endpoints) | Restrict Key Vault access to virtual network service endpoints | High |
| [SC-KV-004](#sc-kv-004-disable-public-network-access-or-enable-key-vault-firewall) | Disable public network access or enable Key Vault firewall | High |
| [SC-KV-005](#sc-kv-005-enable-key-vault-firewall-through-policy-remediation) | Enable Key Vault firewall through policy remediation | High |
| [SC-KV-006](#sc-kv-006-enable-purge-protection-on-managed-hsm) | Enable purge protection on Managed HSM | High |
| [SC-KV-007](#sc-kv-007-enable-soft-delete-on-key-vaults) | Enable soft delete on Key Vaults | High |
| [SC-KV-008](#sc-kv-008-use-private-link-for-key-vaults) | Use private link for Key Vaults | High |
| [SC-KV-003](#sc-kv-003-enable-key-vault-resource-logs) | Enable Key Vault resource logs | Medium |
| [SC-KV-009](#sc-kv-009-deploy-key-vault-diagnostic-settings-to-log-analytics) | Deploy Key Vault diagnostic settings to Log Analytics | Medium |
| [SC-KV-010](#sc-kv-010-enable-managed-hsm-resource-logs) | Enable Managed HSM resource logs | Medium |
| [SC-KV-011](#sc-kv-011-use-rbac-permission-model-for-key-vaults) | Use RBAC permission model for Key Vaults | Medium |

## SC-KV-001: Enable deletion protection on Key Vaults

- **Applies to:** Key Vault
- **Requirement:** Key Vaults and their objects must be recoverable: purge protection must be enabled so a deleted vault, key, secret or certificate cannot be permanently purged before the retention period ends.
- **Severity:** High
- **Azure Policy:** [Key vaults should have deletion protection enabled](https://portal.azure.com/#blade/Microsoft_Azure_Policy/PolicyDetailBlade/definitionId/%2Fproviders%2FMicrosoft.Authorization%2FpolicyDefinitions%2F0b60c0b2-2dc2-4e1c-b5c9-abbed971de53) (`0b60c0b2-2dc2-4e1c-b5c9-abbed971de53`)

## SC-KV-002: Restrict Key Vault access to virtual network service endpoints

- **Applies to:** Key Vault, Virtual network subnets
- **Requirement:** Key Vault network access must be restricted to approved virtual network subnets via service endpoints; access from other networks must be denied by default.
- **Severity:** High
- **Azure Policy:** [Key Vault should use a virtual network service endpoint](https://portal.azure.com/#blade/Microsoft_Azure_Policy/PolicyDetailBlade/definitionId/%2Fproviders%2FMicrosoft.Authorization%2FpolicyDefinitions%2Fea4d6841-2173-4317-9747-ff522a45120f) (`ea4d6841-2173-4317-9747-ff522a45120f`)

## SC-KV-004: Disable public network access or enable Key Vault firewall

- **Applies to:** Key Vault
- **Requirement:** Key Vault must not accept unrestricted public traffic: either public network access is disabled or the firewall denies all traffic except explicitly allowed IP ranges/subnets.
- **Severity:** High
- **Azure Policy:** [Azure Key Vault should have firewall enabled or public network access disabled](https://portal.azure.com/#blade/Microsoft_Azure_Policy/PolicyDetailBlade/definitionId/%2Fproviders%2FMicrosoft.Authorization%2FpolicyDefinitions%2F55615ac9-af46-4a59-874e-391cc3dfb490) (`55615ac9-af46-4a59-874e-391cc3dfb490`)

## SC-KV-005: Enable Key Vault firewall through policy remediation

- **Applies to:** Key Vault
- **Requirement:** Key Vaults without a firewall are remediated by Azure Policy to enable it; modules must deploy with the firewall already enabled so remediation never changes them.
- **Severity:** High
- **Azure Policy:** [Configure key vaults to enable firewall](https://portal.azure.com/#blade/Microsoft_Azure_Policy/PolicyDetailBlade/definitionId/%2Fproviders%2FMicrosoft.Authorization%2FpolicyDefinitions%2Fac673a9a-f77d-4846-b2d8-a57f8e1c01dc) (`ac673a9a-f77d-4846-b2d8-a57f8e1c01dc`)

## SC-KV-006: Enable purge protection on Managed HSM

- **Applies to:** Managed HSM
- **Requirement:** Managed HSM must have purge protection enabled so a deleted HSM or its keys cannot be permanently purged during the retention period.
- **Severity:** High
- **Azure Policy:** [Azure Key Vault Managed HSM should have purge protection enabled](https://portal.azure.com/#blade/Microsoft_Azure_Policy/PolicyDetailBlade/definitionId/%2Fproviders%2FMicrosoft.Authorization%2FpolicyDefinitions%2Fc39ba22d-4428-4149-b981-70acb31fc383) (`c39ba22d-4428-4149-b981-70acb31fc383`)

## SC-KV-007: Enable soft delete on Key Vaults

- **Applies to:** Key Vault
- **Requirement:** Soft delete must be enabled on every Key Vault so deleted vaults and objects can be recovered within the retention period.
- **Severity:** High
- **Azure Policy:** [Key vaults should have soft delete enabled](https://portal.azure.com/#blade/Microsoft_Azure_Policy/PolicyDetailBlade/definitionId/%2Fproviders%2FMicrosoft.Authorization%2FpolicyDefinitions%2F1e66c121-a66a-4b1f-9b83-0fd99bf0fc2d) (`1e66c121-a66a-4b1f-9b83-0fd99bf0fc2d`)

## SC-KV-008: Use private link for Key Vaults

- **Applies to:** Key Vault, Private endpoints
- **Requirement:** Key Vault must be reachable over Azure Private Link through a private endpoint in an approved subnet.
- **Severity:** High
- **Azure Policy:** [Azure Key Vaults should use private link](https://portal.azure.com/#blade/Microsoft_Azure_Policy/PolicyDetailBlade/definitionId/%2Fproviders%2FMicrosoft.Authorization%2FpolicyDefinitions%2Fa6abeaec-4d90-4a02-805f-6b26c4d3fbe9) (`a6abeaec-4d90-4a02-805f-6b26c4d3fbe9`)

## SC-KV-003: Enable Key Vault resource logs

- **Applies to:** Key Vault, Diagnostic settings
- **Requirement:** Every Key Vault must send resource (audit) logs to a log destination so activity can be reconstructed during investigations.
- **Severity:** Medium
- **Azure Policy:** [Resource logs in Key Vault should be enabled](https://portal.azure.com/#blade/Microsoft_Azure_Policy/PolicyDetailBlade/definitionId/%2Fproviders%2FMicrosoft.Authorization%2FpolicyDefinitions%2Fcf820ca0-f99e-4f3e-84fb-66e913812d21) (`cf820ca0-f99e-4f3e-84fb-66e913812d21`)

## SC-KV-009: Deploy Key Vault diagnostic settings to Log Analytics

- **Applies to:** Key Vault, Diagnostic settings
- **Requirement:** Key Vault diagnostic settings must stream to a Log Analytics workspace (deployed by policy if missing); modules must deploy them so remediation is not needed.
- **Severity:** Medium
- **Azure Policy:** [Deploy Diagnostic Settings for Key Vault to Log Analytics workspace](https://portal.azure.com/#blade/Microsoft_Azure_Policy/PolicyDetailBlade/definitionId/%2Fproviders%2FMicrosoft.Authorization%2FpolicyDefinitions%2Fbef3f64c-5290-43b7-85b0-9b254eef4c47) (`bef3f64c-5290-43b7-85b0-9b254eef4c47`)

## SC-KV-010: Enable Managed HSM resource logs

- **Applies to:** Managed HSM, Diagnostic settings
- **Requirement:** Every Managed HSM must send resource (audit) logs to a log destination.
- **Severity:** Medium
- **Azure Policy:** [Resource logs in Azure Key Vault Managed HSM should be enabled](https://portal.azure.com/#blade/Microsoft_Azure_Policy/PolicyDetailBlade/definitionId/%2Fproviders%2FMicrosoft.Authorization%2FpolicyDefinitions%2Fa2a5b911-5617-447e-a49e-59dbe0e0434b) (`a2a5b911-5617-447e-a49e-59dbe0e0434b`)

## SC-KV-011: Use RBAC permission model for Key Vaults

- **Applies to:** Key Vault
- **Requirement:** Key Vault data-plane access must use Azure RBAC, not vault access policies.
- **Severity:** Medium
- **Azure Policy:** [Azure Key Vault should use RBAC permission model](https://portal.azure.com/#blade/Microsoft_Azure_Policy/PolicyDetailBlade/definitionId/%2Fproviders%2FMicrosoft.Authorization%2FpolicyDefinitions%2F12d4fa5e-1f9f-4c21-97a9-b99b3c6611b5) (`12d4fa5e-1f9f-4c21-97a9-b99b3c6611b5`)
