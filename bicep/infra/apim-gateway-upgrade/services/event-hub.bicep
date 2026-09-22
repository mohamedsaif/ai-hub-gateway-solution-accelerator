/**
 * @module services/event-hub
 * @description Create-or-bring-your-own Event Hubs namespace for the gateway usage pipeline.
 *              Always (idempotently) ensures the accelerator hubs and consumer groups exist:
 *                - ai-usage  (consumer groups: $Default, aiUsageIngestion)
 *                - pii-usage (consumer groups: $Default, piiUsageIngestion) — when PII enabled
 *
 *              For an EXISTING (BYO) namespace this module only ADDS the hubs/consumer groups.
 *              It NEVER changes the namespace network configuration (publicNetworkAccess,
 *              network rule sets, private endpoints).
 *
 * Scope: Resource Group
 */

targetScope = 'resourceGroup'

@description('Create a new Event Hubs namespace. When false, an existing namespace (BYO) is referenced by name.')
param createNew bool = true

@description('Name of the Event Hubs namespace to create or reference.')
param namespaceName string

@description('Location for the namespace (only used when createNew is true).')
param location string = resourceGroup().location

@description('Tags to apply (only used when createNew is true).')
param tags object = {}

@description('SKU for a newly created namespace.')
param sku string = 'Standard'

@description('Throughput / capacity units for a newly created namespace.')
param capacity int = 1

@description('Public network access for a newly created namespace. Ignored for BYO namespaces.')
@allowed(['Enabled', 'Disabled'])
param publicNetworkAccess string = 'Enabled'

@description('Name of the main usage event hub.')
param eventHubName string = 'ai-usage'

@description('Provision the PII usage event hub.')
param isPIIEnabled bool = true

@description('Name of the PII usage event hub.')
param eventHubNamePII string = 'pii-usage'

@description('Message retention in days for created hubs.')
param messageRetentionInDays int = 7

// ---------------------------------------------------------------------------
//  Private endpoint (created namespaces only)
// ---------------------------------------------------------------------------

@description('Create a private endpoint for a newly created namespace. Ignored for BYO namespaces.')
param usePrivateEndpoint bool = false

@description('Name of the Event Hub private endpoint (only used when usePrivateEndpoint is true).')
param eventHubPrivateEndpointName string = ''

@description('Name of the Virtual Network for the private endpoint.')
param vNetName string = ''

@description('Resource group containing the Virtual Network.')
param vNetRG string = resourceGroup().name

@description('Name of the private endpoint subnet.')
param privateEndpointSubnetName string = ''

@description('DNS zone name for the Event Hub private endpoint.')
param eventHubDnsZoneName string = 'privatelink.servicebus.windows.net'

@description('Direct DNS zone resource ID for the Event Hub private endpoint (preferred).')
param dnsZoneResourceId string = ''

resource eventHubNamespaceNew 'Microsoft.EventHub/namespaces@2024-01-01' = if (createNew) {
  name: namespaceName
  location: location
  tags: union(tags, { 'azd-service-name': namespaceName })
  sku: {
    name: sku
    tier: sku
    capacity: capacity
  }
  properties: {
    isAutoInflateEnabled: true
    maximumThroughputUnits: 20
    publicNetworkAccess: publicNetworkAccess
  }
}

resource eventHubNamespaceRef 'Microsoft.EventHub/namespaces@2024-01-01' existing = {
  name: namespaceName
}

resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = {
  parent: eventHubNamespaceRef
  name: eventHubName
  properties: {
    messageRetentionInDays: messageRetentionInDays
    partitionCount: 4
    status: 'Active'
  }
  dependsOn: [ eventHubNamespaceNew ]
}

resource eventHubPII 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = if (isPIIEnabled) {
  parent: eventHubNamespaceRef
  name: eventHubNamePII
  properties: {
    messageRetentionInDays: messageRetentionInDays
    partitionCount: 2
    status: 'Active'
  }
  dependsOn: [ eventHubNamespaceNew ]
}

resource defaultConsumerGroup 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2024-01-01' = {
  name: '$Default'
  parent: eventHub
}

resource aiUsageConsumerGroup 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2024-01-01' = {
  name: 'aiUsageIngestion'
  parent: eventHub
}

resource defaultPIIConsumerGroup 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2024-01-01' = if (isPIIEnabled) {
  name: '$Default'
  parent: eventHubPII
}

resource piiUsageConsumerGroup 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2024-01-01' = if (isPIIEnabled) {
  name: 'piiUsageIngestion'
  parent: eventHubPII
}

// Private endpoint (created namespaces only)
module privateEndpoint '../../modules/networking/private-endpoint.bicep' = if (createNew && usePrivateEndpoint) {
  name: '${namespaceName}-pe'
  params: {
    groupIds: [ 'namespace' ]
    dnsZoneName: eventHubDnsZoneName
    name: !empty(eventHubPrivateEndpointName) ? eventHubPrivateEndpointName : '${namespaceName}-pe'
    privateLinkServiceId: eventHubNamespaceRef.id
    location: location
    privateEndpointSubnetId: resourceId(vNetRG, 'Microsoft.Network/virtualNetworks/subnets', vNetName, privateEndpointSubnetName)
    dnsZoneResourceId: dnsZoneResourceId
    tags: tags
  }
  dependsOn: [ eventHubNamespaceNew ]
}

@description('Name of the Event Hubs namespace (created or existing).')
output eventHubNamespaceName string = namespaceName

@description('Name of the main usage event hub.')
output eventHubName string = eventHubName

@description('Name of the PII usage event hub (empty when PII disabled).')
output eventHubPIIName string = isPIIEnabled ? eventHubNamePII : ''

@description('Service Bus endpoint of the namespace.')
output eventHubEndpoint string = 'https://${namespaceName}.servicebus.windows.net:443/'

@description('Resource ID of the Event Hubs namespace.')
output eventHubResourceId string = eventHubNamespaceRef.id
