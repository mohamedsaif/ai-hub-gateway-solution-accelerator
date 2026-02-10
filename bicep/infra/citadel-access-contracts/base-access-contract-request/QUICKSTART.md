# Quick Start Guide: Agent Access Contract Request

## What You'll Build

In this quick start, you'll create an access contract for an HR agent that needs:
- Access to GPT-4o, text-embedding-3-large, and deepseek-r1 models
- Per-model token limits and quotas
- Content safety with prompt shielding
- PII anonymization/deanonymization
- Custom usage tracking dimensions

## Prerequisites

- Python 3.7 or later
- Azure CLI
- Access to an Azure subscription with APIM and Key Vault
- Existing APIM instance with Azure OpenAI APIs configured

## Step 1: Clone and Navigate

```bash
cd infra/usecase-onboarding/base-access-contract-request
```

## Step 2: Create Your Contract Request

Use one of the provided examples or create your own JSON file:

**For a full-featured agent (like HR):**
```bash
cp examples/hr-agent-request.json my-agent-request.json
```

**For a simple agent (like Sales):**
```bash
cp examples/sales-agent-request.json my-agent-request.json
```

Edit `my-agent-request.json` to customize:
- Agent name and business unit
- Models and token limits
- Security features (content safety, PII handling)
- Usage tracking requirements

## Step 3: Validate Your Request

```bash
python3 tools/process_contract_request.py my-agent-request.json --validate-only
```

You should see: `✓ Contract request validation passed`

## Step 4: Generate Policy and Parameters

```bash
python3 tools/process_contract_request.py my-agent-request.json --output-dir ./generated
```

This creates:
- `generated/MyAgent-DEV-policy.xml` - The APIM policy
- `generated/MyAgent-DEV.parameters.json` - Bicep deployment parameters

## Step 5: Configure Azure Resources

Edit `generated/MyAgent-DEV.parameters.json` and update the placeholders:

```json
{
  "apim": {
    "subscriptionId": "your-subscription-id",
    "resourceGroupName": "your-apim-rg",
    "name": "your-apim-name"
  },
  "keyVault": {
    "subscriptionId": "your-subscription-id",
    "resourceGroupName": "your-kv-rg",
    "name": "your-kv-name"
  },
  "existingServices": {
    "OAI": {
      "apiResourceIds": [
        "/subscriptions/your-sub/resourceGroups/your-rg/providers/Microsoft.ApiManagement/service/your-apim/apis/azure-openai-service-api"
      ]
    }
  }
}
```

## Step 6: Add Policy to Parameters

Copy the content of `generated/MyAgent-DEV-policy.xml` and paste it into the `policyXml` field in the parameters file:

```json
{
  "services": {
    "value": [
      {
        "code": "OAI",
        "endpointSecretName": "AzureOpenAI-Endpoint",
        "apiKeySecretName": "AzureOpenAI-Key",
        "policyXml": "<policies><inbound>...paste policy XML here...</inbound>...</policies>"
      }
    ]
  }
}
```

**Tip**: Use a JSON-aware editor and escape the XML properly, or use a JSON string encoder.

## Step 7: Deploy

Deploy the contract using Azure CLI:

```bash
az deployment sub create \
  --name my-agent-contract-deployment \
  --location eastus \
  --template-file main.bicep \
  --parameters @generated/MyAgent-DEV.parameters.json
```

Or use the existing usecase-onboarding infrastructure directly:

```bash
az deployment sub create \
  --name my-agent-contract-deployment \
  --location eastus \
  --template-file ../main.bicep \
  --parameters @generated/MyAgent-DEV.parameters.json
```

## Step 8: Verify Deployment

Check the deployment outputs:

```bash
az deployment sub show \
  --name my-agent-contract-deployment \
  --query properties.outputs
```

You should see:
- `apimGatewayUrl`: Your APIM gateway URL
- `products`: Created product information
- `subscriptions`: Subscription details with Key Vault secret names

## Step 9: Test Your Agent

1. Retrieve the API key from Key Vault:
```bash
az keyvault secret show \
  --vault-name your-kv-name \
  --name azureopenai-key \
  --query value -o tsv
```

2. Make a test API call:
```bash
curl -X POST "https://your-apim.azure-api.net/openai/deployments/gpt-4o/chat/completions?api-version=2024-02-01" \
  -H "Ocp-Apim-Subscription-Key: YOUR-SUBSCRIPTION-KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 100
  }'
```

## Troubleshooting

### Validation Errors

If validation fails, check:
- All required fields are present (contractMetadata, accessRequirements)
- Model names are specified for each model
- JSON syntax is valid

### Deployment Errors

Common issues:
- **APIM not found**: Verify subscription ID, resource group, and APIM name
- **API not found**: Ensure the API resource IDs in existingServices are correct
- **Permission denied**: Ensure you have Contributor access to APIM and Secret Set permissions on Key Vault

### Policy Errors

If the policy doesn't work as expected:
- Review the generated policy XML for correctness
- Check APIM logs for policy execution errors
- Verify required APIM fragments exist (pii-anonymization, pii-deanonymization, pii-state-saving)

## Next Steps

- Review the [main README](README.md) for detailed documentation
- Explore the [Policy Snippets Reference](POLICY-SNIPPETS.md) to understand each policy component
- Create contracts for other agents in your organization
- Customize the templates for your specific governance requirements

## Examples

### Minimal Contract (Just Model Access)

```json
{
  "contractMetadata": {
    "agentName": "SimpleAgent",
    "businessUnit": "IT",
    "environment": "DEV"
  },
  "accessRequirements": {
    "models": [
      { "modelName": "gpt-4o" }
    ]
  }
}
```

### Contract with Content Safety Only

```json
{
  "contractMetadata": {
    "agentName": "SafeAgent",
    "businessUnit": "Support",
    "environment": "PROD"
  },
  "accessRequirements": {
    "models": [
      { "modelName": "gpt-4o" }
    ]
  },
  "contentSafety": {
    "enabled": true,
    "categories": [
      { "name": "Hate", "threshold": 6 },
      { "name": "Violence", "threshold": 6 }
    ]
  }
}
```

## Support

For issues, questions, or feature requests, please refer to the main repository documentation or open an issue on GitHub.
