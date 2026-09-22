/**
 * @module llm-backends
 * @description Creates APIM backends for LLM services (AI Foundry, Azure OpenAI, Amazon Bedrock, and other providers)
 * 
 * This module dynamically creates backend resources based on the provided configuration array.
 * Each backend represents an LLM endpoint that can serve one or more model deployments.
 * 
 * Supported backend types:
 * - ai-foundry: Azure AI Foundry projects with model deployments
 * - azure-openai: Azure OpenAI Service endpoints
 * - aws-bedrock: Amazon Bedrock native (Converse + InvokeModel) endpoints. Default auth is AWS SigV4;
 *                set `authType: 'api-key-bearer'` to use a long-lived Bedrock API key (Bearer token).
 * - aws-bedrock-mantle: Amazon Bedrock OpenAI-compatible endpoint with Bearer token
 * - gemini: GCP Gemini native endpoints (/v1beta/models/...:generateContent) with x-goog-api-key
 * - gemini-openai: GCP Gemini OpenAI-compatible endpoints (/v1beta/openai/...) with Bearer token
 * - anthropic: Anthropic Claude direct endpoints (native Messages API) with x-api-key + anthropic-version
 * - external: Other LLM providers (OpenAI, etc.)
 */

// ------------------
//    PARAMETERS
// ------------------

@description('Name of the API Management service')
param apimServiceName string

@description('User-assigned managed identity client ID for authentication')
param managedIdentityClientId string

@description('Configuration array for LLM backends')
param llmBackendConfig array

@description('Whether to configure circuit breaker for backends (master toggle). Individual backends can opt out via `circuitBreaker.enabled: false` in their config.')
param configureCircuitBreaker bool = true

@description('Default circuit breaker settings applied to every backend unless overridden per-backend via the backend config `circuitBreaker` object')
@metadata({
  description: '''
  Shape:
  - failureCount: Number of failures within the interval that trips the breaker (default 3)
  - failureInterval: ISO 8601 duration window used to count failures (default 'PT5M')
  - tripDuration: ISO 8601 duration the breaker stays open once tripped (default 'PT1M')
  - acceptRetryAfter: Honor upstream Retry-After header when tripping (default true)
  - errorReasons: Failure reasons that count toward the breaker (default ['Server errors'])
  - statusCodeRanges: HTTP status ranges counted as failures (default 429 and 500-503)
  Any subset supplied per-backend is shallow-merged over these defaults.
  '''
})
param circuitBreakerDefaults object = {
  failureCount: 3
  failureInterval: 'PT5M'
  tripDuration: 'PT1M'
  acceptRetryAfter: true
  errorReasons: [
    'Server errors'
  ]
  statusCodeRanges: [
    {
      min: 429
      max: 429
    }
    {
      min: 500
      max: 503
    }
  ]
}

@description('Anthropic API version sent in the anthropic-version header for Anthropic backends (Messages API). Stored as the `anthropic-version` named value referenced by the backend credentials.header.')
param anthropicVersion string = '2023-06-01'

// ------------------
//    VARIABLES
// ------------------

/**
 * Resolve effective authType + named-value key per backend up front so the
 * resource body stays readable. The same precedence used by the policy
 * fragments applies here:
 *   explicit `authType` > backendType-derived default > `managed-identity`
 */
var enrichedBackendConfig = [for config in llmBackendConfig: {
  raw: config
  effectiveAuthType: config.?authType ?? (config.backendType == 'aws-bedrock' ? 'aws-sigv4' : config.backendType == 'external' ? 'none' : config.backendType == 'aws-bedrock-mantle' || config.backendType == 'gemini-openai' ? 'api-key-bearer' : config.backendType == 'gemini' ? 'api-key-gemini' : config.backendType == 'anthropic' ? 'api-key-anthropic' : 'managed-identity')
  authNamedValueKey: config.?authConfig.?namedValueKey ?? ''
  // Effective circuit breaker settings for this backend: start from the global
  // defaults and shallow-merge any per-backend `circuitBreaker` overrides on top.
  // `enabled` (optional, default true) lets a single backend opt out even when
  // the master `configureCircuitBreaker` toggle is on.
  circuitBreaker: union(circuitBreakerDefaults, config.?circuitBreaker ?? {})
}]

