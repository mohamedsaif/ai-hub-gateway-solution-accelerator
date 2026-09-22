using '../../../bicep/infra/citadel-access-contracts/main.bicep'

param apim = {
  subscriptionId: 'd2e7f84f-2790-4baa-9520-59ae8169ed0d'
  resourceGroupName: 'rg-ai-hub-citadel-dev-108'
  name: 'apim-py4ruor5nefi4'
}
param keyVault = {
  subscriptionId: 'd2e7f84f-2790-4baa-9520-59ae8169ed0d'
  resourceGroupName: 'rg-ai-hub-citadel-dev-108'
  name: 'unused-kv'
}
param useTargetAzureKeyVault = false
param useCase = {
  businessUnit: 'Governance'
  useCaseName: 'PublishedAssets'
  environment: 'DEV'
}
param apiNameMapping = {
  MULTI: ['universal-llm-api', 'azure-openai-api', 'unified-ai-api', 'weather-tool', 'ms-learn-tool', 'hr-chat-agent']
}
param services = [
  {
    code: 'MULTI'
    endpointSecretName: 'PUBLISHED-ASSETS-ENDPOINT'
    apiKeySecretName: 'PUBLISHED-ASSETS-KEY'
    policyXml: loadTextContent('ai-product-policy.xml')
  }
]
param productTerms = 'Citadel Access Contract (mixed asset types) for publish-contract validation'
param useTargetFoundry = false
