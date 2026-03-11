param name string
param location string = resourceGroup().location
param tags object = {}

@minLength(1)
param publisherEmail string = 'noreply@microsoft.com'

@minLength(1)
param publisherName string = 'n/a'

param sku string = 'Developer'
var isV2SKU = sku == 'StandardV2' || sku == 'PremiumV2'
param skuCount int = 1
param applicationInsightsName string

param managedIdentityName string
param clientAppId string = 'NA'
param tenantId string = tenant().tenantId
param audience string = 'https://cognitiveservices.azure.com/.default'
param eventHubName string
param eventHubEndpoint string

param eventHubPIIName string
param eventHubPIIEndpoint string

param enableAzureAISearch bool = false
param aiSearchInstances array

param enableAIModelInference bool = true

param enableOpenAIRealtime bool = true

param enableDocumentIntelligence bool = true

param enablePIIAnonymization bool = true

param contentSafetyServiceUrl string
param aiLanguageServiceUrl string


// Networking
param apimNetworkType string = 'External'
param apimSubnetId string

param apimV2PrivateDnsZoneName string = 'privatelink.azure-api.net'
param apimV2PrivateEndpointName string
param dnsZoneRG string = ''
param dnsSubscriptionId string = ''
param privateEndpointSubnetId string
param usePrivateEndpoint bool = false
param apimV2PublicNetworkAccess bool = true

// New parameter: Direct DNS zone resource ID (preferred over dnsZoneRG/dnsSubscriptionId)
param dnsZoneResourceId string = ''

// API Center Integration
param enableAPICenter bool = true
param apiCenterServiceName string
param apiCenterWorkspaceName string = 'default'
param apiCenterMCPEnvironment string = 'mcp-dev'
param apiCenterAPIEnvironment string = 'api-dev'

// MCP Samples (Weather API, Weather MCP, MS Learn MCP)
param isMCPSampleDeployed bool = false

/**
 * LLM Backend Configuration
 * This parameter defines all LLM backends and their supported models for dynamic routing.
 * Each backend can be:
 * - AI Foundry: Deployed Azure AI Foundry project with model deployments
 * - Azure OpenAI: Azure OpenAI service endpoints
 * - Other LLM providers: External LLM endpoints with appropriate authentication
 * 
 * Structure:
 * - backendId: Unique identifier for the backend (used in APIM backend resource name)
 * - backendType: Type of backend ('ai-foundry', 'azure-openai', 'external')
 * - endpoint: Base URL for the backend service
 * - authScheme: Authentication method ('managedIdentity', 'apiKey', 'token')
 * - supportedModels: Array of model names this backend can serve
 * - priority: (Optional) Priority for load balancing (1-5, default 1)
 * - weight: (Optional) Weight for load balancing (1-1000, default 1)
 */
@description('Configuration array for LLM backends supporting multiple providers and models')
param llmBackendConfig array = []

@description('Enable APIM cache configuration backed by Azure Managed Redis')
param enableRedisCache bool = false

@secure()
@description('Runtime connection string to the Azure Managed Redis instance (used for APIM caches).')
param redisCacheConnectionString string = ''

@description('Resource ID of the Azure Managed Redis instance (optional, used for traceability)')
param redisCacheResourceId string = ''

@description('APIM cache entity name for the Redis-backed cache')
param apimRedisCacheName string = 'redis-cache'

@description('Azure Monitor diagnostic log settings for inference APIs (frontend/backend request/response headers & body bytes, and LLM log settings).')
param azureMonitorLogSettings object = {
  frontend: {
    request:  { headers: [], body: { bytes: 0 } }
    response: { headers: [], body: { bytes: 0 } }
  }
  backend: {
    request:  { headers: [], body: { bytes: 0 } }
    response: { headers: [], body: { bytes: 0 } }
  }
  largeLanguageModel: {
    logs: 'enabled'
    requests:  { messages: 'all', maxSizeInBytes: 262144 }
    responses: { messages: 'all', maxSizeInBytes: 262144 }
  }
}

@description('Application Insights diagnostic log settings for inference APIs (headers to capture and body bytes).')
param appInsightsLogSettings object = {
  headers: [ 'Content-type', 'User-agent', 'x-ms-region', 'x-ratelimit-remaining-tokens', 'x-ratelimit-remaining-requests' ]
  body: { bytes: 0 }
}

@description('Enable an APIM backend that targets the AI Foundry embeddings endpoint')
param enableEmbeddingsBackend bool = false

@description('URL for the AI Foundry embeddings endpoint (should be /models/embeddings on the primary Foundry resource)')
param embeddingsBackendUrl string = ''

@description('APIM backend ID for the embeddings backend')
param embeddingsBackendId string = 'foundry-embeddings'

var apimPublicNetworkAccess = apimV2PublicNetworkAccess ? 'Enabled' : 'Disabled'

var openAiApiBackendId = 'openai-backend'
var openAiApiUamiNamedValue = 'uami-client-id'
var openAiApiClientNamedValue = 'client-id'
var openAiApiTenantNamedValue = 'tenant-id'
var openAiApiAudienceNamedValue = 'audience'

var apiManagementMinApiVersion = '2021-08-01'
var apiManagementMinApiVersionV2 = '2024-05-01'

// Add this variable near the top with other variables
// var apimZones = sku == 'Premium' && skuCount > 1 ? ['1','2','3'] : []
// Replace the existing apimZones variable
var apimZones = (sku == 'Premium' && skuCount > 1) ? (skuCount == 2 ? ['1','2'] : ['1','2','3']) : []

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' existing = {
  name: managedIdentityName
}