// Deduplicate per-backend authConfigs by namedValueKey so we create exactly one
// APIM named value per unique key. Multiple backends MAY share the same key
// (e.g. native + OpenAI-compat surfaces of the same provider when the secret
// value happens to be identical). ARM rejects duplicate resource declarations,
// so we collapse to a unique map and re-emit as an array.
var backendAuthConfigs = filter(llmBackendConfig, config => !empty(config.?authConfig.?namedValueKey ?? ''))
var uniqueAuthConfigsMap = reduce(backendAuthConfigs, {}, (acc, config) => contains(acc, config.authConfig.namedValueKey)
  ? acc
  : union(acc, { '${config.authConfig.namedValueKey}': config.authConfig }))
var uniqueAuthConfigs = map(items(uniqueAuthConfigsMap), item => item.value)

// ------------------
//    RESOURCES
// ------------------

resource apimService 'Microsoft.ApiManagement/service@2024-06-01-preview' existing = {
  name: apimServiceName
}

// Per-backend named values for the secrets referenced from `credentials.header`.
// MUST be created BEFORE the `llmBackends` resource because APIM validates the
// `{{namedValueKey}}` tokens at backend create/update time and rejects the
// request with `Property '<key>' not found.` if the named value doesn't exist
// yet. The explicit `dependsOn` below enforces this ordering (the named-value
// reference inside the header value is a string template, so Bicep can't infer
// the dependency on its own).
//
// When `keyVaultSecretUri` is supplied, the named value is created as a Key
// Vault reference (rotatable, auditable). Otherwise the inline `secretValue`
// is stored directly on the named value (testing-only path).
resource backendApiKeyNamedValues 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = [for cfg in uniqueAuthConfigs: {
  name: cfg.namedValueKey
  parent: apimService
  properties: {
    displayName: cfg.namedValueKey
    secret: true
    keyVault: !empty(cfg.?keyVaultSecretUri ?? '') ? {
      secretIdentifier: cfg.keyVaultSecretUri
    } : null
    value: empty(cfg.?keyVaultSecretUri ?? '') ? (cfg.?secretValue ?? 'NOT_CONFIGURED') : null
  }
}]

// `anthropic-version` named value for Anthropic backends. Created here (instead
// of in the policy-fragments module) because the api-key-anthropic backend's
// credentials.header references `{{anthropic-version}}` and APIM validates that
// the named value exists at backend create/update time. Always created with a
// sensible default so the resource is unconditional and the dependsOn below
// stays static (avoids `if(...)` on a non-collection symbolic resource).
resource anthropicVersionNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  name: 'anthropic-version'
  parent: apimService
  properties: {
    displayName: 'anthropic-version'
    value: !empty(anthropicVersion) ? anthropicVersion : '2023-06-01'
    secret: false
  }
}

