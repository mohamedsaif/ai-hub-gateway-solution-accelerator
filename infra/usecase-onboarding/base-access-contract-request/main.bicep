// Main deployment file for Agent Access Contract Request
targetScope = 'subscription'

@description('Path to Agent Access Contract Request JSON file or the JSON object itself')
param contractRequestJson object

@description('APIM resource coordinates')
param apim object

@description('Target Key Vault for storing endpoint and API key secrets')
param keyVault object

@description('Catalog of existing AI services in APIM')
param existingServices object

// Process the contract request
module processContract 'modules/processContractRequest.bicep' = {
  name: 'process-contract-${contractRequestJson.contractMetadata.agentName}'
  params: {
    contractRequest: contractRequestJson
    apim: apim
    keyVault: keyVault
    existingServices: existingServices
  }
}

output generatedPolicyXml string = processContract.outputs.generatedPolicyXml
output productId string = processContract.outputs.productId
output apimGatewayUrl string = processContract.outputs.apimGatewayUrl
output subscriptions array = processContract.outputs.subscriptions