resource apimService 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: name
  location: location
  tags: union(tags, { 'azd-service-name': name })
  sku: {
    name: sku
    capacity: (sku == 'Consumption') ? 0 : ((sku == 'Developer') ? 1 : skuCount)
  }
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    virtualNetworkType: isV2SKU ? 'External' : apimNetworkType
    publicNetworkAccess: isV2SKU ? apimPublicNetworkAccess : 'Enabled'
    virtualNetworkConfiguration: apimNetworkType != 'None' || isV2SKU ? {
      subnetResourceId: apimSubnetId
    } : null
    apiVersionConstraint: {
      minApiVersion: isV2SKU? apiManagementMinApiVersionV2 : apiManagementMinApiVersion
    }
    // Custom properties are not supported for Consumption SKU
    customProperties: sku == 'Consumption' ? {} : {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_128_GCM_SHA256': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_256_CBC_SHA256': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_128_CBC_SHA256': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_256_CBC_SHA': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_128_CBC_SHA': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TripleDes168': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Ssl30': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Ssl30': 'false'
    }
  }
  zones: apimZones
}

module privateEndpoint '../networking/private-endpoint.bicep' = if (isV2SKU && usePrivateEndpoint) {
  name: '${name}-pe'
  params: {
    groupIds: [
      'Gateway'
    ]
    dnsZoneName: apimV2PrivateDnsZoneName
    name: apimV2PrivateEndpointName
    privateLinkServiceId: apimService.id
    location: location
    dnsZoneRG: dnsZoneRG
    privateEndpointSubnetId: privateEndpointSubnetId
    dnsSubId: dnsSubscriptionId
    dnsZoneResourceId: dnsZoneResourceId
  }
}

module apimAiSearchIndexApi './api.bicep' = if (enableAzureAISearch) {
  name: 'azure-ai-search-index-api'
  params: {
    serviceName: apimService.name
    apiName: 'azure-ai-search-index-api'
    path: 'search'
    apiRevision: '1'
    apiDispalyName: 'Azure AI Search Index API (index services)'
    subscriptionRequired: true
    subscriptionKeyName: 'api-key'
    openApiSpecification: loadTextContent('./ai-search-api/ai-search-index-2024-07-01-api-spec.json')
    apiDescription: 'Azure AI Search Index Client APIs'
    policyDocument: loadTextContent('./policies/ai-search-index-api-policy.xml')
    enableAPIDeployment: true
    enableAPIDiagnostics: false
  }
  dependsOn: [
    policyFragments
  ]
}

module apimOpenAIRealTimetApi './api.bicep' = if (enableOpenAIRealtime) {
  name: 'openai-realtime-ws-api'
  params: {
    serviceName: apimService.name
    apiName: 'openai-realtime-ws-api'
    path: 'openai/realtime'
    apiRevision: '1'
    apiDispalyName: 'Azure OpenAI Realtime API'
    subscriptionRequired: true
    subscriptionKeyName: 'api-key'
    openApiSpecification: 'NA'
    apiDescription: 'Access Azure OpenAI Realtime API for real-time voice and text conversion.'
    policyDocument: loadTextContent('./policies/openai-realtime-policy.xml')
    enableAPIDeployment: true
    serviceUrl: 'wss://to-be-replaced-by-policy'
    apiType: 'websocket'
    apiProtocols: ['wss']
    enableAPIDiagnostics: false
  }
  dependsOn: [
    policyFragments
  ]
}

module apimDocumentIntelligenceLegacy './api.bicep' = if (enableDocumentIntelligence) {
  name: 'document-intelligence-api-legacy'
  params: {
    serviceName: apimService.name
    apiName: 'document-intelligence-api-legacy'
    path: 'formrecognizer'
    apiRevision: '1'
    apiDispalyName: 'Document Intelligence API (Legacy)'
    subscriptionRequired: true
    subscriptionKeyName: 'Ocp-Apim-Subscription-Key'
    openApiSpecification: loadTextContent('./doc-intel-api/document-intelligence-2024-11-30-compressed.openapi.yaml')
    apiDescription: 'Uses (/formrecognizer) url path. Extracts content, layout, and structured data from documents.'
    policyDocument: loadTextContent('./policies/doc-intelligence-api-policy.xml')
    enableAPIDeployment: true
    enableAPIDiagnostics: false
  }
  dependsOn: [
    policyFragments
  ]
}

module apimDocumentIntelligence './api.bicep' = if (enableDocumentIntelligence) {
  name: 'document-intelligence-api'
  params: {
    serviceName: apimService.name
    apiName: 'document-intelligence-api'
    path: 'documentintelligence'
    apiRevision: '1'
    apiDispalyName: 'Document Intelligence API'
    subscriptionRequired: true
    subscriptionKeyName: 'Ocp-Apim-Subscription-Key'
    openApiSpecification: loadTextContent('./doc-intel-api/document-intelligence-2024-11-30-compressed.openapi.yaml')
    apiDescription: 'Uses (/documentintelligence) url path. Extracts content, layout, and structured data from documents.'
    policyDocument: loadTextContent('./policies/doc-intelligence-api-policy.xml')
    enableAPIDeployment: true
    enableAPIDiagnostics: false
  }
  dependsOn: [
    policyFragments
  ]
}

/**
 * Dynamic LLM Backend Creation
 * Creates individual backends for each LLM endpoint defined in llmBackendConfig
 * Supports AI Foundry, Azure OpenAI, and external LLM providers
 */
module llmBackends './llm-backends.bicep' = {
  name: 'llm-backends'
  params: {
    apimServiceName: apimService.name
    managedIdentityClientId: managedIdentity.properties.clientId
    llmBackendConfig: llmBackendConfig
    configureCircuitBreaker: true
    tags: tags
  }
}

