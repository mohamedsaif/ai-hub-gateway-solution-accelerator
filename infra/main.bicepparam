using './main.bicep'

// Basic parameters
param environmentName = readEnvironmentVariable('AZURE_ENV_NAME', 'dev')
param location = readEnvironmentVariable('AZURE_LOCATION', 'eastus')
param resourceGroupName = readEnvironmentVariable('AZURE_RESOURCE_GROUP', 'rg-ai-hub-gateway')

// Authentication parameters
param entraAuth = bool(readEnvironmentVariable('AZURE_ENTRA_AUTH', 'false'))
param entraTenantId = readEnvironmentVariable('AZURE_TENANT_ID', '')
param entraClientId = readEnvironmentVariable('AZURE_CLIENT_ID', '')
param entraAudience = readEnvironmentVariable('AZURE_AUDIENCE', '')

// Deployment capacity
param deploymentCapacity = int(readEnvironmentVariable('OPENAI_CAPACITY', '30'))

//
// API DIAGNOSTICS SETTINGS
//
// These settings control logging for LLM inference APIs (Azure OpenAI API and AI Model Inference API).
// Configure what data is logged to Application Insights and Azure Monitor.
//

// Application Insights diagnostics settings for LLM inference APIs
// - headers: Array of HTTP headers to log (e.g., 'Content-type', 'User-agent', rate limit headers)
//   Note: Headers listed here that don't exist in a request/response are safely ignored
//   SECURITY: Never include sensitive headers like 'Authorization', 'api-key', or 'Ocp-Apim-Subscription-Key'
// - body.bytes: Number of bytes of request/response body to log (0 = no body logging, 8192 = 8KB)
// Example: To log more headers, add them to the headers array below
// Example: To increase body logging, change bytes to a higher value (max depends on your needs)
param apiDiagnosticsAppInsights = {
  headers: [ 'Content-type', 'User-agent', 'x-ms-region', 'x-ratelimit-remaining-tokens', 'x-ratelimit-remaining-requests' ]
  body: {
    bytes: 8192
  }
}

// Azure Monitor diagnostics settings for LLM inference APIs
// This configuration enables Azure Monitor's built-in LLM observability features
// - frontend: Logs for requests/responses between client and APIM gateway
// - backend: Logs for requests/responses between APIM gateway and backend services
// - largeLanguageModel: Specialized logging for LLM prompts and completions
//   - logs: 'enabled' or 'disabled' - Controls whether LLM-specific logs are captured
//   - requests.messages: 'all', 'none', or 'sample' - Controls logging of prompts/requests
//   - requests.maxSizeInBytes: Maximum size of request content to log (262144 = 256KB)
//   - responses.messages: 'all', 'none', or 'sample' - Controls logging of completions/responses  
//   - responses.maxSizeInBytes: Maximum size of response content to log (262144 = 256KB)
// 
// Note: Setting bytes to 0 disables body/content logging for that section
// Note: LLM logging helps track token usage, prompts, and completions for observability
param apiDiagnosticsAzureMonitor = {
  frontend: {
    request: {
      headers: []
      body: {
        bytes: 0
      }
    }
    response: {
      headers: []
      body: {
        bytes: 0
      }
    }
  }
  backend: {
    request: {
      headers: []
      body: {
        bytes: 0
      }
    }
    response: {
      headers: []
      body: {
        bytes: 0
      }
    }
  }
  largeLanguageModel: {
    logs: 'enabled'
    requests: {
      messages: 'all'
      maxSizeInBytes: 262144
    }
    responses: {
      messages: 'all'
      maxSizeInBytes: 262144
    }
  }
}
