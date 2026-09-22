using 'main.bicep'

// ============================================================================
// Citadel Publish Contract - Asset Publishing Parameters
// ============================================================================
// Publishes centrally protected AI assets (Tools/MCP and Agents/A2A) through the
// AI Hub Gateway. This does NOT create APIM products/subscriptions (that is Access
// Contract scope). Replace the placeholder values below with your environment's.
//
// REQUIRED: apim, publishAssets
// OPTIONAL: managedIdentityClientId, configureCircuitBreaker, circuitBreakerDefaults,
//           ensureUsageFragments, apiCenter
// ============================================================================

// Target APIM instance (must already exist with the AI Hub Gateway deployed).
param apim = {
  subscriptionId: '00000000-0000-0000-0000-000000000000'
  resourceGroupName: 'rg-apim-resource-group'
  name: 'apim-instance-name'
}

// User-assigned managed identity client id used to authenticate to agent backends (e.g. Foundry A2A).
// For A2A, this MUST be a UAMI granted 'Foundry Agent Consumer' (or 'Azure AI User') on the Foundry
// project. Leave empty ('') to use the APIM system-assigned identity.
param managedIdentityClientId = ''

// Circuit breaker master toggle + defaults (per-asset overrides via backend.circuitBreaker).
param configureCircuitBreaker = true

// Prefix every published asset's gateway path with its asset-type segment: Tools are served under
// {gateway}/mcp/... and Agents under {gateway}/agent/.... Default true. Set false to keep legacy
// un-prefixed paths, or set a per-asset `pathPrefix` ('' opts one asset out; a custom value overrides).
param useAssetTypePathPrefix = true

// Optional Azure API Center coordinates. Required only if any asset sets
// publishToApiCenter=true. Leave serviceName empty to disable API Center registration.
param apiCenter = {
  subscriptionId: ''            // defaults to apim.subscriptionId when empty
  resourceGroupName: ''         // defaults to apim.resourceGroupName when empty
  serviceName: ''               // e.g. 'apic-aihub-dev' — empty disables registration
  workspaceName: 'default'
}

