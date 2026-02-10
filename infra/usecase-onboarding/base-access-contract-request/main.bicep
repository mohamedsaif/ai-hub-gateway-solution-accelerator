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
// This delegates to the standard usecase-onboarding infrastructure

targetScope = 'subscription'

@description('APIM resource coordinates')
param apim object

@description('Target Key Vault for storing endpoint and API key secrets')
param keyVault object

@description('Use case descriptor')
param useCase object

@description('Catalog of existing AI services in APIM')
param existingServices object

@description('Services to onboard with generated policy')
param services array

@description('Product terms')
param productTerms string = ''

// Deploy using existing usecase-onboarding infrastructure
module onboarding '../main.bicep' = {
  name: 'agent-contract-${useCase.useCaseName}-${useCase.environment}'
  params: {
    apim: apim
    keyVault: keyVault
    useCase: useCase
    existingServices: existingServices
    services: services
    productTerms: productTerms
  }
}

output apimGatewayUrl string = onboarding.outputs.apimGatewayUrl
output products array = onboarding.outputs.products
output subscriptions array = onboarding.outputs.subscriptions
