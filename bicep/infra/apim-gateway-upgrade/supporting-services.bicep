/**
 * @module supporting-services
 * @description Provisions (or configures the existing) ecosystem of supporting services that the
 *              AI Hub Gateway / Citadel Governance Hub APIM depends on, so that an EXISTING APIM
 *              that was NOT created by the accelerator can be brought in line with it.
 *
 *              Services covered: user-assigned managed identities, monitoring (Log Analytics +
 *              Application Insights), Key Vault, Event Hub, Cosmos DB, primary AI Foundry (for
 *              Content Safety / PII / Language), Storage + usage-ingestion Logic App.
 *
 *              Design rules:
 *                - Master switch `provisionSupportingServices` gates the whole template.
 *                - Each service supports CREATE-NEW or BRING-YOUR-OWN (existing) via `create*` flags.
 *                - Networking is public by default; private endpoints are opt-in and apply ONLY to
 *                  newly created resources (`usePrivateEndpoints` + BYO VNet/DNS params).
 *                - For BYO/existing resources this template makes ONLY additive changes
 *                  (new Cosmos containers, new Event Hub hubs/consumer groups, named values, RBAC,
 *                  Foundry endpoint consumption). It NEVER changes the network configuration of an
 *                  existing APIM or an existing supporting service.
 *
 *              The outputs feed the companion `main.bicep` (APIM configuration upgrade).
 *
 * Scope: Resource Group
 */

targetScope = 'resourceGroup'

// =====================================================================
//    MASTER SWITCH
// =====================================================================

@description('Master switch. When false, this template is a no-op (no supporting services are created or configured).')
param provisionSupportingServices bool = false

@description('Location for newly created supporting services. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Tags applied to newly created resources.')
param tags object = {}

@description('Token used to generate default resource names when explicit names are not provided.')
param resourceToken string = toLower(uniqueString(resourceGroup().id))

var abbrs = loadJsonContent('../abbreviations.json')

// =====================================================================
//    NETWORKING (opt-in private endpoints — created resources only)
// =====================================================================

@description('Opt in to private endpoints for newly created supporting services. When false (default) created services use public network access. Existing/BYO services are never modified.')
param usePrivateEndpoints bool = false

@description('Name of an existing Virtual Network for private endpoints (required when usePrivateEndpoints is true).')
param vNetName string = ''

@description('Resource group of the existing Virtual Network. Defaults to the current resource group.')
param vNetRG string = resourceGroup().name

@description('Name of the existing private endpoint subnet (required when usePrivateEndpoints is true).')
param privateEndpointSubnetName string = ''

@description('Location of the existing Virtual Network. Defaults to the deployment location.')
param vNetLocation string = location

@description('Existing private DNS zone resource IDs for private endpoints (BYO network). Keys: keyVault, eventHub, cosmosDb, storageBlob, storageFile, aiServices (array of 3).')
param existingPrivateDnsZones object = {}

// =====================================================================
//    MANAGED IDENTITIES
// =====================================================================

@description('Create a new APIM user-assigned managed identity. Default false — the existing APIM identity is referenced (BYO).')
param createApimManagedIdentity bool = false

@description('Name of the APIM user-assigned managed identity (the identity already attached to the existing APIM when BYO).')
param apimManagedIdentityName string

@description('Create a new usage (Logic App) user-assigned managed identity.')
param createUsageManagedIdentity bool = true

@description('Name of the usage (Logic App) user-assigned managed identity. Leave blank for default naming.')
param usageManagedIdentityName string = ''

// =====================================================================
//    MONITORING
// =====================================================================

@description('Include monitoring (Log Analytics + Application Insights) in this deployment.')
param deployMonitoring bool = true

@description('Create a new Log Analytics workspace (false = BYO existing).')
param createLogAnalytics bool = true

@description('Name of the Log Analytics workspace to create. Leave blank for default naming.')
param logAnalyticsName string = ''

@description('Name of the existing Log Analytics workspace (when createLogAnalytics is false).')
param existingLogAnalyticsName string = ''

@description('Resource group of the existing Log Analytics workspace.')
param existingLogAnalyticsRG string = resourceGroup().name

