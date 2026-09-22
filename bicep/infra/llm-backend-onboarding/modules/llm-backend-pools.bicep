/**
 * @module llm-backend-pools
 * @description Creates APIM backend pools that group backends by supported models
 * 
 * This module analyzes the LLM backend configuration and creates backend pools.
 * Each pool groups backends that support the same model, enabling:
 * - Load balancing across multiple backends for the same model
 * - Automatic failover if one backend becomes unavailable
 * - Priority-based and weighted routing strategies
 */

// ------------------
//    PARAMETERS
// ------------------

@description('Name of the API Management service')
param apimServiceName string

@description('Array of backend details from llm-backends module output')
param backendDetails array

@description('Master toggle for backend-pool session affinity (sticky routing). When false, no pool receives session affinity regardless of per-model `sessionAwareModel` flags. Real opt-in is per-model; this is a global kill-switch.')
param configureSessionAffinity bool = true

@description('Default session affinity cookie settings applied to session-aware model pools unless overridden per-backend via the backend config `sessionAffinity` object')
@metadata({
  description: '''
  Applied only to pools whose model is flagged `sessionAwareModel: true`. Shape:
  - cookieName: Name of the affinity cookie APIM sets/reads (default 'ai-gateway-affinity',
    chosen to avoid clashing with other client/server cookies)
  - source: Where the session id is read from (only 'Cookie' is supported by APIM today)
  Per-backend, add a `sessionAffinity` object to any llmBackendConfig entry to override a subset
  of these (shallow-merged). The first pool member that supplies an override wins.
  '''
})
param sessionAffinityDefaults object = {
  cookieName: 'ai-gateway-affinity'
  source: 'Cookie'
}

// ------------------
//    VARIABLES
// ------------------

// Extract model names from supportedModels objects for each backend
// supportedModels can be either array of strings (legacy) or array of objects with 'name' property (new)
var normalizedBackendDetails = [for backend in backendDetails: {
  backendId: backend.backendId
  backendType: backend.backendType
  authType: backend.?authType ?? ''
  authConfigNamedValue: backend.?authConfigNamedValue ?? ''
  resourceId: backend.resourceId
  priority: backend.priority
  weight: backend.weight
  // Per-backend session affinity override for the session cookie (cookieName/source).
  // Empty object => this backend contributes no override and the pool falls back to defaults.
  sessionAffinity: backend.?sessionAffinity ?? {}
  // Extract model names - handle both string arrays and object arrays
  modelNames: map(backend.supportedModels, m => m.name)
  // Names of models this backend flags as session-aware (stateful). Used to decide which
  // generated pools get session affinity. A single backend can mix stateful and stateless models.
  sessionAwareModelNames: map(filter(backend.supportedModels, m => (m.?sessionAwareModel ?? false)), m => m.name)
}]

// Group backends by (model, backendType) to create backend pools.
// Composite key prevents collapse of the same model id served by two different
// backend types (e.g. `eu.amazon.nova-lite-v1:0` registered against both an
// `aws-bedrock` native pool and an `aws-bedrock-mantle` OpenAI-compat pool).
// Without the composite key both backends would collapse into a single pool
// whose `poolType` is whichever backend was processed first, breaking the
// `compatiblePoolTypes` filter applied by the inbound API surface (Universal
// LLM, Unified AI inference api-type, etc.). Delimiter `||` is not legal in
// either model ids or backend types, so it never collides with a real key.
var modelKeyDelimiter = '||'
var modelToBackendsMap = reduce(normalizedBackendDetails, {}, (acc, backend) => union(acc, reduce(backend.modelNames, {}, (modelAcc, model) => union(modelAcc, {
  '${model}${modelKeyDelimiter}${backend.backendType}': union(
    acc[?'${model}${modelKeyDelimiter}${backend.backendType}'] ?? [],
    [{
        backendId: backend.backendId
        backendType: backend.backendType
        authType: backend.authType
        authConfigNamedValue: backend.authConfigNamedValue
        resourceId: backend.resourceId
        priority: backend.priority
        weight: backend.weight
        sessionAffinity: backend.sessionAffinity
      }]
  )
}))))

// Map of (model, backendType) composite key -> true when at least one backend flags that model
// as session-aware. Keys absent from this map are stateless models (no pool session affinity).
// The presence-based union naturally ORs the flag across all backends serving the same model.
var modelSessionAwareMap = reduce(normalizedBackendDetails, {}, (acc, backend) => union(acc, reduce(backend.sessionAwareModelNames, {}, (modelAcc, model) => union(modelAcc, {
  '${model}${modelKeyDelimiter}${backend.backendType}': true
}))))

