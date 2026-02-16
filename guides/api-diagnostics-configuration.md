# API Diagnostics Configuration for LLM Inference APIs

This guide explains how to configure API-level diagnostics for the LLM inference APIs (Azure OpenAI API and AI Model Inference API) in the AI Hub Gateway solution.

## Overview

The solution supports two types of diagnostics for LLM inference APIs:

1. **Application Insights Diagnostics** - Logs API requests and responses to Application Insights for detailed analysis and debugging
2. **Azure Monitor Diagnostics** - Provides specialized LLM observability features including prompt and completion logging

Both diagnostics types can be configured independently through the `main.bicepparam` file.

## Configuration Parameters

### Application Insights Diagnostics (`apiDiagnosticsAppInsights`)

Controls what data is logged to Application Insights for each API request and response.

```bicep
param apiDiagnosticsAppInsights = {
  headers: [ 'Content-type', 'User-agent', 'x-ms-region', 'x-ratelimit-remaining-tokens', 'x-ratelimit-remaining-requests' ]
  body: {
    bytes: 8192
  }
}
```

**Configuration Options:**

- `headers`: Array of HTTP header names to log
  - Common headers include: `Content-type`, `User-agent`, `x-ms-region`
  - Rate limit headers: `x-ratelimit-remaining-tokens`, `x-ratelimit-remaining-requests`
  - To log all headers, include additional header names in the array
  
- `body.bytes`: Number of bytes of request/response body to log
  - `0` = No body logging (only headers)
  - `8192` = Log up to 8KB of body content (default)
  - Increase for larger payloads (e.g., `16384` for 16KB)
  - Note: Large values may increase costs and storage requirements

### Azure Monitor Diagnostics (`apiDiagnosticsAzureMonitor`)

Provides advanced LLM-specific observability with prompt and completion logging.

```bicep
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
```

**Configuration Options:**

#### Frontend (Client ↔ API Gateway)
- `frontend.request.headers`: Array of request headers to log from client
- `frontend.request.body.bytes`: Size of request body to log from client
- `frontend.response.headers`: Array of response headers to log to client
- `frontend.response.body.bytes`: Size of response body to log to client

#### Backend (API Gateway ↔ Backend Services)
- `backend.request.headers`: Array of request headers to log to backend
- `backend.request.body.bytes`: Size of request body to log to backend
- `backend.response.headers`: Array of response headers to log from backend
- `backend.response.body.bytes`: Size of response body to log from backend

#### Large Language Model (LLM-specific logging)
- `largeLanguageModel.logs`: Enable/disable LLM logging
  - `'enabled'` = Capture LLM prompts and completions
  - `'disabled'` = Skip LLM-specific logging
  
- `largeLanguageModel.requests.messages`: Control prompt logging
  - `'all'` = Log all prompts (default)
  - `'none'` = Don't log prompts
  - `'sample'` = Log a sample of prompts
  
- `largeLanguageModel.requests.maxSizeInBytes`: Maximum size of prompts to log
  - `262144` = 256KB (default)
  - Adjust based on your prompt sizes
  
- `largeLanguageModel.responses.messages`: Control completion logging
  - `'all'` = Log all completions (default)
  - `'none'` = Don't log completions
  - `'sample'` = Log a sample of completions
  
- `largeLanguageModel.responses.maxSizeInBytes`: Maximum size of completions to log
  - `262144` = 256KB (default)
  - Adjust based on your completion sizes

## Common Configuration Scenarios

### Scenario 1: Maximum Observability (Development/Testing)

Log everything for detailed debugging and analysis:

```bicep
param apiDiagnosticsAppInsights = {
  headers: [ 'Content-type', 'User-agent', 'x-ms-region', 'x-ratelimit-remaining-tokens', 'x-ratelimit-remaining-requests' ]
  body: {
    bytes: 16384  // 16KB
  }
}

param apiDiagnosticsAzureMonitor = {
  frontend: {
    request: {
      headers: [ 'Content-type', 'User-agent' ]
      body: { bytes: 8192 }
    }
    response: {
      headers: [ 'Content-type' ]
      body: { bytes: 8192 }
    }
  }
  backend: {
    request: {
      headers: [ 'Content-type' ]
      body: { bytes: 8192 }
    }
    response: {
      headers: [ 'Content-type', 'x-ratelimit-remaining-tokens' ]
      body: { bytes: 8192 }
    }
  }
  largeLanguageModel: {
    logs: 'enabled'
    requests: {
      messages: 'all'
      maxSizeInBytes: 524288  // 512KB
    }
    responses: {
      messages: 'all'
      maxSizeInBytes: 524288  // 512KB
    }
  }
}
```

### Scenario 2: Minimal Logging (Production with Cost Optimization)

Log only essential information to reduce costs:

