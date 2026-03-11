/**
 * @module unified-ai-api
 * @description Creates the Unified AI Gateway API in APIM — a wildcard endpoint that routes
 * requests to any AI backend (Azure OpenAI, AI Foundry, external) through the shared pipeline.
 * Unlike inference-api.bicep, this module does not create backends or backend pools; it reuses
 * the shared pools created by llm-backends and llm-backend-pools modules.
 */

// ------------------
//    PARAMETERS
// ------------------

@description('The name of the API Management instance.')
param apiManagementName string

@description('Id of the APIM Logger for Azure Monitor diagnostics.')
param apimLoggerId string = ''

@description('The Application Insights instrumentation key.')
@secure()
param appInsightsInstrumentationKey string = ''

@description('The resource ID for Application Insights.')
param appInsightsId string = ''

@description('The XML content for the API policy.')
param policyXml string

@description('Azure Monitor diagnostic log settings for the API.')
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

@description('Application Insights diagnostic log settings for the API.')
param appInsightsLogSettings object = {
  headers: [ 'Content-type', 'User-agent', 'x-ms-region', 'x-ratelimit-remaining-tokens', 'x-ratelimit-remaining-requests' ]
  body: { bytes: 0 }
}

// ------------------
//    VARIABLES
// ------------------

var logSettings = {
  headers: appInsightsLogSettings.headers
  body: appInsightsLogSettings.body
}

// ------------------
//    RESOURCES
// ------------------

resource apimService 'Microsoft.ApiManagement/service@2024-06-01-preview' existing = {
  name: apiManagementName
}

resource api 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = {
  name: 'unified-ai-gateway-api'
  parent: apimService
  properties: {
    apiType: 'http'
    description: 'Unified AI Gateway API — a single wildcard endpoint that routes to any AI backend through the shared gateway pipeline.'
    displayName: 'Unified AI Gateway API'
    format: 'openapi+json'
    path: 'unified-ai'
    protocols: [
      'https'
    ]
    subscriptionKeyParameterNames: {
      header: 'api-key'
      query: 'api-key'
    }
    subscriptionRequired: true
    type: 'http'
    value: string(loadJsonContent('./unified-ai-api/unified-ai-gateway-wildcard.json'))
  }
}

resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-06-01-preview' = {
  name: 'policy'
  parent: api
  properties: {
    format: 'rawxml'
    value: policyXml
  }
}

resource apiDiagnostics 'Microsoft.ApiManagement/service/apis/diagnostics@2024-06-01-preview' = if(length(apimLoggerId) > 0) {
  parent: api
  name: 'azuremonitor'
  properties: {
    alwaysLog: 'allErrors'
    verbosity: 'verbose'
    logClientIp: true
    loggerId: apimLoggerId
    sampling: {
      samplingType: 'fixed'
      percentage: json('100')
    }
    frontend: {
      request: {
        headers: azureMonitorLogSettings.frontend.request.headers
        body: {
          bytes: azureMonitorLogSettings.frontend.request.body.bytes
        }
      }
      response: {
        headers: azureMonitorLogSettings.frontend.response.headers
        body: {
          bytes: azureMonitorLogSettings.frontend.response.body.bytes
        }
      }
    }
    backend: {
      request: {
        headers: azureMonitorLogSettings.backend.request.headers
        body: {
          bytes: azureMonitorLogSettings.backend.request.body.bytes
        }
      }
      response: {
        headers: azureMonitorLogSettings.backend.response.headers
        body: {
          bytes: azureMonitorLogSettings.backend.response.body.bytes
        }
      }
    }
    largeLanguageModel: {
      logs: azureMonitorLogSettings.largeLanguageModel.logs
      requests: {
        messages: azureMonitorLogSettings.largeLanguageModel.requests.messages
        maxSizeInBytes: azureMonitorLogSettings.largeLanguageModel.requests.maxSizeInBytes
      }
      responses: {
        messages: azureMonitorLogSettings.largeLanguageModel.responses.messages
        maxSizeInBytes: azureMonitorLogSettings.largeLanguageModel.responses.maxSizeInBytes
      }
    }
  }
}

resource apiDiagnosticsAppInsights 'Microsoft.ApiManagement/service/apis/diagnostics@2022-08-01' = if (!empty(appInsightsId) && !empty(appInsightsInstrumentationKey)) {
  name: 'applicationinsights'
  parent: api
  properties: {
    alwaysLog: 'allErrors'
    httpCorrelationProtocol: 'W3C'
    logClientIp: true
    loggerId: resourceId(resourceGroup().name, 'Microsoft.ApiManagement/service/loggers', apiManagementName, 'appinsights-logger')
    metrics: true
    verbosity: 'verbose'
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    frontend: {
      request: logSettings
      response: logSettings
    }
    backend: {
      request: logSettings
      response: logSettings
    }
  }
}

// ------------------
//    OUTPUTS
// ------------------

output apiId string = api.id
output path string = api.properties.path
