using './main.bicep'

// Basic parameters
param environmentName = '${readEnvironmentVariable('AZURE_ENV_NAME', 'dev')}'
param location = '${readEnvironmentVariable('AZURE_LOCATION', 'eastus')}'

// Authentication parameters
param entraAuth = bool('${readEnvironmentVariable('AZURE_ENTRA_AUTH', 'false')}')
param entraTenantId = '${readEnvironmentVariable('AZURE_TENANT_ID', '')}'
param entraClientId = '${readEnvironmentVariable('AZURE_CLIENT_ID', '')}'
param entraAudience = '${readEnvironmentVariable('AZURE_AUDIENCE', '')}'

// Deployment capacity
param deploymentCapacity = int('${readEnvironmentVariable('OPENAI_CAPACITY', '30')}')

// Application Insights diagnostics settings for LLM inference APIs
param apiDiagnosticsAppInsights = {
  headers: [ 'Content-type', 'User-agent', 'x-ms-region', 'x-ratelimit-remaining-tokens', 'x-ratelimit-remaining-requests' ]
  body: {
    bytes: 8192
  }
}

// Azure Monitor diagnostics settings for LLM inference APIs
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
