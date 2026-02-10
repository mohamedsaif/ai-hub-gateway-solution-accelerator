// Module to process Agent Access Contract Request JSON and generate APIM policy
targetScope = 'subscription'

@description('Agent Access Contract Request configuration')
param contractRequest object

@description('APIM resource coordinates')
param apim object

@description('Target Key Vault for storing endpoint and API key secrets')
param keyVault object

@description('Catalog of existing AI services in APIM')
param existingServices object

// Load template files
var masterPolicyTemplate = loadTextContent('../templates/master-policy-template.xml')
var allowedBackendsSnippet = loadTextContent('../templates/snippets/allowed-backends.xml')
var modelRestrictionsSnippet = loadTextContent('../templates/snippets/model-restrictions.xml')
var contentSafetySnippet = loadTextContent('../templates/snippets/content-safety.xml')
var modelSpecificTokenLimitsSnippet = loadTextContent('../templates/snippets/model-specific-token-limits.xml')
var globalTokenLimitsSnippet = loadTextContent('../templates/snippets/global-token-limits.xml')
var piiAnonymizationSnippet = loadTextContent('../templates/snippets/pii-anonymization.xml')
var piiDeanonymizationSnippet = loadTextContent('../templates/snippets/pii-deanonymization.xml')
var usageTrackingSnippet = loadTextContent('../templates/snippets/usage-tracking-variables.xml')

// Extract metadata
var metadata = contractRequest.contractMetadata
var accessReqs = contractRequest.accessRequirements
var contentSafety = contractRequest.?contentSafety ?? { enabled: false }
var piiHandling = contractRequest.?piiHandling ?? { enabled: false }
var usageTracking = contractRequest.?usageTracking ?? {}
var alerts = contractRequest.?alerts ?? {}

// Build product naming
var productPostfix = '${metadata.businessUnit}-${metadata.agentName}-${metadata.environment}'

// Generate allowed backends snippet
var allowedBackendsValue = contains(accessReqs, 'allowedBackends') && length(accessReqs.allowedBackends) > 0 
  ? join(accessReqs.allowedBackends, ',') 
  : ''
var allowedBackendsPolicy = allowedBackendsValue != '' 
  ? replace(allowedBackendsSnippet, '{{ALLOWED_BACKENDS}}', allowedBackendsValue)
  : ''

// Generate model restrictions snippet
var modelNames = [for m in accessReqs.?models ?? []: m.modelName]
var allowedModelsStr = join([for m in modelNames: '"${m}"'], ', ')
var modelRestrictionsPolicy = length(modelNames) > 0 
  ? replace(modelRestrictionsSnippet, '{{ALLOWED_MODELS}}', allowedModelsStr)
  : ''

// Generate content safety snippet
var contentSafetyPolicy = contentSafety.enabled ? generateContentSafetyPolicy(contentSafety, contentSafetySnippet) : ''

// Generate model-specific token limits
var modelTokenLimitCases = [for m in accessReqs.?models ?? []: contains(m, 'tokensPerMinute') || contains(m, 'tokenQuota') ? generateModelTokenLimitCase(m) : '']
var modelSpecificTokenLimitsPolicy = length(filter(modelTokenLimitCases, item => item != '')) > 0
  ? replace(modelSpecificTokenLimitsSnippet, '{{MODEL_TOKEN_LIMIT_CASES}}', join(filter(modelTokenLimitCases, item => item != ''), '\n'))
  : ''

// Generate global token limits
var hasGlobalLimits = contains(accessReqs, 'globalLimits') && 
  (contains(accessReqs.globalLimits, 'tokensPerMinute') || contains(accessReqs.globalLimits, 'tokenQuota'))
var globalTokenLimitsPolicy = hasGlobalLimits 
  ? generateGlobalTokenLimits(accessReqs.globalLimits, globalTokenLimitsSnippet)
  : ''

// Generate PII anonymization snippet
var piiAnonymizationPolicy = piiHandling.enabled 
  ? generatePiiAnonymizationPolicy(piiHandling, piiAnonymizationSnippet)
  : ''

// Generate PII deanonymization snippet
var piiDeanonymizationPolicy = piiHandling.enabled 
  ? generatePiiDeanonymizationPolicy(piiHandling, piiDeanonymizationSnippet)
  : ''