/**
 * Dynamic Backend Pool Creation
 * Groups backends by supported models to enable load balancing and failover
 * Only creates pools for models supported by multiple backends
 */
module llmBackendPools './llm-backend-pools.bicep' = {
  name: 'llm-backend-pools'
  params: {
    apimServiceName: apimService.name
    backendDetails: llmBackends.outputs.backendDetails
    tags: tags
  }
}

/**
 * Dynamic LLM Policy Fragments
 * Generates policy fragments with backend pool configurations for routing logic
 * Updates set-backend-pools and set-backend-authorization fragments dynamically
 * Also generates get-available-models fragment with model metadata
 */
module llmPolicyFragments './llm-policy-fragments.bicep' =  {
  name: 'llm-policy-fragments'
  params: {
    apimServiceName: apimService.name
    policyFragmentConfig: llmBackendPools.outputs.policyFragmentConfig
    managedIdentityClientId: managedIdentity.properties.clientId
    llmBackendConfig: llmBackendConfig
  }
}

resource redisCache 'Microsoft.ApiManagement/service/caches@2024-06-01-preview' = if (enableRedisCache) {
  name: apimRedisCacheName
  parent: apimService
  properties: {
    connectionString: redisCacheConnectionString
    useFromLocation: 'default'
    description: 'Azure Managed Redis cache for APIM Semantic Cache'
  }
}

resource embeddingsBackend 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = if (enableEmbeddingsBackend) {
  name: embeddingsBackendId
  parent: apimService
  properties: {
    description: 'AI Foundry embeddings backend'
    url: embeddingsBackendUrl
    protocol: 'http'
    credentials: {
      managedIdentity: {
        clientId: managedIdentity.properties.clientId
        resource: 'https://cognitiveservices.azure.com'
      }
    }
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}

module apiUniversalLLM './inference-api.bicep' = {
  name: 'universal-llm-api'
  params: {
    apiManagementName: apimService.name
    inferenceAPIName: 'universal-llm-api'
    inferenceAPIPath: ''
    inferenceAPIType: 'AzureAI'
    inferenceAPIDisplayName: 'Universal LLM API'
    inferenceAPIDescription: 'Universal LLM API to route requests to different LLM providers including Azure OpenAI, AI Foundry and 3rd party models.'
    allowSubscriptionKey: true
    apimLoggerId: apimAzMonitorLogger.id
    policyXml: loadTextContent('./policies/universal-llm-api-policy-v2.xml')
    azureMonitorLogSettings: azureMonitorLogSettings
    appInsightsLogSettings: appInsightsLogSettings
  }
  dependsOn: [
    policyFragments
    llmBackends
    llmBackendPools
    llmPolicyFragments
  ]
}

module apimOpenaiApi './inference-api.bicep' = {
  name: 'azure-openai-api'
  params: {
    apiManagementName: apimService.name
    inferenceAPIName: 'azure-openai-api'
    inferenceAPIPath: ''
    inferenceAPIType: 'AzureOpenAI'
    inferenceAPIDisplayName: 'Azure OpenAI API'
    inferenceAPIDescription: 'Azure OpenAI API to route requests to different LLM providers including Azure OpenAI, AI Foundry and 3rd party models.'
    allowSubscriptionKey: true
    apimLoggerId: apimAzMonitorLogger.id
    policyXml: loadTextContent('./policies/azure-open-ai-api-policy.xml')
    azureMonitorLogSettings: azureMonitorLogSettings
    appInsightsLogSettings: appInsightsLogSettings
  }
  dependsOn: [
    policyFragments
    llmBackends
    llmBackendPools
    llmPolicyFragments
  ]
}

module unifiedAiGatewayApi './unified-ai-api.bicep' = {
  name: 'unified-ai-gateway-api'
  params: {
    apiManagementName: apimService.name
    apimLoggerId: apimAzMonitorLogger.id
    policyXml: loadTextContent('./policies/unified-ai-gateway-api-policy.xml')
    azureMonitorLogSettings: azureMonitorLogSettings
    appInsightsLogSettings: appInsightsLogSettings
  }
  dependsOn: [
    policyFragments
    llmBackends
    llmBackendPools
    llmPolicyFragments
  ]
}

////// AI Foundry Integration Requirements /////////////

// Typed resource reference for the Universal LLM API (created by module above)
resource universalLLMApi 'Microsoft.ApiManagement/service/apis@2022-08-01' existing = {
  name: 'universal-llm-api'
  parent: apimService
  dependsOn: [
    apiUniversalLLM
  ]
}

resource universalLlmDeploymentOperation 'Microsoft.ApiManagement/service/apis/operations@2022-08-01' existing = {
  name: 'deployments'
  parent: universalLLMApi
}

resource universalLlmDeploymentByNameOperation 'Microsoft.ApiManagement/service/apis/operations@2022-08-01' existing = {
  name: 'deployment-by-name'
  parent: universalLLMApi
}

resource openAIApi 'Microsoft.ApiManagement/service/apis@2022-08-01' existing = {
  name: 'azure-openai-api'
  parent: apimService
  dependsOn: [
    apimOpenaiApi
  ]
}

resource openAIDeploymentOperation 'Microsoft.ApiManagement/service/apis/operations@2022-08-01' existing = {
  name: 'deployments'
  parent: openAIApi
}

resource openAIDeploymentByNameOperation 'Microsoft.ApiManagement/service/apis/operations@2022-08-01' existing = {
  name: 'deployment-by-name'
  parent: openAIApi
}

resource universalLlmDeploymentOperationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2022-08-01' = {
  name: 'policy'
  parent: universalLlmDeploymentOperation
  properties: {
    format: 'rawxml'
    value: loadTextContent('./policies/universal-llm-api-deployments-policy.xml')
  }
}

resource universalLlmDeploymentByNameOperationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2022-08-01' = {
  name: 'policy'
  parent: universalLlmDeploymentByNameOperation
  properties: {
    format: 'rawxml'
    value: loadTextContent('./policies/universal-llm-api-deployment-by-name-policy.xml')
  }
}

resource openAIDeploymentOperationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2022-08-01' = {
  name: 'policy'
  parent: openAIDeploymentOperation
  properties: {
    format: 'rawxml'
    value: loadTextContent('./policies/universal-llm-api-deployments-policy.xml')
  }
}

resource openAIDeploymentByNameOperationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2022-08-01' = {
  name: 'policy'
  parent: openAIDeploymentByNameOperation
  properties: {
    format: 'rawxml'
    value: loadTextContent('./policies/universal-llm-api-deployment-by-name-policy.xml')
  }
}

// Unified AI Gateway API discovery operations
resource unifiedAiGatewayApiRef 'Microsoft.ApiManagement/service/apis@2022-08-01' existing = {
  name: 'unified-ai-gateway-api'
  parent: apimService
  dependsOn: [
    unifiedAiGatewayApi
  ]
}

resource unifiedAiDeploymentOperation 'Microsoft.ApiManagement/service/apis/operations@2022-08-01' existing = {
  name: 'deployments'
  parent: unifiedAiGatewayApiRef
}

resource unifiedAiDeploymentByNameOperation 'Microsoft.ApiManagement/service/apis/operations@2022-08-01' existing = {
  name: 'deployment-by-name'
  parent: unifiedAiGatewayApiRef
}

resource unifiedAiDeploymentOperationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2022-08-01' = {
  name: 'policy'
  parent: unifiedAiDeploymentOperation
  properties: {
    format: 'rawxml'
    value: loadTextContent('./policies/universal-llm-api-deployments-policy.xml')
  }
}

resource unifiedAiDeploymentByNameOperationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2022-08-01' = {
  name: 'policy'
  parent: unifiedAiDeploymentByNameOperation
  properties: {
    format: 'rawxml'
    value: loadTextContent('./policies/universal-llm-api-deployment-by-name-policy.xml')
  }
}

//////////// End of AI Foundry Integration Requirements /////////////

resource aiSearchBackends 'Microsoft.ApiManagement/service/backends@2022-08-01' = [for (aiSearchInstance, i) in aiSearchInstances: if(enableAzureAISearch) {
  name: aiSearchInstance.name
  parent: apimService
  properties: {
    description: aiSearchInstance.description
    url: aiSearchInstance.url
    protocol: 'http'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}]

resource contentSafetyBackend 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  name: 'content-safety-backend'
  parent: apimService
  properties: {
    description: 'Content Safety Service Backend'
    url: contentSafetyServiceUrl
    protocol: 'http'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
    credentials: {
      managedIdentity: {
        clientId: managedIdentity.properties.clientId
        resource: 'https://cognitiveservices.azure.com'
      }
    }
  }
}

resource apimOpenaiApiUamiNamedValue 'Microsoft.ApiManagement/service/namedValues@2022-08-01' = {
  name: openAiApiUamiNamedValue
  parent: apimService
  properties: {
    displayName: openAiApiUamiNamedValue
    secret: true
    value: managedIdentity.properties.clientId
  }
}

resource apiopenAiApiClientNamedValue 'Microsoft.ApiManagement/service/namedValues@2022-08-01' = {
  name: openAiApiClientNamedValue
  parent: apimService
  properties: {
    displayName: openAiApiClientNamedValue
    secret: true
    value: clientAppId
  }
}
resource apiopenAiApiTenantNamedValue 'Microsoft.ApiManagement/service/namedValues@2022-08-01' = {
  name: openAiApiTenantNamedValue
  parent: apimService
  properties: {
    displayName: openAiApiTenantNamedValue
    secret: true
    value: tenantId
  }
}
resource apimOpenaiApiAudienceNamedValue 'Microsoft.ApiManagement/service/namedValues@2022-08-01' =  {
  name: openAiApiAudienceNamedValue
  parent: apimService
  properties: {
    displayName: openAiApiAudienceNamedValue
    secret: true
    value: audience
  }
}

resource piiServiceUrlNamedValue 'Microsoft.ApiManagement/service/namedValues@2022-08-01' =  {
  name: 'piiServiceUrl'
  parent: apimService
  properties: {
    displayName: 'piiServiceUrl'
    secret: false
    value: aiLanguageServiceUrl
  }
}

resource piiServiceKeyNamedValue 'Microsoft.ApiManagement/service/namedValues@2022-08-01' =  {
  name: 'piiServiceKey'
  parent: apimService
  properties: {
    displayName: 'piiServiceKey'
    secret: true
    value: 'replace-with-language-service-key-if-needed'
  }
}

resource contentSafetyServiceUrlNamedValue 'Microsoft.ApiManagement/service/namedValues@2022-08-01' =  {
  name: 'contentSafetyServiceUrl'
  parent: apimService
  properties: {
    displayName: 'contentSafetyServiceUrl'
    secret: false
    value: contentSafetyServiceUrl
  }
}

// Policy Fragments Module
module policyFragments './policy-fragments.bicep' = {
  name: 'apim-policy-fragments'
  params: {
    apimServiceName: apimService.name
    enablePIIAnonymization: enablePIIAnonymization
    enableAIModelInference: enableAIModelInference
  }
  dependsOn: [
    apiopenAiApiClientNamedValue
    apimOpenaiApiAudienceNamedValue
    apiopenAiApiTenantNamedValue
    ehUsageLogger
    ehPIIUsageLogger
    piiServiceUrlNamedValue
    piiServiceKeyNamedValue
  ]
}

