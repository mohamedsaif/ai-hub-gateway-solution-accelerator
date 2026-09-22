/**
 * @module services/managed-identity
 * @description Create-or-bring-your-own user-assigned managed identity for the gateway ecosystem.
 *              When `createNew` is true a new identity is provisioned; otherwise an existing
 *              identity is referenced (BYO) and only the requested role assignments are applied.
 *
 *              This module NEVER changes any network configuration of an existing identity.
 *              Role assignments are additive and idempotent (guid-named).
 *
 * Scope: Resource Group
 */

targetScope = 'resourceGroup'

@description('Create a new user-assigned managed identity. When false, an existing identity (BYO) is referenced by name.')
param createNew bool = true

@description('Name of the user-assigned managed identity to create or reference.')
param name string

@description('Location for the managed identity (only used when createNew is true).')
param location string = resourceGroup().location

@description('Tags to apply (only used when createNew is true).')
param tags object = {}

@description('Assign the Cognitive Services User role at resource-group scope (APIM identity pattern).')
param assignCognitiveServicesUser bool = false

@description('Assign the Cognitive Services OpenAI User role at resource-group scope (APIM identity pattern).')
param assignCognitiveServicesOpenAIUser bool = false

@description('Assign the Azure Event Hubs Data Sender role at resource-group scope (APIM identity pattern).')
param assignEventHubsDataSender bool = false

@description('Assign the Azure Event Hubs Data Owner role at resource-group scope (usage identity pattern).')
param assignEventHubsDataOwner bool = false

// Built-in role definition IDs
var cognitiveServicesOpenAIUserRoleDefinitionId = resourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
var cognitiveServicesUserRoleDefinitionId = resourceId('Microsoft.Authorization/roleDefinitions', 'a97b65f3-24c7-4388-baec-2e87135dc908')
var eventHubsDataSenderRoleDefinitionId = resourceId('Microsoft.Authorization/roleDefinitions', '2b629674-e913-4c01-ae53-ef4638d8f975')
var eventHubsDataOwnerRoleDefinitionId = resourceId('Microsoft.Authorization/roleDefinitions', 'f526a384-b230-433a-b45c-95f59c4a2dec')

resource managedIdentityNew 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (createNew) {
  name: name
  location: location
  tags: union(tags, { 'azd-service-name': name })
}

resource managedIdentityExisting 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = if (!createNew) {
  name: name
}

#disable-next-line BCP318
var principalId = createNew ? managedIdentityNew.properties.principalId : managedIdentityExisting.properties.principalId
#disable-next-line BCP318
var clientId = createNew ? managedIdentityNew.properties.clientId : managedIdentityExisting.properties.clientId
var identityResourceId = createNew ? managedIdentityNew.id : managedIdentityExisting.id

resource cognitiveServicesUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (assignCognitiveServicesUser) {
  name: guid(identityResourceId, cognitiveServicesUserRoleDefinitionId, resourceGroup().id)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: cognitiveServicesUserRoleDefinitionId
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

resource cognitiveServicesOpenAIUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (assignCognitiveServicesOpenAIUser) {
  name: guid(identityResourceId, cognitiveServicesOpenAIUserRoleDefinitionId, resourceGroup().id)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: cognitiveServicesOpenAIUserRoleDefinitionId
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

resource eventHubsDataSenderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (assignEventHubsDataSender) {
  name: guid(identityResourceId, eventHubsDataSenderRoleDefinitionId, resourceGroup().id)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: eventHubsDataSenderRoleDefinitionId
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

resource eventHubsDataOwnerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (assignEventHubsDataOwner) {
  name: guid(identityResourceId, eventHubsDataOwnerRoleDefinitionId, resourceGroup().id)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: eventHubsDataOwnerRoleDefinitionId
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

@description('Name of the managed identity (created or existing).')
output managedIdentityName string = name

@description('Resource ID of the managed identity (created or existing).')
output managedIdentityId string = identityResourceId

@description('Principal (object) ID of the managed identity.')
output managedIdentityPrincipalId string = principalId

@description('Client ID of the managed identity.')
output managedIdentityClientId string = clientId
