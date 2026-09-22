/**
 * @module services/key-vault
 * @description Create-or-bring-your-own Azure Key Vault for the gateway ecosystem, with optional
 *              private endpoint (created resources only) and additive RBAC assignments.
 *
 *              For an EXISTING (BYO) Key Vault this module references the vault and applies only
 *              additive role assignments. It NEVER changes the vault's network configuration
 *              (publicNetworkAccess, network ACLs, private endpoints).
 *
 * Scope: Resource Group
 */

targetScope = 'resourceGroup'

@description('Create a new Key Vault. When false, an existing vault (BYO) is referenced by name.')
param createNew bool = true

@description('Name of the Key Vault to create or reference.')
param keyVaultName string

@description('Location for the Key Vault (only used when createNew is true).')
param location string = resourceGroup().location

@description('Tags to apply (only used when createNew is true).')
param tags object = {}

@description('SKU for the Key Vault (only used when createNew is true).')
@allowed(['standard', 'premium'])
param skuName string = 'standard'

@description('Public network access for a newly created Key Vault. Ignored for BYO vaults.')
@allowed(['Enabled', 'Disabled'])
param publicNetworkAccess string = 'Enabled'

// ---------------------------------------------------------------------------
//  Private endpoint (created vaults only)
// ---------------------------------------------------------------------------

@description('Create a private endpoint for a newly created Key Vault. Ignored for BYO vaults.')
param usePrivateEndpoint bool = false

@description('Name of the Key Vault private endpoint (only used when usePrivateEndpoint is true).')
param keyVaultPrivateEndpointName string = ''

@description('Name of the Virtual Network for the private endpoint (only used when usePrivateEndpoint is true).')
param vNetName string = ''

@description('Resource group containing the Virtual Network (only used when usePrivateEndpoint is true).')
param vNetRG string = resourceGroup().name

@description('Name of the private endpoint subnet (only used when usePrivateEndpoint is true).')
param privateEndpointSubnetName string = ''

@description('DNS zone name for the Key Vault private endpoint.')
param keyVaultDnsZoneName string = 'privatelink.vaultcore.azure.net'

@description('Direct DNS zone resource ID for the Key Vault private endpoint (preferred).')
param dnsZoneResourceId string = ''

// ---------------------------------------------------------------------------
//  RBAC (additive)
// ---------------------------------------------------------------------------

@description('Principal ID of a user-assigned managed identity to grant Key Vault Secrets User.')
param apimPrincipalId string = ''

@description('Principal ID of the APIM system-assigned identity to grant Secrets User + Certificate User.')
param apimSystemAssignedPrincipalId string = ''

@description('Principal IDs of AI Foundry resources to grant Secrets User + Certificates Officer.')
param aiFoundryPrincipalIds array = []

var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'
var keyVaultCertificateUserRoleId = 'db79e9a7-68ee-4b58-9aeb-b90e7c24fcba'
var keyVaultCertificatesOfficerRoleId = 'a4417e6f-fecd-4de8-b567-7b0420556985'

resource keyVaultNew 'Microsoft.KeyVault/vaults@2025-05-01' = if (createNew) {
  name: keyVaultName
  location: location
  tags: union(tags, { 'azd-service-name': keyVaultName })
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: skuName
    }
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    enableRbacAuthorization: true
    enabledForTemplateDeployment: true
    publicNetworkAccess: publicNetworkAccess
    networkAcls: {
      defaultAction: publicNetworkAccess == 'Enabled' ? 'Allow' : 'Deny'
      bypass: 'AzureServices'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

// Non-conditional reference used for role-assignment scope and outputs (resolves whether the
// vault is created in this deployment or pre-exists).
resource keyVaultRef 'Microsoft.KeyVault/vaults@2025-05-01' existing = {
  name: keyVaultName
}

var keyVaultId = createNew ? keyVaultNew.id : keyVaultRef.id
#disable-next-line BCP318
var keyVaultUri = createNew ? keyVaultNew.properties.vaultUri : keyVaultRef.properties.vaultUri

// Private endpoint (created vaults only)
module privateEndpoint '../../modules/networking/private-endpoint.bicep' = if (createNew && usePrivateEndpoint) {
  name: '${keyVaultName}-pe'
  params: {
    groupIds: [ 'vault' ]
    dnsZoneName: keyVaultDnsZoneName
    name: !empty(keyVaultPrivateEndpointName) ? keyVaultPrivateEndpointName : '${keyVaultName}-pe'
    privateLinkServiceId: keyVaultId
    location: location
    privateEndpointSubnetId: resourceId(vNetRG, 'Microsoft.Network/virtualNetworks/subnets', vNetName, privateEndpointSubnetName)
    dnsZoneResourceId: dnsZoneResourceId
    tags: tags
  }
}

// RBAC: user-assigned identity Secrets User
resource apimSecretsUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(apimPrincipalId)) {
  scope: keyVaultRef
  name: guid(subscription().id, resourceGroup().id, keyVaultName, keyVaultSecretsUserRoleId, apimPrincipalId)
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: apimPrincipalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [ keyVaultNew ]
}

// RBAC: APIM system-assigned identity Secrets User
resource apimSystemSecretsUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(apimSystemAssignedPrincipalId)) {
  scope: keyVaultRef
  name: guid(subscription().id, resourceGroup().id, keyVaultName, keyVaultSecretsUserRoleId, apimSystemAssignedPrincipalId)
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: apimSystemAssignedPrincipalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [ keyVaultNew ]
}

// RBAC: APIM system-assigned identity Certificate User
resource apimSystemCertificateUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(apimSystemAssignedPrincipalId)) {
  scope: keyVaultRef
  name: guid(subscription().id, resourceGroup().id, keyVaultName, keyVaultCertificateUserRoleId, apimSystemAssignedPrincipalId)
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', keyVaultCertificateUserRoleId)
    principalId: apimSystemAssignedPrincipalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [ keyVaultNew ]
}

// RBAC: AI Foundry identities Secrets User
resource foundrySecretsUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (principalId, i) in aiFoundryPrincipalIds: if (!empty(principalId)) {
  scope: keyVaultRef
  name: guid(subscription().id, resourceGroup().id, keyVaultName, keyVaultSecretsUserRoleId, principalId)
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [ keyVaultNew ]
}]

// RBAC: AI Foundry identities Certificates Officer
resource foundryCertificatesOfficerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (principalId, i) in aiFoundryPrincipalIds: if (!empty(principalId)) {
  scope: keyVaultRef
  name: guid(subscription().id, resourceGroup().id, keyVaultName, keyVaultCertificatesOfficerRoleId, principalId)
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', keyVaultCertificatesOfficerRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [ keyVaultNew ]
}]

@description('Name of the Key Vault (created or existing).')
output keyVaultName string = keyVaultName

@description('Resource ID of the Key Vault.')
output keyVaultId string = keyVaultId

@description('URI of the Key Vault.')
output keyVaultUri string = keyVaultUri
