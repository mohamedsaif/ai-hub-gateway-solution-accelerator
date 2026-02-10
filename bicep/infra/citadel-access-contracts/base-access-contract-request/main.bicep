// Main deployment file for Agent Access Contract
// This file deploys an access contract generated from an Agent Access Contract Request
// 
// Usage:
//   1. Process your Agent Access Contract Request JSON using the Python tool:
//      python tools/process_contract_request.py examples/hr-agent-request.json
//   
//   2. Update the generated parameters file with your APIM/Key Vault details
//   
//   3. Deploy using this Bicep file with the generated parameters:
//      az deployment sub create --template-file main.bicep --parameters @generated/HRAgent-DEV.parameters.json
//
// This delegates to the Citadel Access Contracts infrastructure

targetScope = 'subscription'

@description('APIM resource coordinates')
param apim object

@description('Target Key Vault for storing endpoint and API key secrets')
param keyVault object

@description('Whether to use Azure Key Vault for storing secrets')
param useTargetAzureKeyVault bool = true

@description('Use case descriptor')
param useCase object

@description('Map of service codes to their API names in APIM')
param apiNameMapping object

@description('Services to onboard with generated policy')
param services array

@description('Product terms')
param productTerms string = ''

@description('Whether to create Azure AI Foundry connection')
param useTargetFoundry bool = false

@description('Azure AI Foundry configuration')
param foundry object = {
  subscriptionId: ''
  resourceGroupName: ''
  accountName: ''
  projectName: ''
}

@description('Foundry connection configuration options')
param foundryConfig object = {
  connectionNamePrefix: ''
  deploymentInPath: 'false'
  isSharedToAll: false
  inferenceAPIVersion: ''
  deploymentAPIVersion: ''
}

// Deploy using Citadel Access Contracts infrastructure
module onboarding '../main.bicep' = {
  name: 'agent-contract-${useCase.useCaseName}-${useCase.environment}'
  params: {
    apim: apim
    keyVault: keyVault
    useTargetAzureKeyVault: useTargetAzureKeyVault
    useCase: useCase
    apiNameMapping: apiNameMapping
    services: services
    productTerms: productTerms
    useTargetFoundry: useTargetFoundry
    foundry: foundry
    foundryConfig: foundryConfig
  }
}

output apimGatewayUrl string = onboarding.outputs.apimGatewayUrl
output products array = onboarding.outputs.products
output subscriptions array = onboarding.outputs.subscriptions
