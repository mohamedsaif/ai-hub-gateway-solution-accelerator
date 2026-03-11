/*
 * @module llm-policy-fragments
 * @description Generates APIM policy fragments with backend pool configurations
 * 
 * This module creates policy fragments that contain the dynamically generated
 * backend pool configurations based on the LLM backend setup. These fragments
 * are used by the Universal LLM API policy to route requests appropriately.
 */

// ------------------
//    PARAMETERS
// ------------------

@description('Name of the API Management service')
param apimServiceName string

@description('Policy fragment configuration from backend pools module')
param policyFragmentConfig object

@description('User-assigned managed identity client ID for authentication')
param managedIdentityClientId string

@description('LLM backend configuration with model metadata for available models response')
param llmBackendConfig array = []

// ------------------
//    VARIABLES
// ------------------

// Combine backend pools and direct backends for unified routing
var allPools = union(policyFragmentConfig.backendPools, policyFragmentConfig.directBackends)

// Generate C# code for each backend pool with unique variable names
var backendPoolsArray = [for (pool, index) in allPools: replace(replace(replace(replace('// Pool: POOLNAME (Type: POOLTYPE)\nvar pool_INDEX = new JObject()\n{\n    { "poolName", "POOLNAME" },\n    { "poolType", "POOLTYPE" },\n    { "supportedModels", new JArray(MODELS) }\n};\nbackendPools.Add(pool_INDEX);', 'POOLNAME', pool.poolName), 'POOLTYPE', pool.poolType), 'INDEX', string(index)), 'MODELS', join(map(pool.supportedModels, (model) => '"${model}"'), ', '))]

var backendPoolsCode = join(backendPoolsArray, '\n')

// ---- Metadata Config JSON Generation ----
// Flatten model metadata from llmBackendConfig into a lookup by model name
var modelMetadata = reduce(llmBackendConfig, {}, (acc, config) =>
  reduce(config.supportedModels, acc, (modelAcc, model) => union(modelAcc, {
    '${model.name}': {
      tier: model.?tier ?? 'standard'
      apiVersion: model.?apiVersion ?? '2024-02-15-preview'
      inferenceApiVersion: model.?inferenceApiVersion ?? '2024-05-01-preview'
      timeout: model.?timeout ?? 120
    }
  }))
)

// Generate JSON entries for each unique model from allPools + modelMetadata lookup
var metadataModelsEntries = [for pool in allPools: '""${pool.supportedModels[0]}"": { ""backend"": ""${pool.poolName}"", ""pool-type"": ""${pool.poolType}"", ""tier"": ""${modelMetadata[pool.supportedModels[0]].tier}"", ""api-version"": ""${modelMetadata[pool.supportedModels[0]].apiVersion}"", ""inference-api-version"": ""${modelMetadata[pool.supportedModels[0]].inferenceApiVersion}"", ""timeout"": ${modelMetadata[pool.supportedModels[0]].timeout} }']

var metadataModelsJson = join(metadataModelsEntries, ',\n            ')

// Load policy fragment templates
var setBackendPoolsFragmentTemplate = loadTextContent('./policies/frag-set-backend-pools.xml')
var setBackendAuthorizationFragmentXml = loadTextContent('./policies/frag-set-backend-authorization.xml')
var setTargetBackendPoolFragmentXml = loadTextContent('./policies/frag-set-target-backend-pool.xml')
var setLlmRequestedModelFragmentXml = loadTextContent('./policies/frag-set-llm-requested-model.xml')
var setLlmUsageFragmentXml = loadTextContent('./policies/frag-set-llm-usage.xml')
var getAvailableModelsFragmentTemplate = loadTextContent('./policies/frag-get-available-models.xml')

// Inject generated backend pools code into template
var updatedSetBackendPoolsFragmentXml = replace(setBackendPoolsFragmentTemplate, '//{backendPoolsCode}', backendPoolsCode)

