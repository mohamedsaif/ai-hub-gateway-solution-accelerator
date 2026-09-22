targetScope = 'resourceGroup'

@description('Existing Cosmos DB account name.')
param accountName string

@description('Primary write region for this account.')
param primaryRegion string

@description('All write regions that should be configured for this account.')
@minLength(2)
param writeRegions array

@description('Enable automatic failover.')
param systemManagedFailover bool = true

@description('Enable zone redundancy for every configured location.')
param isZoneRedundant bool = false

resource accountExisting 'Microsoft.DocumentDB/databaseAccounts@2024-02-15-preview' existing = {
  name: toLower(accountName)
}

var orderedWriteRegions = union([
  primaryRegion
], writeRegions)

resource accountUpdate 'Microsoft.DocumentDB/databaseAccounts@2024-02-15-preview' = {
  name: accountExisting.name
  location: primaryRegion
  kind: 'GlobalDocumentDB'
  properties: {
    consistencyPolicy: accountExisting.properties.consistencyPolicy
    locations: [for (region, idx) in orderedWriteRegions: {
      locationName: region
      failoverPriority: idx
      isZoneRedundant: isZoneRedundant
    }]
    databaseAccountOfferType: 'Standard'
    enableAutomaticFailover: systemManagedFailover
    enableMultipleWriteLocations: true
    disableKeyBasedMetadataWriteAccess: accountExisting.properties.disableKeyBasedMetadataWriteAccess
    publicNetworkAccess: accountExisting.properties.publicNetworkAccess
  }
}

output configuredWriteRegions array = orderedWriteRegions
output accountEndpoint string = 'https://${accountUpdate.name}.documents.azure.com:443/'
