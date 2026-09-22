/**
 * @module services/monitoring
 * @description Create-or-bring-your-own Log Analytics workspace and Application Insights
 *              components (APIM + Function/Logic App) for the gateway ecosystem.
 *
 *              This module does NOT provision private endpoints or Azure Monitor Private Link
 *              Scope. For an upgrade scenario it favours public ingestion; existing workspaces
 *              and components are referenced without changing their network configuration.
 *
 * Scope: Resource Group
 */

targetScope = 'resourceGroup'

@description('Location for created resources.')
param location string = resourceGroup().location

@description('Tags to apply to created resources.')
param tags object = {}

// ---------------------------------------------------------------------------
//  Log Analytics workspace
// ---------------------------------------------------------------------------

@description('Create a new Log Analytics workspace. When false, an existing workspace (BYO) is referenced.')
param createLogAnalytics bool = true

@description('Name of the Log Analytics workspace to create (only used when createLogAnalytics is true).')
param logAnalyticsName string = ''

@description('Name of the existing Log Analytics workspace (only used when createLogAnalytics is false).')
param existingLogAnalyticsName string = ''

@description('Resource group of the existing Log Analytics workspace. Defaults to the current resource group.')
param existingLogAnalyticsRG string = resourceGroup().name

@description('Subscription ID of the existing Log Analytics workspace. Defaults to the current subscription.')
param existingLogAnalyticsSubscriptionId string = subscription().subscriptionId

// ---------------------------------------------------------------------------
//  Application Insights components
// ---------------------------------------------------------------------------

@description('Create new Application Insights components. When false, existing components (BYO) are referenced by name.')
param createAppInsights bool = true

@description('Name of the APIM Application Insights component.')
param apimApplicationInsightsName string

@description('Name of the Function/Logic App Application Insights component.')
param functionApplicationInsightsName string

resource logAnalyticsNew 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (createLogAnalytics) {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    retentionInDays: 30
    features: {
      searchVersion: 1
    }
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource logAnalyticsExisting 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = if (!createLogAnalytics) {
  name: existingLogAnalyticsName
  scope: resourceGroup(existingLogAnalyticsSubscriptionId, existingLogAnalyticsRG)
}

var logAnalyticsWorkspaceId = createLogAnalytics ? logAnalyticsNew.id : logAnalyticsExisting.id

resource apimAppInsightsNew 'Microsoft.Insights/components@2020-02-02' = if (createAppInsights) {
  name: apimApplicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspaceId
  }
}

resource funcAppInsightsNew 'Microsoft.Insights/components@2020-02-02' = if (createAppInsights) {
  name: functionApplicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspaceId
  }
}

resource apimAppInsightsExisting 'Microsoft.Insights/components@2020-02-02' existing = if (!createAppInsights) {
  name: apimApplicationInsightsName
}

resource funcAppInsightsExisting 'Microsoft.Insights/components@2020-02-02' existing = if (!createAppInsights) {
  name: functionApplicationInsightsName
}

@description('Resource ID of the Log Analytics workspace (created or existing).')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspaceId

@description('Name of the APIM Application Insights component.')
output apimApplicationInsightsName string = apimApplicationInsightsName

@description('Name of the Function/Logic App Application Insights component.')
output funcApplicationInsightsName string = functionApplicationInsightsName

@description('Instrumentation key of the Function/Logic App Application Insights component.')
#disable-next-line BCP318
output funcApplicationInsightsInstrumentationKey string = createAppInsights ? funcAppInsightsNew.properties.InstrumentationKey : funcAppInsightsExisting.properties.InstrumentationKey

@description('Connection string of the APIM Application Insights component.')
#disable-next-line BCP318
output apimApplicationInsightsConnectionString string = createAppInsights ? apimAppInsightsNew.properties.ConnectionString : apimAppInsightsExisting.properties.ConnectionString