@description('Subscription ID of the existing Log Analytics workspace.')
param existingLogAnalyticsSubscriptionId string = subscription().subscriptionId

@description('Create new Application Insights components (false = BYO existing).')
param createAppInsights bool = true

@description('Name of the APIM Application Insights component. Leave blank for default naming.')
param apimApplicationInsightsName string = ''

@description('Name of the Function/Logic App Application Insights component. Leave blank for default naming.')
param functionApplicationInsightsName string = ''

// =====================================================================
//    KEY VAULT
// =====================================================================

@description('Include Key Vault in this deployment.')
param deployKeyVault bool = true

@description('Create a new Key Vault (false = BYO existing).')
param createKeyVault bool = true

@description('Name of the Key Vault to create or reference. Leave blank for default naming.')
param keyVaultName string = ''

@description('Public network access for a newly created Key Vault.')
@allowed(['Enabled', 'Disabled'])
param keyVaultPublicNetworkAccess string = 'Enabled'

@description('Principal ID of the existing APIM system-assigned identity to grant Key Vault access (optional).')
param apimSystemAssignedPrincipalId string = ''

// =====================================================================
//    EVENT HUB
// =====================================================================

@description('Include Event Hub in this deployment.')
param deployEventHub bool = true

@description('Create a new Event Hubs namespace (false = BYO existing — only adds hubs/consumer groups).')
param createEventHub bool = true

@description('Name of the Event Hubs namespace to create or reference. Leave blank for default naming.')
param eventHubNamespaceName string = ''

@description('Public network access for a newly created Event Hubs namespace.')
@allowed(['Enabled', 'Disabled'])
param eventHubPublicNetworkAccess string = 'Enabled'

@description('Provision the PII usage event hub.')
param isPIIEnabled bool = true

// =====================================================================
//    COSMOS DB
// =====================================================================

@description('Include Cosmos DB in this deployment.')
param deployCosmosDb bool = true

@description('Create a new Cosmos DB account (false = BYO existing — only adds database/containers).')
param createCosmosDb bool = true

@description('Name of the Cosmos DB account to create or reference. Leave blank for default naming.')
param cosmosDbAccountName string = ''

@description('Public network access for a newly created Cosmos DB account.')
@allowed(['Enabled', 'Disabled'])
param cosmosDbPublicAccess string = 'Enabled'

@description('Cosmos DB container throughput (RU/s).')
param cosmosDbRUs int = 400

// =====================================================================
//    AI FOUNDRY (primary — Content Safety / PII / Language)
// =====================================================================

@description('Include AI Foundry in this deployment.')
param deployFoundry bool = true

@description('Create a new AI Foundry account (false = BYO existing — endpoint consumed for Content Safety / PII / Language).')
param createFoundry bool = true

@description('Name of the AI Foundry account to create or reference. Leave blank for default naming.')
param foundryName string = ''

@description('Location for a newly created AI Foundry account. Defaults to the deployment location.')
param foundryLocation string = location

@description('Public network access for a newly created AI Foundry account.')
@allowed(['Enabled', 'Disabled'])
param foundryPublicNetworkAccess string = 'Enabled'

@description('Add model deployments to the AI Foundry account (opt-in; default false = endpoint-only).')
param deployFoundryModels bool = false

@description('Model deployments configuration (used when deployFoundryModels is true). Each entry: name, publisher, version, sku, capacity.')
param foundryModelsConfig array = []

// =====================================================================
//    STORAGE + LOGIC APP (usage ingestion)
// =====================================================================

@description('Include the usage-ingestion Logic App (and its storage) in this deployment.')
param deployLogicApp bool = true

@description('Create a new Storage Account for the Logic App (false = BYO existing).')
param createStorage bool = true

@description('Name of the Storage Account to create or reference. Leave blank for default naming.')
param storageAccountName string = ''

@description('Name of the usage processing Logic App. Leave blank for default naming.')
param usageProcessingLogicAppName string = ''

@description('Name of the Logic App content file share.')
param logicContentShareName string = 'usage-logic-content'

