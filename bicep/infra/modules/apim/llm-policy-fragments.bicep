/**
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

/**
 * Generate the backend pools array for the set-backend-pools fragment
 * This creates the C# code that will be injected into the policy fragment
 */
var allPools = union(policyFragmentConfig.backendPools, policyFragmentConfig.directBackends)

// Generate C# code for each backend pool with unique variable names using index
var backendPoolsArray = [for (pool, index) in allPools: replace(replace(replace(replace('''
// Pool: POOLNAME (Type: POOLTYPE)
var pool_INDEX = new JObject()
{
    { "poolName", "POOLNAME" },
    { "poolType", "POOLTYPE" },
    { "supportedModels", new JArray(MODELS) }
};
backendPools.Add(pool_INDEX);
''', 'POOLNAME', pool.poolName), 'POOLTYPE', pool.poolType), 'INDEX', string(index)), 'MODELS', join(map(pool.supportedModels, (model) => '"${model}"'), ', '))]

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

/**
 * Complete policy fragment XML with backend pools configuration
 */
var setBackendPoolsFragmentXml = loadTextContent('./policies/frag-set-backend-pools.xml')

var updatedSetBackendPoolsFragmentXml = replace(setBackendPoolsFragmentXml, '//{backendPoolsCode}', backendPoolsCode)

/**
 * Enhanced authorization fragment that supports multiple backend types
 */
var setBackendAuthorizationFragmentXml = loadTextContent('./policies/frag-set-backend-authorization.xml')

/**
 * Get available models fragment template
 */
var getAvailableModelsFragmentTemplate = loadTextContent('./policies/frag-get-available-models.xml')

// Inject generated model deployments code into available models template
var updatedGetAvailableModelsFragmentXml = replace(getAvailableModelsFragmentTemplate, '//{modelDeploymentsCode}', modelDeploymentsCode)

/**
 * Metadata config fragment template
 * Inject generated models JSON into metadata-config XML template
 */
var metadataConfigTemplate = loadTextContent('./policies/frag-metadata-config.xml')
var updatedMetadataConfigXml = replace(metadataConfigTemplate, '//{metadataConfigModels}', metadataModelsJson)

// ------------------
//    RESOURCES
// ------------------

resource apimService 'Microsoft.ApiManagement/service@2024-06-01-preview' existing = {
  name: apimServiceName
}

/**
 * Policy Fragment: Set Backend Pools
 * Contains the dynamically generated backend pool configurations
 */
resource setBackendPoolsFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  name: 'set-backend-pools'
  parent: apimService
  properties: {
    description: 'Dynamically generated backend pool configurations for LLM routing'
    format: 'rawxml'
    value: updatedSetBackendPoolsFragmentXml
  }
}

/**
 * Policy Fragment: Set Backend Authorization
 * Handles authentication for different backend types (Azure OpenAI, AI Foundry, External)
 */
resource setBackendAuthorizationFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  name: 'set-backend-authorization'
  parent: apimService
  properties: {
    description: 'Authentication and routing configuration for different LLM backend types'
    format: 'rawxml'
    value: setBackendAuthorizationFragmentXml
  }
}

/**
 * Policy Fragment: Set Target Backend Pool
 * Determines which backend pool to route requests to based on model and permissions
 */
resource setTargetBackendPoolPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  parent: apimService
  name: 'set-target-backend-pool'
  properties: {
    description: 'Determines the target backend pool for LLM requests'
    value: loadTextContent('./policies/frag-set-target-backend-pool.xml')
    format: 'rawxml'
  }
}

resource setLLMUsagePolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  parent: apimService
  name: 'set-llm-usage'
  properties: {
    description: 'Collects usage metrics for LLM requests'
    value: loadTextContent('./policies/frag-set-llm-usage.xml')
    format: 'rawxml'
  }
}

/**
 * Policy Fragment: Set LLM Requested Model
 * Extracts the requested model from either Azure OpenAI endpoint or inference endpoint
 */
resource setLLMRequestedModelPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  parent: apimService
  name: 'set-llm-requested-model'
  properties: {
    description: 'Extracts the requested model from deployment-id (Azure OpenAI) or request body (Inference)'
    value: loadTextContent('./policies/frag-set-llm-requested-model.xml')
    format: 'rawxml'
  }
}

/**
 * Policy Fragment: Get Available Models
 * Returns a JSON response listing all available model deployments with their capabilities
 */
resource getAvailableModelsFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  parent: apimService
  name: 'get-available-models'
  properties: {
    description: 'Returns a JSON response listing all available model deployments with their capabilities'
    value: updatedGetAvailableModelsFragmentXml
    format: 'rawxml'
  }
}

/**
 * Policy Fragment: Metadata Config
 * Centralized JSON configuration for models, API types, cache, and timeout settings.
 * Models section is auto-generated from llmBackendConfig during deployment.
 */
resource metadataConfigFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  parent: apimService
  name: 'metadata-config'
  properties: {
    description: 'Centralized metadata configuration for AI models and API routing'
    value: updatedMetadataConfigXml
    format: 'rawxml'
  }
}

/**
 * Policy Fragment: Validate Model Access
 * Restricts access to specific models based on the allowedModels variable
 */
resource validateModelAccessFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  parent: apimService
  name: 'validate-model-access'
  properties: {
    description: 'Validates that the requested model is in the allowed models list for the product'
    value: loadTextContent('./policies/frag-validate-model-access.xml')
    format: 'rawxml'
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
output setTargetBackendPoolFragmentName string = setTargetBackendPoolPolicyFragment.name

@description('Name of the get-available-models fragment')
output getAvailableModelsFragmentName string = getAvailableModelsFragment.name

@description('Name of the metadata-config fragment')
output metadataConfigFragmentName string = metadataConfigFragment.name

@description('Name of the validate-model-access fragment')
output validateModelAccessFragmentName string = validateModelAccessFragment.name

@description('Generated backend pools configuration code')
output backendPoolsCode string = backendPoolsCode