// Create pool configurations only for (model, backendType) combos served by multiple backends.
// Pool name embeds the backendType so two pools for the same model id
// (e.g. one `aws-bedrock`, one `aws-bedrock-mantle`) get distinct APIM resource
// names. Special characters from provider model ids (`.`, `:`, `_`, `/`) are
// stripped from both the model and backendType segments because APIM resource
// names allow only letters/digits/hyphens. The original (unsanitized) model
// name is still used as the routing key, so the request-processor /
// set-target-backend-pool fragments keep matching by the real model name.
var poolConfigs = map(
  filter(items(modelToBackendsMap), (item) => length(item.value) > 1),
  (item) => {
    modelName: split(item.key, modelKeyDelimiter)[0]
    backendType: split(item.key, modelKeyDelimiter)[1]
    poolName: '${replace(replace(replace(replace(split(item.key, modelKeyDelimiter)[0], '.', ''), ':', ''), '_', ''), '/', '')}-${replace(replace(replace(replace(split(item.key, modelKeyDelimiter)[1], '.', ''), ':', ''), '_', ''), '/', '')}-backend-pool'
    backends: item.value
    // Whether this pool's model is session-aware (stateful) and therefore gets session affinity.
    sessionAware: (modelSessionAwareMap[?item.key] ?? false)
    // Effective session cookie config for the pool: global defaults shallow-merged with the first
    // pool member that supplies a per-backend `sessionAffinity` override (else just the defaults).
    sessionAffinity: union(sessionAffinityDefaults, length(filter(item.value, b => !empty(b.sessionAffinity))) > 0 ? filter(item.value, b => !empty(b.sessionAffinity))[0].sessionAffinity : {})
  }
)

// ------------------
//    RESOURCES
// ------------------

resource apimService 'Microsoft.ApiManagement/service@2024-06-01-preview' existing = {
  name: apimServiceName
  // Note: We don't use this directly as pools are created as children of the service
}

// Create backend pools for models with multiple backend options.
// Uses the 2025-03-01-preview API version because `pool.sessionAffinity` (session-aware
// load balancing) is only present in the backend type from that version onward; the rest of
// the module (and the parent service reference) stays on 2024-06-01-preview.
resource backendPools 'Microsoft.ApiManagement/service/backends@2025-03-01-preview' = [for config in poolConfigs: {
  name: config.poolName
  parent: apimService
  properties: {
    description: 'Backend pool for model: ${config.modelName}'
    type: 'Pool'
    #disable-next-line BCP035
    pool: {
      services: [for backend in config.backends: {
        id: '/backends/${backend.backendId}'
        priority: backend.priority
        weight: backend.weight
      }]
      // Session affinity (sticky routing) is emitted only for pools whose model is flagged
      // `sessionAwareModel: true` and while the master toggle is on. APIM sets an affinity cookie
      // so a client that replays it (via a shared cookie jar / HTTP client) is routed back to the
      // same backend for the whole session — required by stateful APIs such as the OpenAI Responses
      // and Assistants APIs. Stateless model pools omit this and keep pure load balancing.
      sessionAffinity: (configureSessionAffinity && config.sessionAware) ? {
        sessionId: {
          source: config.sessionAffinity.source
          name: config.sessionAffinity.cookieName
        }
      } : null
    }
  }
}]

// ------------------
//    OUTPUTS
// ------------------

@description('Array of created backend pool names')
output poolNames array = [for (config, i) in poolConfigs: backendPools[i].name]

@description('Mapping of models to their backend pool names')
output modelToPoolMap object = reduce(poolConfigs, {}, (acc, config) => union(acc, {
  '${config.modelName}': config.poolName
}))

@description('Mapping of models to backend IDs (for models with single backend)')
output modelToBackendMap object = reduce(
  filter(items(modelToBackendsMap), (item) => length(item.value) == 1),
  {},
  (acc, item) => union(acc, {
    // item.key is the composite `${model}||${backendType}` — extract just the model id.
    '${split(item.key, modelKeyDelimiter)[0]}': item.value[0].backendId
  })
)

@description('Complete pool configurations including backend details')
output poolDetails array = [for (config, i) in poolConfigs: {
  modelName: config.modelName
  poolName: config.poolName
  poolType: 'pool'
  backends: config.backends
  // Session affinity summary for this pool (true only for session-aware models with the toggle on).
  sessionAffinityEnabled: (configureSessionAffinity && config.sessionAware)
  sessionAffinityCookie: (configureSessionAffinity && config.sessionAware) ? config.sessionAffinity.cookieName : ''
}]

@description('Configuration for policy fragment generation')
output policyFragmentConfig object = {
  backendPools: map(poolConfigs, config => {
    poolName: config.poolName
    poolType: length(config.backends) > 0 ? config.backends[0].backendType : 'mixed'
    authType: length(config.backends) > 0 ? config.backends[0].authType : ''
    authConfigNamedValue: length(config.backends) > 0 ? config.backends[0].authConfigNamedValue : ''
    supportedModels: [config.modelName]
  })
  directBackends: map(
    filter(items(modelToBackendsMap), (item) => length(item.value) == 1),
    (item) => {
      poolName: item.value[0].backendId
      poolType: item.value[0].backendType
      authType: item.value[0].authType
      authConfigNamedValue: item.value[0].authConfigNamedValue
      // item.key is the composite `${model}||${backendType}` — extract just the model id.
      supportedModels: [split(item.key, modelKeyDelimiter)[0]]
    }
  )
}