@description('Logic App VNet integration subnet resource ID. Leave blank to run the Logic App over public networking.')
param logicAppSubnetId string = ''

// =====================================================================
//    RESOLVED NAMES
// =====================================================================

var resolvedUsageManagedIdentityName = !empty(usageManagedIdentityName) ? usageManagedIdentityName : '${abbrs.managedIdentityUserAssignedIdentities}logicapp-${resourceToken}'
var resolvedLogAnalyticsName = !empty(logAnalyticsName) ? logAnalyticsName : '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
var resolvedApimAppInsightsName = !empty(apimApplicationInsightsName) ? apimApplicationInsightsName : '${abbrs.insightsComponents}apim-${resourceToken}'
var resolvedFuncAppInsightsName = !empty(functionApplicationInsightsName) ? functionApplicationInsightsName : '${abbrs.insightsComponents}func-${resourceToken}'
var resolvedKeyVaultName = !empty(keyVaultName) ? keyVaultName : '${abbrs.keyVaultVaults}${resourceToken}'
var resolvedEventHubNamespaceName = !empty(eventHubNamespaceName) ? eventHubNamespaceName : '${abbrs.eventHubNamespaces}${resourceToken}'
var resolvedCosmosDbAccountName = !empty(cosmosDbAccountName) ? cosmosDbAccountName : '${abbrs.documentDBDatabaseAccounts}${resourceToken}'
var resolvedFoundryName = !empty(foundryName) ? foundryName : '${abbrs.cognitiveServicesAccounts}foundry-${resourceToken}'
var resolvedStorageAccountName = !empty(storageAccountName) ? storageAccountName : 'funcusage${resourceToken}'
var resolvedLogicAppName = !empty(usageProcessingLogicAppName) ? usageProcessingLogicAppName : '${abbrs.logicWorkflows}usage-${resourceToken}'

var aiServicesDnsZoneResourceIds = existingPrivateDnsZones.?aiServices ?? []

// =====================================================================
//    MANAGED IDENTITIES
// =====================================================================

module apimManagedIdentity 'services/managed-identity.bicep' = if (provisionSupportingServices) {
  name: 'ss-apim-managed-identity'
  params: {
    createNew: createApimManagedIdentity
    name: apimManagedIdentityName
    location: location
    tags: tags
    assignCognitiveServicesUser: createApimManagedIdentity
    assignCognitiveServicesOpenAIUser: createApimManagedIdentity
    assignEventHubsDataSender: createApimManagedIdentity
  }
}

module usageManagedIdentity 'services/managed-identity.bicep' = if (provisionSupportingServices && deployLogicApp) {
  name: 'ss-usage-managed-identity'
  params: {
    createNew: createUsageManagedIdentity
    name: resolvedUsageManagedIdentityName
    location: location
    tags: tags
    assignEventHubsDataOwner: true
  }
}

// =====================================================================
//    MONITORING
// =====================================================================

module monitoring 'services/monitoring.bicep' = if (provisionSupportingServices && deployMonitoring) {
  name: 'ss-monitoring'
  params: {
    location: location
    tags: tags
    createLogAnalytics: createLogAnalytics
    logAnalyticsName: resolvedLogAnalyticsName
    existingLogAnalyticsName: existingLogAnalyticsName
    existingLogAnalyticsRG: existingLogAnalyticsRG
    existingLogAnalyticsSubscriptionId: existingLogAnalyticsSubscriptionId
    createAppInsights: createAppInsights
    apimApplicationInsightsName: resolvedApimAppInsightsName
    functionApplicationInsightsName: resolvedFuncAppInsightsName
  }
}

// =====================================================================
//    EVENT HUB
// =====================================================================

module eventHub 'services/event-hub.bicep' = if (provisionSupportingServices && deployEventHub) {
  name: 'ss-event-hub'
  params: {
    createNew: createEventHub
    namespaceName: resolvedEventHubNamespaceName
    location: location
    tags: tags
    publicNetworkAccess: eventHubPublicNetworkAccess
    isPIIEnabled: isPIIEnabled
    usePrivateEndpoint: usePrivateEndpoints
    vNetName: vNetName
    vNetRG: vNetRG
    privateEndpointSubnetName: privateEndpointSubnetName
    dnsZoneResourceId: existingPrivateDnsZones.?eventHub ?? ''
  }
}

