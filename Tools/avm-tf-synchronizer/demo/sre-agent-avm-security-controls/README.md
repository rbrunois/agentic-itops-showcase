# SRE Agent AVM – Security Controls

Security controls used by the Azure SRE Agent to validate internal Terraform modules.

## Purpose

Read by engineers and by the Azure SRE Agent **AVM TF Synchronizer**, which remediates internal modules against these controls and ports Azure Verified Module (AVM) changes into them. Controls are written as plain-language requirements; the agent interprets them and checks every ported change against them.

**A control always wins over upstream AVM defaults. A change that violates or weakens a control must not be ported.**

## Control format

IDs follow `SC-<SERVICE>-NNN` (Key Vault: `SC-KV-NNN`). IDs are stable and never reused. Each control is one `##` section with these fields:

| Field | Meaning |
| --- | --- |
| Applies to | Azure resources in scope |
| Requirement | Plain-language rule |
| Severity | High (data exposure/deletion), Medium (logging/access model), Low (other) |
| Azure Policy | Built-in policy the control is derived from |

## Source

[Azure Policy regulatory compliance controls for Azure Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/security-controls-policy)

## Index

| Service | File | Controls |
| --- | --- | --- |
| Azure Key Vault | [controls/key-vault.md](controls/key-vault.md) | SC-KV-001 – SC-KV-011 |
