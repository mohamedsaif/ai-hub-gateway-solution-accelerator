# Deployment troubleshooting

This guide provides troubleshooting tips for common issues that you might encounter when deploying this accelerator to Azure using Azure Developer CLI or Bicep.

## Transient errors

You might want to try again running the deployed as it might resolve some of the transient issues.

```bash
azd up
```

This is usually a transient issue. Please try again after some time (it might take up to 1 hour unfortunately).

Below are few examples of transient issues:

- Unable to edit or replace deployment 'application-insights-dashboard'

- Runtime Scale Monitoring is not supported for this Functions version

- Failed to connect to management endpoint apim-RANDOM.management.azure-api.net:3443 for a service deployed in a Virtual Network. Make sure to follow guidance at https://aka.ms/apim-vnet-common-issues for Inbound connectivity to Management endpoint. Check 'ApiManagement Control Plane - inbound' connectivity at https://aka.ms/apimnetworkstatus. (Code: ManagementApiRequestFailed)

- Managed identity id not found

- Timeout: Call to Management API apim-RANDOM.management.azure-api.net:3443 timed out for the Developer SKU service which will have inherent capacity issues due to it's scale. Please refer to SLA at https://aka.ms/apimsla and considering upgrading to a SKU Tier with higher SLA.

- Deployment 'azure-ai-search-api' could not be found (this only will happen if you sett ```enableAzureAISearch``` to false and you can ignore it)