// =====================================================================
//    COSMOS DB
// =====================================================================

module cosmosDb 'services/cosmos-db.bicep' = if (provisionSupportingServices && deployCosmosDb) {
  name: 'ss-cosmos-db'
  params: {
    createNew: createCosmosDb
    accountName: resolvedCosmosDbAccountName
    location: location
    tags: tags
    publicAccess: cosmosDbPublicAccess
    throughput: cosmosDbRUs
    usePrivateEndpoint: usePrivateEndpoints
    vNetName: vNetName
    vNetRG: vNetRG
    privateEndpointSubnetName: privateEndpointSubnetName
    dnsZoneResourceId: existingPrivateDnsZones.?cosmosDb ?? ''
  }
}

module usageCosmosSqlRole '../modules/cosmos-db/cosmos-sql-role-assignment.bicep' = if (provisionSupportingServices && deployCosmosDb && deployLogicApp) {
  name: 'ss-usage-cosmos-sql-role'
  params: {
    #disable-next-line BCP318
    cosmosDbAccountName: cosmosDb.outputs.cosmosDbAccountName
    #disable-next-line BCP318
    principalId: usageManagedIdentity.outputs.managedIdentityPrincipalId
  }
}

// =====================================================================
//    AI FOUNDRY
// =====================================================================

module foundry 'services/foundry.bicep' = if (provisionSupportingServices && deployFoundry) {
  name: 'ss-foundry'
  params: {
    createNew: createFoundry
    foundryName: resolvedFoundryName
    location: foundryLocation
    tags: tags
    publicNetworkAccess: foundryPublicNetworkAccess
    #disable-next-line BCP318
    apimPrincipalId: apimManagedIdentity.outputs.managedIdentityPrincipalId
    deployModels: deployFoundryModels
    modelsConfig: foundryModelsConfig
    usePrivateEndpoint: usePrivateEndpoints
    vNetName: vNetName
    vNetLocation: vNetLocation
    vNetRG: vNetRG
    privateEndpointSubnetName: privateEndpointSubnetName
    dnsZoneResourceIds: aiServicesDnsZoneResourceIds
  }
}

// =====================================================================
//    KEY VAULT (after APIM identity + Foundry for RBAC)
// =====================================================================

module keyVault 'services/key-vault.bicep' = if (provisionSupportingServices && deployKeyVault) {
  name: 'ss-key-vault'
  params: {
    createNew: createKeyVault
    keyVaultName: resolvedKeyVaultName
    location: location
    tags: tags
    publicNetworkAccess: keyVaultPublicNetworkAccess
    usePrivateEndpoint: usePrivateEndpoints
    vNetName: vNetName
    vNetRG: vNetRG
    privateEndpointSubnetName: privateEndpointSubnetName
    dnsZoneResourceId: existingPrivateDnsZones.?keyVault ?? ''
    #disable-next-line BCP318
    apimPrincipalId: apimManagedIdentity.outputs.managedIdentityPrincipalId
    apimSystemAssignedPrincipalId: apimSystemAssignedPrincipalId
    #disable-next-line BCP318
    aiFoundryPrincipalIds: (provisionSupportingServices && deployFoundry && createFoundry) ? [ foundry.outputs.foundryPrincipalId ] : []
  }
}

// =====================================================================
//    STORAGE + LOGIC APP
// =====================================================================

module storage 'services/storage.bicep' = if (provisionSupportingServices && deployLogicApp) {
  name: 'ss-storage'
  params: {
    createNew: createStorage
    storageAccountName: resolvedStorageAccountName
    location: location
    tags: tags
    publicNetworkAccess: usePrivateEndpoints ? 'Disabled' : 'Enabled'
    logicContentShareName: logicContentShareName
    #disable-next-line BCP318
    functionAppManagedIdentityName: usageManagedIdentity.outputs.managedIdentityName
    usePrivateEndpoint: usePrivateEndpoints
    vNetName: vNetName
    vNetRG: vNetRG
    privateEndpointSubnetName: privateEndpointSubnetName
    storageBlobDnsZoneResourceId: existingPrivateDnsZones.?storageBlob ?? ''
    storageFileDnsZoneResourceId: existingPrivateDnsZones.?storageFile ?? ''
  }
}