// Generate model deployments code using reduce to flatten models from all backends
// Each backend generates code for all its supported models (now with per-model metadata)
// supportedModels is now an array of objects: { name, sku?, capacity?, modelFormat?, modelVersion?, retirementDate? }
var modelDeploymentsCodeResult = reduce(llmBackendConfig, { code: '', index: 0 }, (acc, config) => 
  reduce(config.supportedModels, acc, (modelAcc, model) => {
    code: '${modelAcc.code}\n// Model: ${model.name} from backend: ${config.backendId}\nvar deployment_${modelAcc.index} = new JObject()\n{\n    { "id", "${config.backendId}" },\n    { "type", "${config.backendType}" },\n    { "name", "${model.name}" },\n    { "sku", new JObject() { { "name", "${model.?sku ?? 'Standard'}" }, { "capacity", ${model.?capacity ?? 100} } } },\n    { "properties", new JObject() {\n        { "model", new JObject() { { "format", "${model.?modelFormat ?? 'OpenAI'}" }, { "name", "${model.name}" }, { "version", "${model.?modelVersion ?? '1'}" } } },\n        { "capabilities", new JObject() { { "chatCompletion", "true" } } },\n        { "provisioningState", "Succeeded" }${!empty(model.?retirementDate) ? ',\n        { "retirementDate", "${model.retirementDate}" }' : ''}\n    }}\n};\nmodelDeployments.Add(deployment_${modelAcc.index});'
    index: modelAcc.index + 1
  })
)

var modelDeploymentsCode = modelDeploymentsCodeResult.code

// Inject generated model deployments code into available models template
var updatedGetAvailableModelsFragmentXml = replace(getAvailableModelsFragmentTemplate, '//{modelDeploymentsCode}', modelDeploymentsCode)

// Metadata config fragment template - inject generated models JSON
var metadataConfigTemplate = loadTextContent('./policies/frag-metadata-config.xml')
var updatedMetadataConfigXml = replace(metadataConfigTemplate, '//{metadataConfigModels}', metadataModelsJson)

// ------------------
//    RESOURCES
// ------------------

resource apimService 'Microsoft.ApiManagement/service@2024-06-01-preview' existing = {
  name: apimServiceName
}

// Named value for managed identity client ID
resource uamiClientIdNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  name: 'uami-client-id'
  parent: apimService
  properties: {
    displayName: 'uami-client-id'
    value: managedIdentityClientId
    secret: false
  }
}

// Policy Fragment: Set Backend Pools
resource setBackendPoolsFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  name: 'set-backend-pools'
  parent: apimService
  properties: {
    description: 'Dynamically generated backend pool configurations for LLM routing'
    format: 'rawxml'
    value: updatedSetBackendPoolsFragmentXml
  }
}

// Policy Fragment: Set Backend Authorization
resource setBackendAuthorizationFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  name: 'set-backend-authorization'
  parent: apimService
  properties: {
    description: 'Authentication and routing configuration for different LLM backend types'
    format: 'rawxml'
    value: setBackendAuthorizationFragmentXml
  }
}

// Policy Fragment: Set Target Backend Pool
resource setTargetBackendPoolFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  name: 'set-target-backend-pool'
  parent: apimService
  properties: {
    description: 'Determines the target backend pool for LLM requests'
    format: 'rawxml'
    value: setTargetBackendPoolFragmentXml
  }
}

// Policy Fragment: Set LLM Requested Model
resource setLlmRequestedModelFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  name: 'set-llm-requested-model'
  parent: apimService
  properties: {
    description: 'Extracts the requested model from deployment-id (Azure OpenAI) or request body (Inference)'
    format: 'rawxml'
    value: setLlmRequestedModelFragmentXml
  }
}

// Policy Fragment: Set LLM Usage
resource setLlmUsageFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  name: 'set-llm-usage'
  parent: apimService
  properties: {
    description: 'Collects usage metrics for LLM requests'
    format: 'rawxml'
    value: setLlmUsageFragmentXml
  }
}

// Policy Fragment: Get Available Models
resource getAvailableModelsFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  name: 'get-available-models'
  parent: apimService
  properties: {
    description: 'Returns a JSON response listing all available model deployments with their capabilities'
    format: 'rawxml'
    value: updatedGetAvailableModelsFragmentXml
  }
}

// Policy Fragment: Metadata Config
resource metadataConfigFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  name: 'metadata-config'
  parent: apimService
  properties: {
    description: 'Centralized metadata configuration for AI models and API routing'
    format: 'rawxml'
    value: updatedMetadataConfigXml
  }
}

// ------------------
//    OUTPUTS
// ------------------

@description('Name of the set-backend-pools fragment')
output setBackendPoolsFragmentName string = setBackendPoolsFragment.name

@description('Name of the set-backend-authorization fragment')
output setBackendAuthorizationFragmentName string = setBackendAuthorizationFragment.name

@description('Name of the set-target-backend-pool fragment')
output setTargetBackendPoolFragmentName string = setTargetBackendPoolFragment.name

@description('Name of the get-available-models fragment')
output getAvailableModelsFragmentName string = getAvailableModelsFragment.name

@description('Name of the metadata-config fragment')
output metadataConfigFragmentName string = metadataConfigFragment.name

@description('Generated backend pools configuration code')
output backendPoolsCode string = backendPoolsCode