// Create individual backends for each LLM endpoint
//
// API-key auth is configured **natively on the backend resource** via
// `credentials.header`. APIM substitutes `{{namedValueKey}}` tokens when the
// backend is created/updated, so the actual secret never appears in policy
// expressions. This keeps `frag-set-backend-authorization.xml` simple — it only
// has to handle `aws-sigv4` (which can't be expressed as a static header) and
// the implicit `managed-identity` / `none` paths.
//
// IMPORTANT: APIM does NOT substitute `{{namedValueKey}}` tokens inside a
// concatenated string (e.g. `'Bearer {{key}}'`) on the Backend resource — the
// substitution only fires when the *entire* header value is the bare token.
// Therefore the secret stored in Key Vault / the named value must contain the
// **complete header value**, not just the API key:
//   api-key-bearer    → Authorization: <secret>          ← secret = "Bearer sk-abc..."
//   api-key-header    → api-key: <secret>                ← secret = "sk-abc..."
//   api-key-gemini    → x-goog-api-key: <secret>         ← secret = "sk-abc..."
//   api-key-anthropic → x-api-key: <secret>              ← secret = "sk-abc..."
//                       anthropic-version: <version>      ← from {{anthropic-version}} named value
//
// Backends needing both a Bearer-prefixed and a raw form of the same provider
// key (e.g. Gemini native vs Gemini-OpenAI-compat) must use **separate named
// values / Key Vault secrets** — one storing `Bearer <key>` and one storing
// the raw `<key>`. Do NOT share a single named value across both.
resource llmBackends 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = [for (entry, i) in enrichedBackendConfig: {
  name: entry.raw.backendId
  parent: apimService
  // The named-value references inside `credentials.header` (`{{namedValueKey}}`)
  // are string templates, so Bicep can't infer the dependency on
  // `backendApiKeyNamedValues`. Declare it explicitly to avoid the "Property
  // '<key>' not found." validation error that APIM raises when a backend is
  // submitted before its named value exists. Same applies to the static
  // `{{anthropic-version}}` reference used by api-key-anthropic backends.
  dependsOn: [
    backendApiKeyNamedValues
    anthropicVersionNamedValue
  ]
  properties: {
    description: 'LLM Backend: ${entry.raw.backendType} - ${entry.raw.backendId} - Supports models: ${join(map(entry.raw.supportedModels, m => m.name), ', ')}'
    url: entry.raw.endpoint
    protocol: 'http'

    // Circuit breaker configuration for resilience. Per-backend settings are the
    // global `circuitBreakerDefaults` shallow-merged with any overrides supplied
    // on this backend's `circuitBreaker` object. A backend can opt out entirely
    // by setting `circuitBreaker.enabled: false` even while the master toggle is on.
    circuitBreaker: (configureCircuitBreaker && (entry.circuitBreaker.?enabled ?? true)) ? {
      rules: [
        {
          failureCondition: {
            count: entry.circuitBreaker.failureCount
            errorReasons: entry.circuitBreaker.errorReasons
            interval: entry.circuitBreaker.failureInterval
            statusCodeRanges: entry.circuitBreaker.statusCodeRanges
          }
          name: '${entry.raw.backendId}-breaker-rule'
          tripDuration: entry.circuitBreaker.tripDuration
          acceptRetryAfter: entry.circuitBreaker.acceptRetryAfter
        }
      ]
    } : null

    credentials: {
      // Managed Identity: native backend auth — no policy expression needed
      #disable-next-line BCP037
      managedIdentity: entry.effectiveAuthType == 'managed-identity' ? {
        clientId: managedIdentityClientId
        resource: 'https://cognitiveservices.azure.com'
      } : null
      // Static headers — APIM resolves `{{namedValueKey}}` to the named value's
      // secret (or Key Vault reference) at create/update time.
      header: entry.effectiveAuthType == 'managed-identity' ? {
        'x-ms-client-id': [managedIdentityClientId]
      } : entry.effectiveAuthType == 'api-key-bearer' ? {
        Authorization: ['{{${entry.authNamedValueKey}}}']
      } : entry.effectiveAuthType == 'api-key-header' ? {
        'api-key': ['{{${entry.authNamedValueKey}}}']
      } : entry.effectiveAuthType == 'api-key-gemini' ? {
        'x-goog-api-key': ['{{${entry.authNamedValueKey}}}']
      } : entry.effectiveAuthType == 'api-key-anthropic' ? {
        'x-api-key': ['{{${entry.authNamedValueKey}}}']
        'anthropic-version': ['{{anthropic-version}}']
      } : {}
    }

    // TLS configuration for secure communication
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}]

// ------------------
//    OUTPUTS
// ------------------

@description('Array of created backend IDs')
output backendIds array = [for (config, i) in llmBackendConfig: llmBackends[i].name]

@description('Array of backend configurations with resource IDs')
output backendDetails array = [for (config, i) in llmBackendConfig: {
  backendId: config.backendId
  backendType: config.backendType
  authType: config.?authType ?? ''
  authConfigNamedValue: config.?authConfig.?namedValueKey ?? ''
  resourceId: llmBackends[i].id
  supportedModels: config.supportedModels
  priority: config.?priority ?? 1
  weight: config.?weight ?? 100
  sessionAffinity: config.?sessionAffinity ?? {}
}]