module logicApp 'services/logic-app.bicep' = if (provisionSupportingServices && deployLogicApp) {
  name: 'ss-logic-app'
  params: {
    logicAppName: resolvedLogicAppName
    location: location
    tags: tags
    #disable-next-line BCP318
    storageAccountName: storage.outputs.storageAccountName
    fileShareName: logicContentShareName
    #disable-next-line BCP318
    applicationInsightsName: monitoring.outputs.funcApplicationInsightsName
    #disable-next-line BCP318
    apimAppInsightsName: monitoring.outputs.apimApplicationInsightsName
    #disable-next-line BCP318
    cosmosDbAccountName: cosmosDb.outputs.cosmosDbAccountName
    #disable-next-line BCP318
    cosmosDBDatabaseName: cosmosDb.outputs.cosmosDbDatabaseName
    #disable-next-line BCP318
    cosmosDBContainerConfigName: cosmosDb.outputs.cosmosDbStreamingExportConfigContainerName
    #disable-next-line BCP318
    cosmosDBContainerUsageName: cosmosDb.outputs.cosmosDbContainerName
    #disable-next-line BCP318
    cosmosDBContainerPIIName: cosmosDb.outputs.cosmosDbPiiUsageContainerName
    #disable-next-line BCP318
    cosmosDBContainerLLMUsageName: cosmosDb.outputs.cosmosDbLLMUsageContainerName
    #disable-next-line BCP318
    cosmosDBContainerMCPUsageName: cosmosDb.outputs.cosmosDbMcpUsageContainerName
    #disable-next-line BCP318
    cosmosDBContainerAgentUsageName: cosmosDb.outputs.cosmosDbAgentUsageContainerName
    #disable-next-line BCP318
    eventHubNamespaceName: eventHub.outputs.eventHubNamespaceName
    #disable-next-line BCP318
    eventHubName: eventHub.outputs.eventHubName
    #disable-next-line BCP318
    eventHubPIIName: eventHub.outputs.eventHubPIIName
    functionAppSubnetId: logicAppSubnetId
  }
  dependsOn: [
    usageCosmosSqlRole
  ]
}

// =====================================================================
//    OUTPUTS — feed the companion main.bicep (APIM configuration upgrade)
// =====================================================================

@description('Name of the APIM user-assigned managed identity (created or existing).')
output managedIdentityName string = apimManagedIdentityName

@description('AI Foundry endpoint to use as APIM Content Safety backend and PII / Language named-value URL.')
#disable-next-line BCP318
output foundryEndpoint string = (provisionSupportingServices && deployFoundry) ? foundry.outputs.foundryEndpoint : ''

@description('Key Vault name (created or existing).')
#disable-next-line BCP318
output keyVaultName string = (provisionSupportingServices && deployKeyVault) ? keyVault.outputs.keyVaultName : ''

@description('Event Hub namespace name (created or existing).')
#disable-next-line BCP318
output eventHubNamespaceName string = (provisionSupportingServices && deployEventHub) ? eventHub.outputs.eventHubNamespaceName : ''

@description('Main usage event hub name.')
#disable-next-line BCP318
output eventHubName string = (provisionSupportingServices && deployEventHub) ? eventHub.outputs.eventHubName : ''

@description('PII usage event hub name.')
#disable-next-line BCP318
output eventHubPIIName string = (provisionSupportingServices && deployEventHub) ? eventHub.outputs.eventHubPIIName : ''

@description('Event Hub service bus endpoint.')
#disable-next-line BCP318
output eventHubEndpoint string = (provisionSupportingServices && deployEventHub) ? eventHub.outputs.eventHubEndpoint : ''

@description('Cosmos DB account name (created or existing).')
#disable-next-line BCP318
output cosmosDbAccountName string = (provisionSupportingServices && deployCosmosDb) ? cosmosDb.outputs.cosmosDbAccountName : ''