resource apimLogger 'Microsoft.ApiManagement/service/loggers@2024-05-01' = {
  name: 'appinsights-logger'
  parent: apimService
  properties: {
    credentials: {
      connectionString: applicationInsights.properties.ConnectionString
    }
    description: 'Application Insights logger for API observability'
    isBuffered: false
    loggerType: 'applicationInsights'
    resourceId: applicationInsights.id
  }
}

resource apimAzMonitorLogger 'Microsoft.ApiManagement/service/loggers@2024-10-01-preview' = {
  parent: apimService
  name: 'azuremonitor'
  properties: {
    loggerType: 'azureMonitor'
    isBuffered: false // Set to false to ensure logs are sent immediately
    description: 'Azure Monitor logger for Log Analytics'
  }
}

resource apimAppInsights 'Microsoft.ApiManagement/service/diagnostics@2024-05-01' = {
  parent: apimService
  name: 'applicationinsights'
  properties: {
    alwaysLog: 'allErrors'
    httpCorrelationProtocol: 'W3C'
    verbosity: 'information'
    logClientIp: true
    loggerId: apimLogger.id
    metrics: true
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    frontend: {
      request: {
        body: {
          bytes: 0
        }
      }
      response: {
        body: {
          bytes: 0
        }
      }
    }
    backend: {
      request: {
        body: {
          bytes: 0
        }
      }
      response: {
        body: {
          bytes: 0
        }
      }
    }
  }
}

resource ehUsageLogger 'Microsoft.ApiManagement/service/loggers@2022-08-01' = {
  name: 'usage-eventhub-logger'
  parent: apimService
  properties: {
    loggerType: 'azureEventHub'
    description: 'Event Hub logger for OpenAI usage metrics'
    credentials: {
      name: eventHubName
      endpointAddress: replace(eventHubEndpoint, 'https://', '')
      identityClientId: managedIdentity.properties.clientId
    }
  }
}

resource ehPIIUsageLogger 'Microsoft.ApiManagement/service/loggers@2022-08-01' = if (enablePIIAnonymization) {
  name: 'pii-usage-eventhub-logger'
  parent: apimService
  properties: {
    loggerType: 'azureEventHub'
    description: 'Event Hub logger for PII usage metrics and logs'
    credentials: {
      name: eventHubPIIName
      endpointAddress: replace(eventHubPIIEndpoint, 'https://', '')
      identityClientId: managedIdentity.properties.clientId
    }
  }
}

