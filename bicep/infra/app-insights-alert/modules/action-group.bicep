// ============================================================================
// Action Group — email notification target for AI Gateway alert rules
// Scope: resource group (deployed by ../main.bicep into the App Insights RG)
// ============================================================================

@description('Action group resource name.')
param name string

@description('Action group short name (max 12 characters). Shown as the SMS/email sender label.')
@maxLength(12)
param shortName string

@description('Email receivers for the action group. Each item: { name: string, email: string }.')
param emailReceivers array

@description('Whether the action group is enabled.')
param enabled bool = true

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: name
  location: 'Global'
  properties: {
    groupShortName: shortName
    enabled: enabled
    emailReceivers: [
      for receiver in emailReceivers: {
        name: receiver.name
        emailAddress: receiver.email
        // Common alert schema includes the alert rule description, fired dimension
        // values (alertType/productName/...), metric value and threshold in the email.
        useCommonAlertSchema: true
      }
    ]
  }
}

output id string = actionGroup.id
output name string = actionGroup.name
