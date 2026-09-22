/**
 * @module services/foundry
 * @description Create-or-bring-your-own primary AI Foundry (Azure AI Services / Cognitive Services
 *              account) used by APIM as the backend for Content Safety and the named-value URL for
 *              PII / Language processing (exposed on the unified AI Services endpoint).
 *
 *              For an EXISTING (BYO) account this module references it and (optionally) applies
 *              additive APIM RBAC and model deployments. It NEVER changes the account network
 *              configuration (publicNetworkAccess, network ACLs, private endpoints).
 *
 * Scope: Resource Group
 */

targetScope = 'resourceGroup'

@description('Create a new AI Foundry (AI Services) account. When false, an existing account (BYO) is referenced by name.')
param createNew bool = true

@description('Name of the AI Foundry account to create or reference.')
param foundryName string

@description('Location for the account (only used when createNew is true).')
param location string = resourceGroup().location

@description('Tags to apply (only used when createNew is true).')
param tags object = {}

@description('Custom sub-domain name for a newly created account. Defaults to the lowercased account name.')
param customSubDomainName string = ''

@description('Default project name for a newly created account.')
param foundryProjectName string = 'citadel-governance-project'

@description('Public network access for a newly created account. Ignored for BYO accounts.')
@allowed(['Enabled', 'Disabled'])
param publicNetworkAccess string = 'Enabled'

@description('Disable local (key) auth, enabling only Entra ID auth (created accounts only).')
param disableKeyAuth bool = false

@description('Principal ID of the APIM managed identity to grant Cognitive Services User (additive).')
param apimPrincipalId string = ''

@description('Add model deployments to the account. Defaults to false (endpoint-only for BYO).')
param deployModels bool = false

@description('Model deployments configuration (only used when deployModels is true). Each entry: name, publisher, version, sku, capacity.')
param modelsConfig array = []

// ---------------------------------------------------------------------------
//  Private endpoint (created accounts only)
// ---------------------------------------------------------------------------

@description('Create a private endpoint for a newly created account. Ignored for BYO accounts.')
param usePrivateEndpoint bool = false

@description('Base name of the AI Foundry private endpoint (only used when usePrivateEndpoint is true).')
param foundryPrivateEndpointName string = ''

@description('Name of the Virtual Network for the private endpoint.')
param vNetName string = ''

@description('Location of the Virtual Network.')
param vNetLocation string = location

@description('Resource group containing the Virtual Network.')
param vNetRG string = resourceGroup().name

@description('Name of the private endpoint subnet.')
param privateEndpointSubnetName string = ''

@description('DNS zone names for the AI Foundry private endpoint.')
param aiServicesDnsZoneNames array = [
  'privatelink.cognitiveservices.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.services.ai.azure.com'
]

@description('Direct DNS zone resource IDs for the AI Foundry private endpoint (preferred). Order matches aiServicesDnsZoneNames.')
param dnsZoneResourceIds array = []

var cognitiveServicesUserRoleDefinitionId = resourceId('Microsoft.Authorization/roleDefinitions', 'a97b65f3-24c7-4388-baec-2e87135dc908')

resource foundryNew 'Microsoft.CognitiveServices/accounts@2026-01-15-preview' = if (createNew) {
  name: foundryName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'S0'
  }
  kind: 'AIServices'
  properties: {
    allowProjectManagement: true
    customSubDomainName: toLower(!empty(customSubDomainName) ? customSubDomainName : foundryName)
    disableLocalAuth: disableKeyAuth
    publicNetworkAccess: publicNetworkAccess
    networkAcls: {
      defaultAction: publicNetworkAccess == 'Enabled' ? 'Allow' : 'Deny'
      bypass: 'AzureServices'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

resource foundryRef 'Microsoft.CognitiveServices/accounts@2026-01-15-preview' existing = {
  name: foundryName
}

resource aiProject 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = if (createNew) {
  name: foundryProjectName
  parent: foundryNew
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    description: 'Citadel Governance Hub default project'
  }
}

// Additive RBAC: APIM managed identity Cognitive Services User
resource apimCognitiveServicesUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(apimPrincipalId)) {
  scope: foundryRef
  name: guid(subscription().id, resourceGroup().id, foundryName, cognitiveServicesUserRoleDefinitionId, apimPrincipalId)
  properties: {
    roleDefinitionId: cognitiveServicesUserRoleDefinitionId
    principalId: apimPrincipalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [ foundryNew ]
}

// Optional model deployments (additive)
module modelDeployments '../../modules/foundry/deployments.bicep' = if (deployModels && !empty(modelsConfig)) {
  name: take('models-${foundryName}', 64)
  params: {
    cognitiveServiceName: foundryName
    modelsConfig: modelsConfig
  }
  dependsOn: [ foundryNew, aiProject ]
}

// Private endpoint (created accounts only)
module privateEndpoint '../../modules/networking/private-endpoint-multi-dns.bicep' = if (createNew && usePrivateEndpoint) {
  name: 'pe-${foundryName}'
  params: {
    name: !empty(foundryPrivateEndpointName) ? foundryPrivateEndpointName : '${foundryName}-pe'
    privateLinkServiceId: foundryRef.id
    groupIds: [ 'account' ]
    dnsZoneNames: aiServicesDnsZoneNames
    location: vNetLocation
    privateEndpointSubnetId: resourceId(vNetRG, 'Microsoft.Network/virtualNetworks/subnets', vNetName, privateEndpointSubnetName)
    dnsZoneResourceIds: dnsZoneResourceIds
    tags: tags
  }
  dependsOn: [ foundryNew ]
}

@description('Name of the AI Foundry account (created or existing).')
output foundryName string = foundryName

@description('Resource ID of the AI Foundry account.')
output foundryId string = foundryRef.id

@description('Endpoint of the AI Foundry account (used by APIM for Content Safety and PII/Language).')
#disable-next-line BCP318
output foundryEndpoint string = createNew ? foundryNew.properties.endpoint : foundryRef.properties.endpoint

@description('Principal (object) ID of the AI Foundry system-assigned identity (empty for BYO accounts).')
#disable-next-line BCP318
output foundryPrincipalId string = createNew ? foundryNew.identity.principalId : ''
