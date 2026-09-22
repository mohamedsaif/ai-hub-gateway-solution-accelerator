/**
 * @module services/classic-llm-usage-container
 * @description [Classic AI Hub Gateway ONLY — pre Citadel Governance Hub]
 *              Provisions a single `llm-usage-container` (partition key `/productName`)
 *              inside an EXISTING Azure Cosmos DB (SQL API) account and database.
 *
 *              This module is additive and idempotent: it references the existing
 *              account and database by name and only creates the container. It NEVER
 *              changes the account network configuration (publicNetworkAccess,
 *              IP/VNet rules, private endpoints) or any other database/container.
 *
 * Scope: Resource Group (the RG that already contains the Cosmos DB account)
 */

targetScope = 'resourceGroup'

@description('Name of the EXISTING Cosmos DB account in which to provision the container.')
param cosmosDbAccountName string

@description('Name of the EXISTING Cosmos DB SQL database in which to provision the container.')
param databaseName string = 'ai-usage-db'

@description('Name of the LLM usage container to create.')
param containerName string = 'llm-usage-container'

@description('Partition key path for the LLM usage container.')
param partitionKeyPath string = '/productName'

@description('Throughput (RU/s) for the created container.')
@minValue(400)
@maxValue(1000000)
param throughput int = 400

resource account 'Microsoft.DocumentDB/databaseAccounts@2024-02-15-preview' existing = {
  name: toLower(cosmosDbAccountName)
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-02-15-preview' existing = {
  parent: account
  name: databaseName
}

resource llmUsageContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-02-15-preview' = {
  parent: database
  name: containerName
  properties: {
    resource: {
      id: containerName
      partitionKey: {
        paths: [ partitionKeyPath ]
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
}

@description('Name of the Cosmos DB account.')
output cosmosDbAccountName string = account.name

@description('Name of the Cosmos DB database.')
output cosmosDbDatabaseName string = databaseName

@description('Name of the provisioned LLM usage container.')
output llmUsageContainerName string = llmUsageContainer.name