```bicep
param apiDiagnosticsAppInsights = {
  headers: [ 'Content-type', 'x-ratelimit-remaining-tokens' ]
  body: {
    bytes: 0  // No body logging
  }
}

param apiDiagnosticsAzureMonitor = {
  frontend: {
    request: { headers: [], body: { bytes: 0 } }
    response: { headers: [], body: { bytes: 0 } }
  }
  backend: {
    request: { headers: [], body: { bytes: 0 } }
    response: { headers: [], body: { bytes: 0 } }
  }
  largeLanguageModel: {
    logs: 'enabled'
    requests: {
      messages: 'sample'  // Sample only
      maxSizeInBytes: 1024  // 1KB
    }
    responses: {
      messages: 'sample'  // Sample only
      maxSizeInBytes: 1024  // 1KB
    }
  }
}
```

### Scenario 3: Compliance/Audit Mode (Log Everything, Especially LLM Content)

Capture all LLM interactions for compliance and audit purposes:

```bicep
param apiDiagnosticsAppInsights = {
  headers: [ 'Content-type', 'User-agent', 'x-ms-region', 'x-ratelimit-remaining-tokens', 'x-ratelimit-remaining-requests' ]
  body: {
    bytes: 8192
  }
}

param apiDiagnosticsAzureMonitor = {
  frontend: {
    request: { headers: [], body: { bytes: 0 } }
    response: { headers: [], body: { bytes: 0 } }
  }
  backend: {
    request: { headers: [], body: { bytes: 0 } }
    response: { headers: [], body: { bytes: 0 } }
  }
  largeLanguageModel: {
    logs: 'enabled'
    requests: {
      messages: 'all'
      maxSizeInBytes: 1048576  // 1MB - capture large prompts
    }
    responses: {
      messages: 'all'
      maxSizeInBytes: 1048576  // 1MB - capture large completions
    }
  }
}
```

## Deployment

After modifying the parameters in `main.bicepparam`, deploy using:

```bash
# Deploy with bicepparam file
az deployment sub create \
  --location <your-location> \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam
```

Or using Azure Developer CLI:

```bash
# Using azd (ensure your .azure/<env>/.env is configured)
azd up
```

## Viewing Diagnostics Data

### Application Insights

1. Navigate to your Application Insights resource in Azure Portal
2. Go to "Logs" and query the `requests` and `dependencies` tables
3. Example query to view API requests:

```kusto
requests
| where cloud_RoleName contains "apim"
| where name contains "openai" or name contains "inference"
| project timestamp, name, duration, resultCode, customDimensions
| order by timestamp desc
```

### Azure Monitor (LLM Logs)

1. Navigate to your API Management service in Azure Portal
2. Go to "Monitoring" > "Logs"
3. Query the diagnostic logs for LLM content:

```kusto
ApiManagementGatewayLogs
| where OperationId contains "openai" or OperationId contains "inference"
| where isnotempty(LargeLanguageModelRequest) or isnotempty(LargeLanguageModelResponse)
| project TimeGenerated, OperationId, LargeLanguageModelRequest, LargeLanguageModelResponse
| order by TimeGenerated desc
```

## Best Practices

1. **Development**: Use maximum observability to debug issues
2. **Production**: Balance observability with cost and performance
3. **Sensitive Data**: Be careful logging headers that may contain sensitive information (e.g., API keys)
4. **Storage Costs**: Large log volumes increase Azure storage costs
5. **Performance**: Excessive logging can impact API performance
6. **Compliance**: Ensure logged data complies with your data retention policies
7. **PII**: Consider if prompt/completion logging may capture personally identifiable information

## Security Considerations

- **API Keys**: Never log `Ocp-Apim-Subscription-Key` or `api-key` headers
- **Authorization Tokens**: Never log `Authorization` headers in any environment (development, testing, or production)
- **User Data**: Be aware that prompts and completions may contain sensitive user data
- **Retention**: Configure appropriate log retention periods based on compliance requirements
- **Access Control**: Ensure only authorized personnel can access diagnostic logs

> **Security Warning**: Authorization tokens, API keys, and subscription keys should never be logged as they could be exposed to unauthorized users and compromise your system security.

## Troubleshooting

### Issue: Diagnostics not appearing in Application Insights

- Verify Application Insights is properly configured
- Check that the logger resource is correctly created in APIM
- Ensure sampling percentage is set to 100 for testing

### Issue: LLM logs not appearing in Azure Monitor

- Confirm Azure Monitor diagnostics is enabled (`logs: 'enabled'`)
- Verify messages setting is not set to `'none'`
- Check that maxSizeInBytes is sufficient for your content
- Ensure you're using API version 2024-06-01-preview or later

### Issue: High storage costs

- Reduce `body.bytes` values
- Set LLM messages to `'sample'` instead of `'all'`
- Decrease `maxSizeInBytes` for LLM requests/responses
- Configure shorter retention periods in Application Insights

## Related Resources

- [API Management Diagnostics Documentation](https://learn.microsoft.com/azure/api-management/api-management-howto-app-insights)
- [Azure Monitor for APIM](https://learn.microsoft.com/azure/api-management/observability)
- [Application Insights Overview](https://learn.microsoft.com/azure/azure-monitor/app/app-insights-overview)
- [APIM Configuration Guide](./apim-configuration.md)
