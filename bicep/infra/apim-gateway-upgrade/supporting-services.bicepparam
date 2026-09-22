using './supporting-services.bicep'

// =====================================================================
//    SUPPORTING SERVICES — gateway ecosystem provisioning / configuration
// ---------------------------------------------------------------------
//    Provision (or configure existing) the services the Citadel Governance
//    Hub / AI Hub Gateway APIM depends on, so an EXISTING APIM that was NOT
//    created by the accelerator can be brought in line with it.
//
//    Run this BEFORE main.bicep (the APIM configuration upgrade) and feed the
//    outputs (foundryEndpoint, eventHub/cosmos names, managedIdentityName) into
//    main.bicepparam.
//
//    IMPORTANT: For any BRING-YOUR-OWN (existing) service, this template makes
//    ONLY additive changes (new Cosmos containers, new Event Hub hubs/consumer
//    groups, RBAC). It NEVER changes the network configuration of the existing
//    APIM or any existing supporting service.
// =====================================================================

// ---- Master switch -------------------------------------------------
// Set to true to provision / configure supporting services.
param provisionSupportingServices = true

param tags = {
  'azd-env-name': 'citadel-gateway-upgrade'
  SecurityControl: 'Ignore'
}

// ---- Networking ----------------------------------------------------
// Public access by default. To enable private endpoints for NEWLY created
// services, set usePrivateEndpoints = true and supply the existing VNet /
// subnet, plus DNS zone resource IDs in existingPrivateDnsZones.
param usePrivateEndpoints = false
param vNetName = ''
param vNetRG = ''
param privateEndpointSubnetName = ''
param existingPrivateDnsZones = {
  // keyVault:     '/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net'
  // eventHub:     '/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/privateDnsZones/privatelink.servicebus.windows.net'
  // cosmosDb:     '/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.com'
  // storageBlob:  '/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net'
  // storageFile:  '/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net'
  // aiServices: [
  //   '/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com'
  //   '/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com'
  //   '/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com'
  // ]
}

// ---- Managed identities --------------------------------------------
// The APIM identity is normally the one ALREADY attached to your existing APIM
// (BYO). Provide its name; leave createApimManagedIdentity = false.
param createApimManagedIdentity = false
param apimManagedIdentityName = '<your-existing-apim-managed-identity-name>'

param createUsageManagedIdentity = true
param usageManagedIdentityName = ''

// ---- Monitoring ----------------------------------------------------
param deployMonitoring = true
param createLogAnalytics = true
param logAnalyticsName = ''
// To BYO an existing Log Analytics workspace:
// param createLogAnalytics = false
// param existingLogAnalyticsName = '<existing-law-name>'
// param existingLogAnalyticsRG = '<existing-law-rg>'
param createAppInsights = true
param apimApplicationInsightsName = ''
param functionApplicationInsightsName = ''

// ---- Key Vault -----------------------------------------------------
param deployKeyVault = true
param createKeyVault = true
param keyVaultName = ''
param keyVaultPublicNetworkAccess = 'Enabled'
// Optional: grant the existing APIM system-assigned identity Key Vault access.
param apimSystemAssignedPrincipalId = ''

// ---- Event Hub -----------------------------------------------------
param deployEventHub = true
param createEventHub = true          // false = add hubs/consumer groups to an existing namespace
param eventHubNamespaceName = ''
param eventHubPublicNetworkAccess = 'Enabled'
param isPIIEnabled = true

// ---- Cosmos DB -----------------------------------------------------
param deployCosmosDb = true
param createCosmosDb = true          // false = add database/containers to an existing account
param cosmosDbAccountName = ''
param cosmosDbPublicAccess = 'Enabled'
param cosmosDbRUs = 400

// ---- AI Foundry (Content Safety / PII / Language) ------------------
param deployFoundry = true
param createFoundry = true           // false = consume an existing Foundry endpoint only
param foundryName = ''
param foundryPublicNetworkAccess = 'Enabled'
param deployFoundryModels = false    // opt-in: add model deployments to the Foundry account
param foundryModelsConfig = [
  // { name: 'gpt-4o-mini', publisher: 'OpenAI', version: '2024-07-18', sku: 'GlobalStandard', capacity: 100 }
  // { name: 'text-embedding-3-large', publisher: 'OpenAI', version: '1', sku: 'GlobalStandard', capacity: 100 }
]

// ---- Storage + usage-ingestion Logic App ---------------------------
param deployLogicApp = true
param createStorage = true
param storageAccountName = ''
param usageProcessingLogicAppName = ''
param logicContentShareName = 'usage-logic-content'
// For VNet-integrated Logic App, supply the function/logic app subnet resource ID.
param logicAppSubnetId = ''