// ============================================================================
// ASSETS TO PUBLISH
// ============================================================================
param publishAssets = [
  // --------------------------------------------------------------------------
  // 1) TOOL (API -> MCP): expose an existing onboarded REST API as an MCP server.
  //    Reuses the source API's backend/auth. The sample weather-api is created
  //    when the gateway is deployed with isMCPSampleDeployed=true.
  //    NOTE: the source API (sourceApiName) MUST be onboarded with subscriptionRequired=false.
  //    tools/call forwards to it internally; a required source-API key makes that hop fail with
  //    401 "missing subscription key" (initialize/tools/list still pass as they skip the backend).
  //    OPT-IN alternative: to keep the source API subscription-protected (no anonymous direct access)
  //    while the SAME contract key reaches both, set forwardSubscriptionKeyToSource: true and onboard
  //    the source API with subscriptionRequired=true reading its key from sourceSubscriptionKeyHeaderName
  //    (default 'x-mcp-sub-key'), then grant the source API in the Access Contract's apiNameMapping too.
  // --------------------------------------------------------------------------
  {
    assetType: 'mcp-from-api'
    name: 'weather-tool'
    displayName: 'Weather Tool (MCP)'
    description: 'Weather data operations for a given location, published as an MCP tool server.'
    path: 'weather-tool-mcp'                 // endpoint: {gateway}/mcp/weather-tool-mcp/mcp (mcp/ prefix + APIM /mcp suffix)
    metadata: {
      version: '1.0.0'
      owner: 'Platform Engineering'
      contactEmail: 'ai-platform@contoso.com'
      compliance: [ 'Internal' ]
      classification: 'internal'
    }
    sourceApiName: 'weather-api'
    operationNames: [ 'get-weather' ]
    // forwardSubscriptionKeyToSource: true        // opt-in: keep the source API protected, forward the caller key
    // sourceSubscriptionKeyHeaderName: 'x-mcp-sub-key' // custom header the source API reads (APIM won't strip it)

    // Optional API Center registration
    publishToApiCenter: false
    apiCenter: {
      environmentName: 'mcp-dev'
      lifecycleStage: 'development'
      customProperties: {
        Visibility: true
        Categories: [ 'AI/ML', 'Developer Tools' ]
        Vendor: 'Internal'
        Type: 'AI Gateway'
      }
    }
  }

  // --------------------------------------------------------------------------
  // 2) TOOL (remote/native MCP): publish an existing MCP server through the gateway.
  //    A dedicated backend ('ms-learn-tool-backend') is created for the remote URL.
  // --------------------------------------------------------------------------
  {
    assetType: 'mcp-existing'
    name: 'ms-learn-tool'
    displayName: 'Microsoft Learn Tool (MCP)'
    description: 'Microsoft Learn MCP server published and protected through the gateway.'
    path: 'ms-learn-tool-mcp'                // endpoint: {gateway}/mcp/ms-learn-tool-mcp (mcp/ prefix, no /mcp suffix)
    transportType: 'streamable'
    subscriptionRequired: true
    metadata: {
      version: '1.0.0'
      owner: 'Knowledge Management'
      contactEmail: 'km@contoso.com'
      compliance: [ 'Public' ]
      classification: 'public'
    }
    backend: {
      url: 'https://learn.microsoft.com/api/mcp'
      authType: 'none'
      // Per-asset circuit breaker override example (optional):
      // circuitBreaker: { failureCount: 5, tripDuration: 'PT30S' }
    }

    publishToApiCenter: false
    apiCenter: {
      environmentName: 'mcp-dev'
      lifecycleStage: 'development'
      customProperties: {
        Visibility: true
        Vendor: 'Microsoft'
        Type: 'AI Gateway'
      }
    }
  }

  // --------------------------------------------------------------------------
  // 3) AGENT (A2A): publish a Foundry-hosted agent's A2A endpoint through the gateway.
  //    Requires incoming A2A enabled on the Foundry agent first (see the validation
  //    notebook / Learn guide). The backend uses managed-identity with audience
  //    https://ai.azure.com. Replace {account}, {project}, {agent} below.
  // --------------------------------------------------------------------------
  {
    assetType: 'a2a'
    name: 'hr-chat-agent'
    displayName: 'HR Chat Agent (A2A)'
    description: 'HR assistant answering policy, benefits, and onboarding questions via A2A.'
    path: 'hr-chat-agent'                    // endpoint: {gateway}/agent/hr-chat-agent (agent/ prefix); card at /agent/hr-chat-agent/.well-known/agent.json
    agentId: 'HR-ChatAgent'
    // A2A is anonymous at the gateway in phase 1 (APIM's A2A preview does not validate subscription
    // keys). Client auth is added by the phase-2 Access Contract. Do not send an api-key header to A2A.
    subscriptionRequired: false
    agentCardPath: '/.well-known/agent.json'
    // Foundry v1.0 agent card URL:
    agentCardBackendUrl: 'https://{account}.services.ai.azure.com/api/projects/{project}/agents/{agent}/endpoint/protocols/a2a/agentCard/v1.0'
    jsonRpcPath: '/'
    metadata: {
      version: '1.0.0'
      owner: 'HR Digital'
      contactEmail: 'hr-digital@contoso.com'
      compliance: [ 'GDPR' ]
      classification: 'confidential'
    }
    backend: {
      // Foundry A2A base path (JSON-RPC endpoint):
      url: 'https://{account}.services.ai.azure.com/api/projects/{project}/agents/{agent}/endpoint/protocols/a2a'
      authType: 'managed-identity'
      authConfig: {
        resource: 'https://ai.azure.com'
      }
    }

    publishToApiCenter: false
    apiCenter: {
      environmentName: 'mcp-dev'
      lifecycleStage: 'development'
      customProperties: {
        Visibility: true
        Vendor: 'Internal'
        Type: 'AI Agent'
      }
    }
  }
]
