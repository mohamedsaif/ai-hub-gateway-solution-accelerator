targetScope = 'subscription'

@description('Gateway implementations to link for globally replicated usage data. Minimum two.')
@minLength(2)
param gatewayImplementations array

@description('Extra Azure regions to include as writable regions in addition to implementation regions.')
param additionalWriteRegions array = []

@description('Enable Cosmos DB automatic failover across the configured regions.')
param systemManagedFailover bool = true

@description('Override zone redundancy flag per region in the locations block.')
param isZoneRedundant bool = false

var implementationRegions = [for g in gatewayImplementations: g.region]
var globalWriteRegions = union(implementationRegions, additionalWriteRegions)

module multiMasterLink 'modules/cosmos-global-multi-master-link.bicep' = [for (gateway, i) in gatewayImplementations: {
  name: 'cosmos-mm-link-${i}-${uniqueString(gateway.subscriptionId, gateway.resourceGroupName, gateway.cosmosDbAccountName)}'
  scope: resourceGroup(gateway.subscriptionId, gateway.resourceGroupName)
  params: {
    accountName: gateway.cosmosDbAccountName
    primaryRegion: gateway.region
    writeRegions: globalWriteRegions
    systemManagedFailover: systemManagedFailover
    isZoneRedundant: isZoneRedundant
  }
}]

output globalWriteRegions array = globalWriteRegions

output linkedGateways array = [for (gateway, i) in gatewayImplementations: {
  implementationName: gateway.?name ?? 'gateway-${i + 1}'
  subscriptionId: gateway.subscriptionId
  resourceGroupName: gateway.resourceGroupName
  cosmosDbAccountName: gateway.cosmosDbAccountName
  primaryRegion: gateway.region
  configuredWriteRegions: multiMasterLink[i].outputs.configuredWriteRegions
  accountEndpoint: multiMasterLink[i].outputs.accountEndpoint
}]
