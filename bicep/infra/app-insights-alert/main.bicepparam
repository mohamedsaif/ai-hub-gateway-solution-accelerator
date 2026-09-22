using 'main.bicep'

// ============================================================================
// AI Gateway — Application Insights Alerting Parameters
// ----------------------------------------------------------------------------
// Provisions Azure Monitor metric alerts on the gateway's "AI Gateway Alert"
// custom metric (emitted by the raise-alert-events APIM policy fragment) and an
// email Action Group.
//
// Values default to azd environment variables where available; override any
// value with a literal string as needed. See ./README.md.
// ============================================================================

// ----------------------------------------------------------------------------
// REQUIRED: Application Insights component the gateway emits metrics to.
// The hub's APIM logs to a component named "appi-apim-<token>" by default.
// ----------------------------------------------------------------------------
param appInsights = {
  subscriptionId: readEnvironmentVariable('AZURE_SUBSCRIPTION_ID', '00000000-0000-0000-0000-000000000000')
  resourceGroupName: readEnvironmentVariable('AZURE_RESOURCE_GROUP', 'REPLACE')
  name: readEnvironmentVariable('APIM_APP_INSIGHTS_NAME', 'REPLACE')
}

// Resource group for the alert rules + action group (defaults to the App Insights RG).
// param alertResourceGroupName = readEnvironmentVariable('AZURE_RESOURCE_GROUP', 'REPLACE')

// ----------------------------------------------------------------------------
// REQUIRED: email address that receives alert notifications.
// ----------------------------------------------------------------------------
param alertEmailAddress = readEnvironmentVariable('ALERT_EMAIL_ADDRESS', 'REPLACE@example.com')

// Optional additional recipients.
// param additionalEmailReceivers = [
//   { name: 'oncall', email: 'oncall@example.com' }
// ]

// Optional: scope every alert rule to a single access contract (product) name.
// NOTE: use the APIM product DISPLAY NAME emitted in the productName dimension (space-separated),
// NOT the hyphenated product id.
// param productNameFilter = 'LLM Ops AlertProbe DEV'

// Naming + metric identity (defaults match the shipped raise-alert-events fragment).
param namePrefix = 'ai-gateway'
param actionGroupShortName = 'aigwalerts'
param metricNamespace = 'ai-gateway-alerts'
param metricName = 'AI Gateway Alert'
param alertsEnabled = true

// Alerting mode:
//   'logQuery' (DEFAULT) — scheduled query alerts on the customMetrics table (work immediately).
//   'metric'             — metric alerts on the ai-gateway-alerts namespace (only after it registers).
param alertMode = 'logQuery'

// Alert rules. The defaults create throttling + backend-failure rules; extend
// with auth-failure / content-safety / pii-failure entries as needed.
param alerts = [
  {
    name: 'throttling'
    alertType: 'throttling'
    severity: 2
    operator: 'GreaterThan'
    threshold: 10
    timeAggregation: 'Total'
    windowSize: 'PT5M'
    evaluationFrequency: 'PT1M'
    description: 'AI Gateway throttling: the gateway returned HTTP 429 more than the threshold within the window. Likely a use case exceeded its per-minute token rate (TPM) or a backend ran out of capacity. Investigate the productName / deploymentName / backendId dimensions of the "AI Gateway Alert" metric. Remediation: review the access contract llm-token-limit tokens-per-minute, add backend pool capacity, or configure a model alias fallback. See guides/throttling-events-handling.md.'
  }
  {
    name: 'quota-exceeded'
    alertType: 'quota-exceeded'
    severity: 2
    operator: 'GreaterThan'
    threshold: 0
    timeAggregation: 'Total'
    windowSize: 'PT5M'
    evaluationFrequency: 'PT1M'
    description: 'AI Gateway token-quota exceeded: the gateway returned HTTP 403 (AITokenQuotaExceeded) because a use case exhausted its long-term token-quota for the period. All further calls for that use case are blocked until the quota window resets. Investigate the productName / deploymentName dimensions of the "AI Gateway Alert" metric. Remediation: raise the access contract llm-token-limit token-quota / shorten token-quota-period, or expect the use case to be blocked until reset. See guides/throttling-events-handling.md.'
  }
  {
    name: 'backend-failure'
    alertType: 'backend-failure'
    severity: 1
    operator: 'GreaterThan'
    threshold: 5
    timeAggregation: 'Total'
    windowSize: 'PT5M'
    evaluationFrequency: 'PT1M'
    description: 'AI Gateway backend failure: the gateway saw HTTP 5xx / connectivity errors from a backend more than the threshold within the window. Investigate the backendId / deploymentName dimensions. Remediation: check backend health, circuit-breaker state, and pool capacity. See guides/resiliency-guide.md.'
  }
]