// Generate usage tracking variables
var usageTrackingPolicy = generateUsageTrackingPolicy(usageTracking, usageTrackingSnippet)

// Build custom policies
var customInboundPolicies = join(contractRequest.?additionalPolicies.?customInboundPolicies ?? [], '\n')
var customOutboundPolicies = join(contractRequest.?additionalPolicies.?customOutboundPolicies ?? [], '\n')

// Replace placeholders in master template
var policyXml = replace(
  replace(
    replace(
      replace(
        replace(
          replace(
            replace(
              replace(
                replace(masterPolicyTemplate, 
                  '<!-- PLACEHOLDER:ALLOWED_BACKENDS -->', allowedBackendsPolicy),
                '<!-- PLACEHOLDER:MODEL_RESTRICTIONS -->', modelRestrictionsPolicy),
              '<!-- PLACEHOLDER:CONTENT_SAFETY -->', contentSafetyPolicy),
            '<!-- PLACEHOLDER:MODEL_SPECIFIC_TOKEN_LIMITS -->', modelSpecificTokenLimitsPolicy),
          '<!-- PLACEHOLDER:GLOBAL_TOKEN_LIMITS -->', globalTokenLimitsPolicy),
        '<!-- PLACEHOLDER:PII_ANONYMIZATION -->', piiAnonymizationPolicy),
      '<!-- PLACEHOLDER:USAGE_TRACKING_VARIABLES -->', usageTrackingPolicy),
    '<!-- PLACEHOLDER:PII_DEANONYMIZATION -->', piiDeanonymizationPolicy),
  '<!-- PLACEHOLDER:CUSTOM_INBOUND_POLICIES -->', customInboundPolicies)
var finalPolicyXml = replace(policyXml, '<!-- PLACEHOLDER:CUSTOM_OUTBOUND_POLICIES -->', customOutboundPolicies)

// Helper function to generate content safety policy
func generateContentSafetyPolicy(config object, template string) string => 
  config.enabled ? 
    replace(
      replace(
        replace(
          replace(template, 
            '{{BACKEND_ID}}', config.?backendId ?? 'content-safety-backend'),
          '{{SHIELD_PROMPT}}', string(config.?shieldPrompt ?? false)),
        '{{APPLICABLE_MODELS}}', generateApplicableModels(config)),
      '{{CATEGORIES}}', generateContentSafetyCategories(config.?categories ?? []))
    : ''

func generateApplicableModels(config object) string =>
  contains(config, 'applicableModels') && length(config.applicableModels) > 0
    ? join([for m in config.applicableModels: '"${m}"'], ', ')
    : '""'

func generateContentSafetyCategories(categories array) string =>
  join([for c in categories: '<category name="${c.name}" threshold="${c.threshold}" />'], '\n        ')

// Helper function to generate model-specific token limit case
func generateModelTokenLimitCase(model object) string {
  var hasTPM = contains(model, 'tokensPerMinute')
  var hasQuota = contains(model, 'tokenQuota')
  var quotaParams = hasQuota ? 'token-quota="${model.tokenQuota}"\n      token-quota-period="${model.?tokenQuotaPeriod ?? 'Monthly'}"' : ''
  
  return hasTPM || hasQuota ? '''
  <when condition="@((string)context.Variables["target-deployment"] == "${model.modelName}")">
    <azure-openai-token-limit 
      counter-key="@(context.Subscription.Id + "-${model.modelName}")" 
      tokens-per-minute="${model.?tokensPerMinute ?? 1000}" 
      estimate-prompt-tokens="false" 
      tokens-consumed-header-name="consumed-tokens" 
      remaining-tokens-header-name="remaining-tokens" 
      ${quotaParams}
      retry-after-header-name="retry-after" />
  </when>''' : ''
}

// Helper function to generate global token limits
func generateGlobalTokenLimits(limits object, template string) string {
  var hasQuota = contains(limits, 'tokenQuota')
  var quotaParams = hasQuota ? 'token-quota="${limits.tokenQuota}"\n  token-quota-period="${limits.?tokenQuotaPeriod ?? 'Monthly'}"' : ''
  
  return replace(
    replace(template, 
      '{{TOKENS_PER_MINUTE}}', string(limits.?tokensPerMinute ?? 1000)),
    '{{TOKEN_QUOTA_PARAMS}}', quotaParams)
}

