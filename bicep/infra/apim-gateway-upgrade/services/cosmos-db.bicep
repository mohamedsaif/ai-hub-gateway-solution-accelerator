/**
 * @module services/cosmos-db
 * @description Create-or-bring-your-own Azure Cosmos DB (SQL API) account for the usage pipeline.
 *              Always (idempotently) ensures the accelerator database and containers exist:
 *                - ai-usage-db
 *                  - ai-usage-container          (/productName)
 *                  - pii-usage-container         (/type)
 *                  - llm-usage-container         (/productName)
 *                  - model-pricing               (/model)
 *                  - streaming-export-config     (/type)
 *
 *              For an EXISTING (BYO) account this module only ADDS the database/containers.
 *              It NEVER changes the account network configuration (publicNetworkAccess,
 *              IP/VNet rules, private endpoints).
 *
 * Scope: Resource Group
 */

targetScope = 'resourceGroup'

@description('Create a new Cosmos DB account. When false, an existing account (BYO) is referenced by name.')
param createNew bool = true

@description('Name of the Cosmos DB account to create or reference.')
param accountName string

@description('Location for the account (only used when createNew is true).')
param location string = resourceGroup().location

@description('Tags to apply (only used when createNew is true).')
param tags object = {}

@description('Public network access for a newly created account. Ignored for BYO accounts.')
@allowed(['Enabled', 'Disabled'])
param publicAccess string = 'Enabled'

@description('Throughput (RU/s) for created containers.')
@minValue(400)
@maxValue(1000000)
param throughput int = 400

@description('Database name.')
param databaseName string = 'ai-usage-db'

@description('Main usage container name.')
param containerName string = 'ai-usage-container'

@description('PII usage container name.')
param piiUsageContainerName string = 'pii-usage-container'

@description('LLM usage container name.')
param llmUsageContainerName string = 'llm-usage-container'

@description('Published Tools (MCP) usage container name.')
param mcpUsageContainerName string = 'mcp-usage-container'

@description('Published Agents (A2A) usage container name.')
param agentUsageContainerName string = 'agent-usage-container'

@description('Model pricing container name.')
param pricingContainerName string = 'model-pricing'

@description('Streaming export config container name.')
param streamingExportConfigContainerName string = 'streaming-export-config'

// ---------------------------------------------------------------------------
//  Private endpoint (created accounts only)
// ---------------------------------------------------------------------------

@description('Create a private endpoint for a newly created account. Ignored for BYO accounts.')
param usePrivateEndpoint bool = false

@description('Name of the Cosmos DB private endpoint (only used when usePrivateEndpoint is true).')
param cosmosPrivateEndpointName string = ''

@description('Name of the Virtual Network for the private endpoint.')
param vNetName string = ''

@description('Resource group containing the Virtual Network.')
param vNetRG string = resourceGroup().name

@description('Name of the private endpoint subnet.')
param privateEndpointSubnetName string = ''

@description('DNS zone name for the Cosmos DB private endpoint.')
param cosmosDnsZoneName string = 'privatelink.documents.azure.com'

@description('Direct DNS zone resource ID for the Cosmos DB private endpoint (preferred).')
param dnsZoneResourceId string = ''

var partitionKeys = {
  '${containerName}': '/productName'
  '${piiUsageContainerName}': '/type'
  '${llmUsageContainerName}': '/productName'
  '${mcpUsageContainerName}': '/productName'
  '${agentUsageContainerName}': '/productName'
  '${pricingContainerName}': '/model'
  '${streamingExportConfigContainerName}': '/type'
}

var containerNames = [
  containerName
  piiUsageContainerName
  llmUsageContainerName
  mcpUsageContainerName
  agentUsageContainerName
  pricingContainerName
  streamingExportConfigContainerName
]

resource accountNew 'Microsoft.DocumentDB/databaseAccounts@2024-02-15-preview' = if (createNew) {
  name: toLower(accountName)
  location: location
  tags: union(tags, { 'azd-service-name': accountName })
  kind: 'GlobalDocumentDB'
  properties: {
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    databaseAccountOfferType: 'Standard'
    enableAutomaticFailover: true
    disableKeyBasedMetadataWriteAccess: true
    publicNetworkAccess: publicAccess
  }
}

resource accountRef 'Microsoft.DocumentDB/databaseAccounts@2024-02-15-preview' existing = {
  name: toLower(accountName)
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-02-15-preview' = {
  parent: accountRef
  name: databaseName
  properties: {
    resource: {
      id: databaseName
    }
  }
  dependsOn: [ accountNew ]
}

resource containers 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-02-15-preview' = [for name in containerNames: {
  parent: database
  name: name
  properties: {
    resource: {
      id: name
      partitionKey: {
        paths: [ partitionKeys[name] ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
      }
    }
    options: {
      throughput: throughput
    }
  }
}]

// Private endpoint (created accounts only)
module privateEndpoint '../../modules/networking/private-endpoint.bicep' = if (createNew && usePrivateEndpoint) {
  name: '${accountName}-pe'
  params: {
    groupIds: [ 'sql' ]
    dnsZoneName: cosmosDnsZoneName
    name: !empty(cosmosPrivateEndpointName) ? cosmosPrivateEndpointName : '${accountName}-pe'
    privateLinkServiceId: accountRef.id
    location: location
    privateEndpointSubnetId: resourceId(vNetRG, 'Microsoft.Network/virtualNetworks/subnets', vNetName, privateEndpointSubnetName)
    dnsZoneResourceId: dnsZoneResourceId
    tags: tags
  }
  dependsOn: [ accountNew ]
}

@description('Name of the Cosmos DB account (created or existing).')
output cosmosDbAccountName string = toLower(accountName)

@description('Name of the database.')
output cosmosDbDatabaseName string = databaseName

@description('Main usage container name.')
output cosmosDbContainerName string = containerName

@description('PII usage container name.')
output cosmosDbPiiUsageContainerName string = piiUsageContainerName

@description('LLM usage container name.')
output cosmosDbLLMUsageContainerName string = llmUsageContainerName

@description('Published Tools (MCP) usage container name.')
output cosmosDbMcpUsageContainerName string = mcpUsageContainerName

@description('Published Agents (A2A) usage container name.')
output cosmosDbAgentUsageContainerName string = agentUsageContainerName

@description('Streaming export config container name.')
output cosmosDbStreamingExportConfigContainerName string = streamingExportConfigContainerName

@description('Cosmos DB account endpoint.')
output cosmosDbEndpoint string = 'https://${toLower(accountName)}.documents.azure.com:443/'
