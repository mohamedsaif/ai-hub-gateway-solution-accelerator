using 'main.bicep'

// Deploy this module at subscription scope:
// az deployment sub create --name citadel-cosmos-global-sync --location swedencentral --template-file main.bicep --parameters main.bicepparam

param gatewayImplementations = [
  {
    name: 'gateway-se'
    subscriptionId: '00000000-0000-0000-0000-000000000000'
    resourceGroupName: 'rg-aihub-se-prod'
    cosmosDbAccountName: 'cosmos-aihub-se-prod'
    region: 'swedencentral'
  }
  {
    name: 'gateway-us'
    subscriptionId: '00000000-0000-0000-0000-000000000000'
    resourceGroupName: 'rg-aihub-us-prod'
    cosmosDbAccountName: 'cosmos-aihub-us-prod'
    region: 'eastus2'
  }
]

// Optional: add more write regions beyond the gateway primary regions.
param additionalWriteRegions = [
  'westeurope'
]

param systemManagedFailover = true
param isZoneRedundant = false