// Helper function to generate PII anonymization policy
func generatePiiAnonymizationPolicy(config object, template string) string {
  var regexPatternsStr = contains(config, 'customRegexPatterns') && length(config.customRegexPatterns) > 0
    ? join([for p in config.customRegexPatterns: '''
        new JObject {
          ["pattern"] = @"${p.pattern}",
          ["category"] = "${p.category}"
        }'''], ',')
    : ''
  
  var exclusionsStr = contains(config, 'entityCategoryExclusions') && length(config.entityCategoryExclusions) > 0
    ? join(config.entityCategoryExclusions, ',')
    : ''
  
  return replace(
    replace(
      replace(
        replace(template,
          '{{CONFIDENCE_THRESHOLD}}', string(config.?confidenceThreshold ?? 0.75)),
        '{{ENTITY_EXCLUSIONS}}', exclusionsStr),
      '{{DETECTION_LANGUAGE}}', config.?detectionLanguage ?? 'en'),
    '{{REGEX_PATTERNS}}', regexPatternsStr)
}

// Helper function to generate PII deanonymization policy
func generatePiiDeanonymizationPolicy(config object, template string) string {
  var stateSavingBlock = config.?stateSaving ?? false ? '''
    <set-variable name="piiStateSavingEnabled" value="true" />
    <set-variable name="originalRequest" value="@(context.Variables.GetValueOrDefault&lt;string&gt;("piiInputContent"))" />
    <set-variable name="originalResponse" value="@(context.Variables.GetValueOrDefault&lt;string&gt;("responseBodyContent"))" />
    
    <!-- Include the PII state saving fragment to push pii detection results to event hub -->
    <include-fragment fragment-id="pii-state-saving" />
    ''' : ''
  
  return replace(template, '{{STATE_SAVING_BLOCK}}', stateSavingBlock)
}

// Helper function to generate usage tracking policy
func generateUsageTrackingPolicy(config object, template string) string {
  var vars = []
  
  if (config.?trackEndUserId ?? false) {
    vars = union(vars, ['<set-variable name="endUserId" value="@(context.Request.Headers.GetValueOrDefault("endUserId", "NA-HEADER"))" />'])
  }
  
  if (config.?trackSessionId ?? false) {
    vars = union(vars, ['<set-variable name="sessionId" value="@(context.Request.Headers.GetValueOrDefault("sessionId", "NA-HEADER"))" />'])
  }
  
  if (config.?trackAppId ?? false) {
    vars = union(vars, ['<set-variable name="appId" value="@(context.Request.Headers.GetValueOrDefault("appId", "NA-HEADER"))" />'])
  }
  
  // Add custom dimensions
  if (contains(config, 'customDimensions') && length(config.customDimensions) > 0) {
    for dimension in config.customDimensions {
      vars = union(vars, ['<set-variable name="${dimension}" value="@(context.Request.Headers.GetValueOrDefault("${dimension}", "NA-HEADER"))" />'])
    }
  }
  
  return length(vars) > 0 ? replace(template, '{{USAGE_TRACKING_VARIABLES}}', join(vars, '\n')) : ''
}

// Build services array for existing usecase-onboarding module
var services = [
  {
    code: 'OAI'
    endpointSecretName: 'AzureOpenAI-Endpoint'
    apiKeySecretName: 'AzureOpenAI-Key'
    policyXml: finalPolicyXml
  }
]

// Build useCase object
var useCase = {
  businessUnit: metadata.businessUnit
  useCaseName: metadata.agentName
  environment: metadata.environment
}

// Deploy using existing usecase-onboarding infrastructure
module onboarding '../../main.bicep' = {
  name: 'contract-${metadata.agentName}-${metadata.environment}'
  params: {
    apim: apim
    keyVault: keyVault
    useCase: useCase
    existingServices: existingServices
    services: services
    productTerms: 'Agent Access Contract for ${metadata.agentName} in ${metadata.businessUnit}'
  }
}

output generatedPolicyXml string = finalPolicyXml
output productId string = 'OAI-${productPostfix}'
output apimGatewayUrl string = onboarding.outputs.apimGatewayUrl
output subscriptions array = onboarding.outputs.subscriptions
