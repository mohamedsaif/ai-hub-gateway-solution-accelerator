/**
 * @module services/storage
 * @description Create-or-bring-your-own Storage Account for the usage Logic App, ensuring the
 *              content file share exists and granting the usage identity Storage Blob Data Owner.
 *
 *              For an EXISTING (BYO) account this module only ADDS the file share and RBAC.
 *              It NEVER changes the account network configuration (publicNetworkAccess,
 *              network ACLs, private endpoints).
 *
 * Scope: Resource Group
 */

targetScope = 'resourceGroup'

@description('Create a new Storage Account. When false, an existing account (BYO) is referenced by name.')
param createNew bool = true

@description('Name of the Storage Account to create or reference.')
param storageAccountName string

@description('Location for the account (only used when createNew is true).')
param location string = resourceGroup().location

@description('Tags to apply (only used when createNew is true).')
param tags object = {}

@description('Storage account SKU (only used when createNew is true).')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS'])
param storageAccountType string = 'Standard_LRS'

@description('Public network access for a newly created account. Ignored for BYO accounts.')
@allowed(['Enabled', 'Disabled'])
param publicNetworkAccess string = 'Enabled'

@description('Name of the Logic App content file share.')
param logicContentShareName string

@description('Name of the usage managed identity to grant Storage Blob Data Owner.')
param functionAppManagedIdentityName string

// ---------------------------------------------------------------------------
//  Private endpoints (created accounts only)
// ---------------------------------------------------------------------------

@description('Create private endpoints (blob/file/table/queue) for a newly created account. Ignored for BYO accounts.')
param usePrivateEndpoint bool = false

@description('Name of the Virtual Network for the private endpoints.')
param vNetName string = ''

@description('Resource group containing the Virtual Network.')
param vNetRG string = resourceGroup().name

@description('Name of the private endpoint subnet.')
param privateEndpointSubnetName string = ''

@description('Direct DNS zone resource ID for blob private endpoint (preferred).')
param storageBlobDnsZoneResourceId string = ''

@description('Direct DNS zone resource ID for file private endpoint (preferred).')
param storageFileDnsZoneResourceId string = ''

var storageBlobDataOwnerRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')

resource functionAppManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: functionAppManagedIdentityName
}

resource storageAccountNew 'Microsoft.Storage/storageAccounts@2023-05-01' = if (createNew) {
  name: storageAccountName
  location: location
  tags: union(tags, { 'azd-service-name': storageAccountName })
  sku: {
    name: storageAccountType
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: publicNetworkAccess
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    accessTier: 'Hot'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: publicNetworkAccess == 'Enabled' ? 'Allow' : 'Deny'
    }
  }
}

resource storageAccountRef 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' = {
  name: '${storageAccountName}/default/${logicContentShareName}'
  dependsOn: [ storageAccountNew ]
}

resource storageBlobDataOwnerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccountName, functionAppManagedIdentity.name, storageBlobDataOwnerRoleId)
  scope: storageAccountRef
  properties: {
    principalId: functionAppManagedIdentity.properties.principalId
    roleDefinitionId: storageBlobDataOwnerRoleId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [ storageAccountNew ]
}

// Private endpoints (created accounts only)
module privateEndpointBlob '../../modules/networking/private-endpoint.bicep' = if (createNew && usePrivateEndpoint) {
  name: '${storageAccountName}-blob-pe'
  params: {
    groupIds: [ 'blob' ]
    #disable-next-line no-hardcoded-env-urls
    dnsZoneName: 'privatelink.blob.core.windows.net'
    name: '${storageAccountName}-blob-pe'
    privateLinkServiceId: storageAccountRef.id
    location: location
    privateEndpointSubnetId: resourceId(vNetRG, 'Microsoft.Network/virtualNetworks/subnets', vNetName, privateEndpointSubnetName)
    dnsZoneResourceId: storageBlobDnsZoneResourceId
    tags: tags
  }
  dependsOn: [ storageAccountNew ]
}

module privateEndpointFile '../../modules/networking/private-endpoint.bicep' = if (createNew && usePrivateEndpoint) {
  name: '${storageAccountName}-file-pe'
  params: {
    groupIds: [ 'file' ]
    #disable-next-line no-hardcoded-env-urls
    dnsZoneName: 'privatelink.file.core.windows.net'
    name: '${storageAccountName}-file-pe'
    privateLinkServiceId: storageAccountRef.id
    location: location
    privateEndpointSubnetId: resourceId(vNetRG, 'Microsoft.Network/virtualNetworks/subnets', vNetName, privateEndpointSubnetName)
    dnsZoneResourceId: storageFileDnsZoneResourceId
    tags: tags
  }
  dependsOn: [ storageAccountNew ]
}

@description('Name of the Storage Account (created or existing).')
output storageAccountName string = storageAccountName