resource apimDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: apimService
  name: 'apimDiagnosticSettings'
  properties: {
    workspaceId: applicationInsights.properties.WorkspaceResourceId
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      {
        categoryGroup: 'AllLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// Sample MCP resources
module weatherAPI './api.bicep' = if (isMCPSampleDeployed) {
  name: 'weather-api'
  params: {
    serviceName: apimService.name
    apiName: 'weather-api'
    path: 'weather'
    apiRevision: '1'
    apiDispalyName: 'Weather API'
    subscriptionRequired: false
    subscriptionKeyName: 'api-key'
    openApiSpecification: loadTextContent('./sample/weather/openapi.json')
    apiDescription: 'Weather API for getting dynamic weather information for a given location.'
    policyDocument: loadTextContent('./sample/weather/policy.xml')
    enableAPIDeployment: true
    enableAPIDiagnostics: false
  }
  dependsOn: [
  ]
}

module weatherMCP './mcp-from-api.bicep' = if (isMCPSampleDeployed) {
  name: 'weather-mcp'
  params: {
    apimServiceName: apimService.name
    appInsightsLoggerName: 'appinsights-logger'
    apiName: 'weather-api'
    operationNames: ['get-weather']
    mcpPath: 'weather-mcp'
    mcpName: 'weather-mcp'
    mcpDisplayName: 'Weather MCP Development'
    mcpDescription: 'MCP server for weather data operations for given location (Development)'
  }
  dependsOn: [
    weatherAPI
    apimLogger
  ]
}

module microsoftLearnMCPServer 'mcp-existing.bicep' = if (isMCPSampleDeployed) {
  name: 'microsoftLearnMCPServer'
  params: {
    apimServiceName: apimService.name
    backendName: 'ms-learn-mcp-server'
    backendDescription: 'Microsoft Learn MCP Server'
    backendURL: 'https://learn.microsoft.com/api/mcp'
    mcpApiName: 'ms-learn-mcp'
    mcpDisplayName: 'Microsoft Learn MCP'
    mcpDescription: 'Microsoft Learn MCP Server'
    mcpPath: 'ms-learn-mcp'
    mcpPolicyXml: ''
  }
  dependsOn: [
    apimLogger
  ]
}

// ------------------
//    MCP API Center Onboarding
// ------------------

var weatherMCPCustomProperties = {
  Visibility: true
  Categories: ['AI/ML', 'Developer Tools']
  Vendor: 'Internal'
  Type: 'AI Gateway'
  Icon: 'https://cdn-icons-png.flaticon.com/512/1163/1163661.png'
}
module weatherMCPApiCenter './api-center-onboarding.bicep' = if (isMCPSampleDeployed && enableAPICenter) {
  name: 'weather-mcp-api-center'
  params: {
    apicServiceName: apiCenterServiceName
    apicWorkspaceName: apiCenterWorkspaceName
    environmentName: apiCenterMCPEnvironment
    apiName: 'weather-mcp'
    apiDisplayName: 'Weather MCP Development'
    apiDescription: 'MCP server for weather data operations for given location (Development)'
    apiKind: 'mcp'
    lifecycleStage: 'development'
    versionName: '1-0-0'
    versionDisplayName: '1.0.0'
    definitionName: 'weather-mcp-definition'
    definitionDisplayName: 'Weather MCP Definition'
    definitionDescription: 'Weather MCP Definition for version 1.0.0'
    deploymentName: 'weather-mcp-deployment'
    deploymentDisplayName: 'Weather MCP Deployment'
    deploymentDescription: 'Weather MCP Deployment for version 1.0.0 and environment Development'
    gatewayUrl: apimService.properties.gatewayUrl
    apiPath: 'weather-mcp'
    customProperties: weatherMCPCustomProperties
    documentationUrl: 'https://example.com/weather-mcp-docs'
  }
}

var microsoftLearnMCPProperties = {
  Visibility: true
  Categories: ['Developer Tools', 'Productivity']
  Vendor: 'Microsoft'
  Type: 'Remote'
  Icon: 'https://learn.microsoft.com/media/logos/logo-ms-social.png'
}
module microsoftLearnMCPApiCenter './api-center-onboarding.bicep' = if (isMCPSampleDeployed && enableAPICenter) {
  name: 'ms-learn-mcp-api-center'
  params: {
    apicServiceName: apiCenterServiceName
    apicWorkspaceName: apiCenterWorkspaceName
    environmentName: apiCenterMCPEnvironment
    apiName: 'ms-learn-mcp'
    apiDisplayName: 'Microsoft Learn MCP'
    apiDescription: 'Microsoft Learn MCP Server'
    apiKind: 'mcp'
    lifecycleStage: 'development'
    versionName: '1-0-0'
    versionDisplayName: '1.0.0'
    definitionName: 'ms-learn-mcp-definition'
    definitionDisplayName: 'Microsoft Learn MCP Definition'
    definitionDescription: 'Microsoft Learn MCP Definition for version 1.0.0'
    deploymentName: 'ms-learn-mcp-deployment'
    deploymentDisplayName: 'Microsoft Learn MCP Deployment'
    deploymentDescription: 'Microsoft Learn MCP Deployment for version 1.0.0 and environment development'
    gatewayUrl: apimService.properties.gatewayUrl
    apiPath: 'ms-learn-mcp'
    customProperties: microsoftLearnMCPProperties
    documentationUrl: 'https://learn.microsoft.com/mcp'
  }
}

// ------------------
//    API Center Onboarding - Regular APIs
// ------------------

var openAIApiCustomProperties = {
  Visibility: true
  Categories: ['AI/ML', 'OpenAI']
  Vendor: 'Microsoft'
  Type: 'AI Service'
  Icon: 'https://cdn.openai.com/API/logo-assets/openai-logo.svg'
}
module openAIApiCenter './api-center-onboarding.bicep' = if (enableAPICenter) {
  name: 'openai-api-center'
  params: {
    apicServiceName: apiCenterServiceName
    apicWorkspaceName: apiCenterWorkspaceName
    environmentName: apiCenterAPIEnvironment
    apiName: 'azure-openai-service-api'
    apiDisplayName: 'Azure OpenAI API'
    apiDescription: 'Azure OpenAI API for accessing GPT models and other AI capabilities'
    apiKind: 'REST'
    lifecycleStage: 'production'
    versionName: '1-0-0'
    versionDisplayName: '1.0.0'
    definitionName: 'azure-openai-service-api-definition'
    definitionDisplayName: 'Azure OpenAI API Definition'
    definitionDescription: 'Azure OpenAI API Definition for version 1.0.0'
    deploymentName: 'azure-openai-service-api-deployment'
    deploymentDisplayName: 'Azure OpenAI API Deployment'
    deploymentDescription: 'Azure OpenAI API Deployment for version 1.0.0'
    gatewayUrl: apimService.properties.gatewayUrl
    apiPath: 'openai'
    customProperties: openAIApiCustomProperties
    documentationUrl: 'https://learn.microsoft.com/azure/ai-services/openai/'
  }
}

var unifiedAiApiCustomProperties = {
  Visibility: true
  Categories: ['AI/ML', 'OpenAI', 'AI Foundry']
  Vendor: 'Microsoft'
  Type: 'AI Gateway'
  Icon: 'https://learn.microsoft.com/media/logos/logo-ms-social.png'
}
module unifiedAiApiCenter './api-center-onboarding.bicep' = if (enableAPICenter) {
  name: 'unified-ai-gateway-api-center'
  params: {
    apicServiceName: apiCenterServiceName
    apicWorkspaceName: apiCenterWorkspaceName
    environmentName: apiCenterAPIEnvironment
    apiName: 'unified-ai-gateway-api'
    apiDisplayName: 'Unified AI Gateway API'
    apiDescription: 'Unified AI Gateway API — single wildcard endpoint routing to any AI backend through the shared gateway pipeline'
    apiKind: 'REST'
    lifecycleStage: 'production'
    versionName: '1-0-0'
    versionDisplayName: '1.0.0'
    definitionName: 'unified-ai-gateway-api-definition'
    definitionDisplayName: 'Unified AI Gateway API Definition'
    definitionDescription: 'Unified AI Gateway API Definition for version 1.0.0'
    deploymentName: 'unified-ai-gateway-api-deployment'
    deploymentDisplayName: 'Unified AI Gateway API Deployment'
    deploymentDescription: 'Unified AI Gateway API Deployment for version 1.0.0'
    gatewayUrl: apimService.properties.gatewayUrl
    apiPath: 'unified-ai'
    customProperties: unifiedAiApiCustomProperties
    documentationUrl: 'https://learn.microsoft.com/azure/api-management/'
  }
}

var aiSearchCustomProperties = {
  Visibility: true
  Categories: ['AI/ML', 'Search']
  Vendor: 'Microsoft'
  Type: 'AI Service'
  Icon: 'https://learn.microsoft.com/media/logos/logo-ms-social.png'
}
module aiSearchApiCenter './api-center-onboarding.bicep' = if (enableAzureAISearch && enableAPICenter) {
  name: 'ai-search-api-center'
  params: {
    apicServiceName: apiCenterServiceName
    apicWorkspaceName: apiCenterWorkspaceName
    environmentName: apiCenterAPIEnvironment
    apiName: 'azure-ai-search-index-api'
    apiDisplayName: 'Azure AI Search Index API'
    apiDescription: 'Azure AI Search Index Client APIs for search operations'
    apiKind: 'REST'
    lifecycleStage: 'production'
    versionName: '1-0-0'
    versionDisplayName: '1.0.0'
    definitionName: 'azure-ai-search-index-api-definition'
    definitionDisplayName: 'Azure AI Search Index API Definition'
    definitionDescription: 'Azure AI Search Index API Definition for version 1.0.0'
    deploymentName: 'azure-ai-search-index-api-deployment'
    deploymentDisplayName: 'Azure AI Search Index API Deployment'
    deploymentDescription: 'Azure AI Search Index API Deployment for version 1.0.0'
    gatewayUrl: apimService.properties.gatewayUrl
    apiPath: 'search'
    customProperties: aiSearchCustomProperties
    documentationUrl: 'https://learn.microsoft.com/azure/search/'
  }
}

var aiModelInferenceCustomProperties = {
  Visibility: true
  Categories: ['AI/ML', 'Model Inference']
  Vendor: 'Microsoft'
  Type: 'AI Service'
  Icon: 'https://learn.microsoft.com/media/logos/logo-ms-social.png'
}
module aiModelInferenceApiCenter './api-center-onboarding.bicep' = if (enableAIModelInference && enableAPICenter) {
  name: 'ai-model-inference-api-center'
  params: {
    apicServiceName: apiCenterServiceName
    apicWorkspaceName: apiCenterWorkspaceName
    environmentName: apiCenterAPIEnvironment
    apiName: 'ai-model-inference-api'
    apiDisplayName: 'AI Model Inference API'
    apiDescription: 'Access to AI inference models published through Azure AI Foundry'
    apiKind: 'REST'
    lifecycleStage: 'production'
    versionName: '1-0-0'
    versionDisplayName: '1.0.0'
    definitionName: 'ai-model-inference-api-definition'
    definitionDisplayName: 'AI Model Inference API Definition'
    definitionDescription: 'AI Model Inference API Definition for version 1.0.0'
    deploymentName: 'ai-model-inference-api-deployment'
    deploymentDisplayName: 'AI Model Inference API Deployment'
    deploymentDescription: 'AI Model Inference API Deployment for version 1.0.0'
    gatewayUrl: apimService.properties.gatewayUrl
    apiPath: 'models'
    customProperties: aiModelInferenceCustomProperties
    documentationUrl: 'https://learn.microsoft.com/en-us/rest/api/aifoundry/modelinference/'
  }
}

var openAIRealtimeCustomProperties = {
  Visibility: true
  Categories: ['AI/ML', 'OpenAI', 'Real-time']
  Vendor: 'Microsoft'
  Type: 'AI Service'
  Icon: 'https://cdn.openai.com/API/logo-assets/openai-logo.svg'
}
module openAIRealtimeApiCenter './api-center-onboarding.bicep' = if (enableOpenAIRealtime && enableAPICenter) {
  name: 'openai-realtime-api-center'
  params: {
    apicServiceName: apiCenterServiceName
    apicWorkspaceName: apiCenterWorkspaceName
    environmentName: apiCenterAPIEnvironment
    apiName: 'openai-realtime-ws-api'
    apiDisplayName: 'Azure OpenAI Realtime API'
    apiDescription: 'Access Azure OpenAI Realtime API for real-time voice and text conversion'
    apiKind: 'websocket'
    lifecycleStage: 'production'
    versionName: '1-0-0'
    versionDisplayName: '1.0.0'
    definitionName: 'openai-realtime-ws-api-definition'
    definitionDisplayName: 'Azure OpenAI Realtime API Definition'
    definitionDescription: 'Azure OpenAI Realtime API Definition for version 1.0.0'
    deploymentName: 'openai-realtime-ws-api-deployment'
    deploymentDisplayName: 'Azure OpenAI Realtime API Deployment'
    deploymentDescription: 'Azure OpenAI Realtime API Deployment for version 1.0.0'
    gatewayUrl: apimService.properties.gatewayUrl
    apiPath: 'openai/realtime'
    customProperties: openAIRealtimeCustomProperties
    documentationUrl: 'https://learn.microsoft.com/en-us/azure/ai-foundry/openai/realtime-audio-quickstart?tabs=keyless%2Cwindows'
  }
}

var documentIntelligenceCustomProperties = {
  Visibility: true
  Categories: ['AI/ML', 'Document Processing']
  Vendor: 'Microsoft'
  Type: 'AI Service'
  Icon: 'https://learn.microsoft.com/media/logos/logo-ms-social.png'
}
module documentIntelligenceLegacyApiCenter './api-center-onboarding.bicep' = if (enableDocumentIntelligence && enableAPICenter) {
  name: 'doc-intel-legacy-api-center'
  params: {
    apicServiceName: apiCenterServiceName
    apicWorkspaceName: apiCenterWorkspaceName
    environmentName: apiCenterAPIEnvironment
    apiName: 'document-intelligence-api-legacy'
    apiDisplayName: 'Document Intelligence API (Legacy)'
    apiDescription: 'Uses /formrecognizer path. Extracts content, layout, and structured data from documents'
    apiKind: 'REST'
    lifecycleStage: 'deprecated'
    versionName: '1-0-0'
    versionDisplayName: '1.0.0'
    definitionName: 'document-intelligence-api-legacy-definition'
    definitionDisplayName: 'Document Intelligence API (Legacy) Definition'
    definitionDescription: 'Document Intelligence API (Legacy) Definition for version 1.0.0'
    deploymentName: 'document-intelligence-api-legacy-deployment'
    deploymentDisplayName: 'Document Intelligence API (Legacy) Deployment'
    deploymentDescription: 'Document Intelligence API (Legacy) Deployment for version 1.0.0'
    gatewayUrl: apimService.properties.gatewayUrl
    apiPath: 'formrecognizer'
    customProperties: documentIntelligenceCustomProperties
    documentationUrl: 'https://learn.microsoft.com/azure/ai-services/document-intelligence/'
  }
}

module documentIntelligenceApiCenter './api-center-onboarding.bicep' = if (enableDocumentIntelligence && enableAPICenter) {
  name: 'doc-intel-api-center'
  params: {
    apicServiceName: apiCenterServiceName
    apicWorkspaceName: apiCenterWorkspaceName
    environmentName: apiCenterAPIEnvironment
    apiName: 'document-intelligence-api'
    apiDisplayName: 'Document Intelligence API'
    apiDescription: 'Uses /documentintelligence path. Extracts content, layout, and structured data from documents'
    apiKind: 'REST'
    lifecycleStage: 'production'
    versionName: '1-0-0'
    versionDisplayName: '1.0.0'
    definitionName: 'document-intelligence-api-definition'
    definitionDisplayName: 'Document Intelligence API Definition'
    definitionDescription: 'Document Intelligence API Definition for version 1.0.0'
    deploymentName: 'document-intelligence-api-deployment'
    deploymentDisplayName: 'Document Intelligence API Deployment'
    deploymentDescription: 'Document Intelligence API Deployment for version 1.0.0'
    gatewayUrl: apimService.properties.gatewayUrl
    apiPath: 'documentintelligence'
    customProperties: documentIntelligenceCustomProperties
    documentationUrl: 'https://learn.microsoft.com/azure/ai-services/document-intelligence/'
  }
}

var universalLLMCustomProperties = {
  Visibility: true
  Categories: ['AI/ML', 'LLM', 'Multi-Provider']
  Vendor: 'Internal'
  Type: 'AI Gateway'
  Icon: 'https://learn.microsoft.com/media/logos/logo-ms-social.png'
}
module universalLLMApiCenter './api-center-onboarding.bicep' = if (enableAPICenter) {
  name: 'universal-llm-api-center'
  params: {
    apicServiceName: apiCenterServiceName
    apicWorkspaceName: apiCenterWorkspaceName
    environmentName: apiCenterAPIEnvironment
    apiName: 'universal-llm-api'
    apiDisplayName: 'Universal LLM API'
    apiDescription: 'Universal LLM API to route requests to different LLM providers including Azure OpenAI and AI Foundry'
    apiKind: 'REST'
    lifecycleStage: 'production'
    versionName: '1-0-0'
    versionDisplayName: '1.0.0'
    definitionName: 'universal-llm-api-definition'
    definitionDisplayName: 'Universal LLM API Definition'
    definitionDescription: 'Universal LLM API Definition for version 1.0.0'
    deploymentName: 'universal-llm-api-deployment'
    deploymentDisplayName: 'Universal LLM API Deployment'
    deploymentDescription: 'Universal LLM API Deployment for version 1.0.0'
    gatewayUrl: apimService.properties.gatewayUrl
    apiPath: 'llm'
    customProperties: universalLLMCustomProperties
    documentationUrl: 'https://github.com/mohamedsaif/ai-hub-gateway-solution-accelerator'
  }
}

var weatherAPICustomProperties = {
  Visibility: true
  Categories: ['Sample', 'Weather']
  Vendor: 'Internal'
  Type: 'Sample API'
  Icon: 'https://cdn-icons-png.flaticon.com/512/1163/1163661.png'
}
module weatherAPIApiCenter './api-center-onboarding.bicep' = if (isMCPSampleDeployed && enableAPICenter) {
  name: 'weather-api-center'
  params: {
    apicServiceName: apiCenterServiceName
    apicWorkspaceName: apiCenterWorkspaceName
    environmentName: apiCenterAPIEnvironment
    apiName: 'weather-api'
    apiDisplayName: 'Weather API'
    apiDescription: 'Weather API for getting dynamic weather information for a given location'
    apiKind: 'REST'
    lifecycleStage: 'development'
    versionName: '1-0-0'
    versionDisplayName: '1.0.0'
    definitionName: 'weather-api-definition'
    definitionDisplayName: 'Weather API Definition'
    definitionDescription: 'Weather API Definition for version 1.0.0'
    deploymentName: 'weather-api-deployment'
    deploymentDisplayName: 'Weather API Deployment'
    deploymentDescription: 'Weather API Deployment for version 1.0.0'
    gatewayUrl: apimService.properties.gatewayUrl
    apiPath: 'weather'
    customProperties: weatherAPICustomProperties
    documentationUrl: 'https://example.com/weather-api-docs'
  }
}

@description('The name of the deployed API Management service.')
output apimName string = apimService.name

@description('The path for the OpenAI API in the deployed API Management service.')
output apimOpenaiApiPath string = apimOpenaiApi.outputs.path

@description('Gateway URL for the deployed API Management resource.')
output apimGatewayUrl string = apimService.properties.gatewayUrl

output apimIdentityClientId string = apimService.identity.principalId
