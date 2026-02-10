# Policy Snippets Reference

This document provides a comprehensive reference of all available policy snippets used in the Agent Access Contract Request system.

## Overview

Policy snippets are modular, reusable XML templates that can be combined to create complete APIM policies. Each snippet addresses a specific concern (security, throttling, PII handling, etc.) and uses template variables that are replaced with actual values during policy generation.

## Available Snippets

### 1. Allowed Backends

**File**: `templates/snippets/allowed-backends.xml`

**Purpose**: Restrict access to specific backend services/regions

**Template Variables**:
- `{{ALLOWED_BACKENDS}}`: Comma-separated list of backend IDs

**JSON Configuration**:
```json
{
  "accessRequirements": {
    "allowedBackends": ["openai-backend-0", "openai-backend-1"]
  }
}
```

**Generated Policy**:
```xml
<set-variable name="allowedBackend" value="openai-backend-0,openai-backend-1" />
```

**When Applied**: When `accessRequirements.allowedBackends` is specified and not empty

---

### 2. Model Restrictions

**File**: `templates/snippets/model-restrictions.xml`

**Purpose**: Restrict access to specific AI models

**Template Variables**:
- `{{ALLOWED_MODELS}}`: Comma-separated list of quoted model names

**JSON Configuration**:
```json
{
  "accessRequirements": {
    "models": [
      { "modelName": "gpt-4o" },
      { "modelName": "text-embedding-3-large" }
    ]
  }
}
```

**Generated Policy**:
```xml
<choose>
  <when condition="@(!new [] { "gpt-4o", "text-embedding-3-large" }.Contains(context.Request.MatchedParameters["deployment-id"] ?? String.Empty))">
    <return-response>
      <set-status code="401" reason="Unauthorized model access" />
    </return-response>
  </when>
</choose>
```

**When Applied**: When `accessRequirements.models` is specified and contains at least one model

---

### 3. Content Safety

**File**: `templates/snippets/content-safety.xml`

**Purpose**: Apply Azure AI Content Safety checks to requests

**Template Variables**:
- `{{BACKEND_ID}}`: Content safety backend ID
- `{{SHIELD_PROMPT}}`: Enable/disable prompt shielding (true/false)
- `{{APPLICABLE_MODELS}}`: Comma-separated list of quoted model names
- `{{CATEGORIES}}`: Content safety category configurations

**JSON Configuration**:
```json
{
  "contentSafety": {
    "enabled": true,
    "backendId": "content-safety-backend",
    "shieldPrompt": true,
    "categories": [
      { "name": "Hate", "threshold": 4 },
      { "name": "Violence", "threshold": 4 }
    ],
    "applicableModels": ["gpt-4o"]
  }
}
```

**Generated Policy**:
```xml
<choose>
  <when condition="@(new [] { "gpt-4o" }.Contains(context.Request.MatchedParameters["deployment-id"] ?? String.Empty))">
    <llm-content-safety backend-id="content-safety-backend" shield-prompt="true">
      <categories output-type="EightSeverityLevels">
        <category name="Hate" threshold="4" />
        <category name="Violence" threshold="4" />
      </categories>
    </llm-content-safety>
  </when>
</choose>
```

**Categories**: Hate, Violence, Sexual, SelfHarm  
**Threshold Levels**: 0-8 (higher = more restrictive)

**When Applied**: When `contentSafety.enabled` is true

---

### 4. Model-Specific Token Limits

**File**: `templates/snippets/model-specific-token-limits.xml`

**Purpose**: Apply per-model token rate limits and quotas

**Template Variables**:
- `{{MODEL_TOKEN_LIMIT_CASES}}`: Generated when/choose cases for each model

**JSON Configuration**:
```json
{
  "accessRequirements": {
    "models": [
      {
        "modelName": "gpt-4o",
        "tokensPerMinute": 10000,
        "tokenQuota": 100000,
        "tokenQuotaPeriod": "Monthly"
      },
      {
        "modelName": "text-embedding-3-large",
        "tokensPerMinute": 5000
      }
    ]
  }
}
```

**Generated Policy**:
```xml
<set-variable name="target-deployment" value="@((string)context.Request.MatchedParameters["deployment-id"])" />
<choose>
  <when condition="@((string)context.Variables["target-deployment"] == "gpt-4o")">
    <azure-openai-token-limit 
      counter-key="@(context.Subscription.Id + "-gpt-4o")" 
      tokens-per-minute="10000" 
      estimate-prompt-tokens="false" 
      tokens-consumed-header-name="consumed-tokens" 
      remaining-tokens-header-name="remaining-tokens" 
      token-quota="100000"
      token-quota-period="Monthly"
      retry-after-header-name="retry-after" />
  </when>
  <when condition="@((string)context.Variables["target-deployment"] == "text-embedding-3-large")">
    <azure-openai-token-limit 
      counter-key="@(context.Subscription.Id + "-text-embedding-3-large")" 
      tokens-per-minute="5000" 
      estimate-prompt-tokens="false" 
      tokens-consumed-header-name="consumed-tokens" 
      remaining-tokens-header-name="remaining-tokens" 
      retry-after-header-name="retry-after" />
  </when>
  <otherwise>
    <azure-openai-token-limit 
      counter-key="@(context.Subscription.Id + "-default")" 
      tokens-per-minute="1000" 
      estimate-prompt-tokens="false" 
      tokens-consumed-header-name="consumed-tokens" 
      remaining-tokens-header-name="remaining-tokens" 
      retry-after-header-name="retry-after" />
  </otherwise>
</choose>
```

**Token Quota Periods**: Hourly, Daily, Weekly, Monthly

**When Applied**: When any model in `accessRequirements.models` has `tokensPerMinute` or `tokenQuota` specified

---

### 5. Global Token Limits

**File**: `templates/snippets/global-token-limits.xml`

**Purpose**: Apply token limits across all models at the product level

**Template Variables**:
- `{{TOKENS_PER_MINUTE}}`: Global TPM limit
- `{{TOKEN_QUOTA_PARAMS}}`: Optional quota parameters

**JSON Configuration**:
```json
{
  "accessRequirements": {
    "globalLimits": {
      "tokensPerMinute": 15000,
      "tokenQuota": 150000,
      "tokenQuotaPeriod": "Monthly"
    }
  }
}
```

**Generated Policy**:
```xml
<azure-openai-token-limit 
  counter-key="@(context.Product?.Name?.ToString() ?? "Portal-Admin")" 
  tokens-per-minute="15000" 
  estimate-prompt-tokens="false" 
  tokens-consumed-header-name="consumed-tokens" 
  remaining-tokens-header-name="remaining-tokens" 
  token-quota="150000"
  token-quota-period="Monthly"
  retry-after-header-name="retry-after" />
```

**When Applied**: When `accessRequirements.globalLimits` is specified with `tokensPerMinute` or `tokenQuota`

---

### 6. PII Anonymization

**File**: `templates/snippets/pii-anonymization.xml`

**Purpose**: Detect and anonymize PII in request content

**Template Variables**:
- `{{CONFIDENCE_THRESHOLD}}`: Detection confidence threshold (0.0-1.0)
- `{{ENTITY_EXCLUSIONS}}`: Comma-separated list of entity categories to exclude
- `{{DETECTION_LANGUAGE}}`: Language code for detection
- `{{REGEX_PATTERNS}}`: Custom regex patterns as JArray objects

**JSON Configuration**:
```json
{
  "piiHandling": {
    "enabled": true,
    "confidenceThreshold": 0.75,
    "detectionLanguage": "en",
    "entityCategoryExclusions": ["PersonType", "CADriversLicenseNumber"],
    "customRegexPatterns": [
      {
        "pattern": "\\b\\d{4}[- ]?\\d{4}[- ]?\\d{4}[- ]?\\d{4}\\b",
        "category": "CREDIT_CARD"
      },
      {
        "pattern": "\\b[A-Z]{2}\\d{6}[A-Z]\\b",
        "category": "PASSPORT_NUMBER"
      }
    ]
  }
}
```

**Generated Policy**:
```xml
<set-variable name="piiAnonymizationEnabled" value="true" />
<choose>
  <when condition="@(context.Variables.GetValueOrDefault<string>("piiAnonymizationEnabled") == "true")">
    <set-variable name="piiConfidenceThreshold" value="0.75" />
    <set-variable name="piiEntityCategoryExclusions" value="PersonType,CADriversLicenseNumber" />
    <set-variable name="piiDetectionLanguage" value="en" />
    
    <set-variable name="piiRegexPatterns" value="@{
      var patterns = new JArray {
        new JObject {
          ["pattern"] = @"\b\d{4}[- ]?\d{4}[- ]?\d{4}[- ]?\d{4}\b",
          ["category"] = "CREDIT_CARD"
        },
        new JObject {
          ["pattern"] = @"\b[A-Z]{2}\d{6}[A-Z]\b",
          ["category"] = "PASSPORT_NUMBER"
        }
      };
      return patterns.ToString();
    }" />
    <set-variable name="piiInputContent" value="@(context.Request.Body.As<string>(preserveContent: true))" />
    <include-fragment fragment-id="pii-anonymization" />
    <set-body>@(context.Variables.GetValueOrDefault<string>("piiAnonymizedContent"))</set-body>
  </when>
</choose>
```

**Prerequisites**: 
- APIM fragment `pii-anonymization` must exist
- Azure AI Language service configured

**When Applied**: When `piiHandling.enabled` is true

---

### 7. PII Deanonymization

**File**: `templates/snippets/pii-deanonymization.xml`

**Purpose**: Restore original PII in response content

**Template Variables**:
- `{{STATE_SAVING_BLOCK}}`: Optional PII state saving configuration

**JSON Configuration**:
```json
{
  "piiHandling": {
    "enabled": true,
    "stateSaving": true
  }
}
```

**Generated Policy** (with state saving):
```xml
<set-variable name="responseBodyContent" value="@(context.Response.Body.As<string>(preserveContent: true))" />
<choose>
  <when condition="@(context.Variables.GetValueOrDefault<string>("piiAnonymizationEnabled") == "true" && 
                  context.Variables.ContainsKey("piiMappings"))">
    <set-variable name="piiDeanonymizeContentInput" value="@(context.Variables.GetValueOrDefault<string>("responseBodyContent"))" />
    <include-fragment fragment-id="pii-deanonymization" />
    
    <set-variable name="piiStateSavingEnabled" value="true" />
    <set-variable name="originalRequest" value="@(context.Variables.GetValueOrDefault<string>("piiInputContent"))" />
    <set-variable name="originalResponse" value="@(context.Variables.GetValueOrDefault<string>("responseBodyContent"))" />
    <include-fragment fragment-id="pii-state-saving" />
    
    <set-body>@(context.Variables.GetValueOrDefault<string>("piiDeanonymizedContentOutput"))</set-body>
  </when>
  <otherwise>
    <set-body>@(context.Variables.GetValueOrDefault<string>("responseBodyContent"))</set-body>
  </otherwise>
</choose>
```

**Prerequisites**: 
- APIM fragments `pii-deanonymization` and optionally `pii-state-saving` must exist
- PII anonymization must be enabled

**When Applied**: When `piiHandling.enabled` is true (in outbound section)

---

### 8. Usage Tracking Variables

**File**: `templates/snippets/usage-tracking-variables.xml`

**Purpose**: Set variables for usage tracking and custom dimensions

**Template Variables**:
- `{{USAGE_TRACKING_VARIABLES}}`: Generated set-variable statements

**JSON Configuration**:
```json
{
  "usageTracking": {
    "customDimensions": ["departmentId", "employeeRegion"],
    "trackEndUserId": true,
    "trackSessionId": true,
    "trackAppId": true
  }
}
```

**Generated Policy**:
```xml
<set-variable name="endUserId" value="@(context.Request.Headers.GetValueOrDefault("endUserId", "NA-HEADER"))" />
<set-variable name="sessionId" value="@(context.Request.Headers.GetValueOrDefault("sessionId", "NA-HEADER"))" />
<set-variable name="appId" value="@(context.Request.Headers.GetValueOrDefault("appId", "NA-HEADER"))" />
<set-variable name="departmentId" value="@(context.Request.Headers.GetValueOrDefault("departmentId", "NA-HEADER"))" />
<set-variable name="employeeRegion" value="@(context.Request.Headers.GetValueOrDefault("employeeRegion", "NA-HEADER"))" />
```

**When Applied**: When any tracking option is enabled in `usageTracking`

---

## Policy Assembly Order

Policies are assembled in the following order within each section:

### Inbound Section
1. Allowed Backends
2. Model Restrictions
3. Content Safety
4. Model-Specific Token Limits
5. Global Token Limits
6. PII Anonymization
7. Usage Tracking Variables
8. Custom Inbound Policies

### Outbound Section
1. PII Deanonymization
2. Custom Outbound Policies

## Adding New Snippets

To add a new policy snippet:

1. **Create the snippet file** in `templates/snippets/`:
   ```xml
   <!-- Your policy snippet -->
   <your-policy-element attribute="{{TEMPLATE_VAR}}">
     {{NESTED_CONTENT}}
   </your-policy-element>
   ```

2. **Add placeholder** to `master-policy-template.xml`:
   ```xml
   <!-- PLACEHOLDER:YOUR_NEW_POLICY -->
   ```

3. **Update JSON schema** in `schemas/agent-access-contract-request.schema.json`:
   ```json
   {
     "yourNewPolicy": {
       "type": "object",
       "properties": {
         "enabled": { "type": "boolean" },
         "configParam": { "type": "string" }
       }
     }
   }
   ```

4. **Add processing logic** in `modules/processContractRequest.bicep`:
   ```bicep
   var yourNewPolicySnippet = loadTextContent('../templates/snippets/your-new-policy.xml')
   
   var yourNewPolicy = contractRequest.?yourNewPolicy.?enabled ?? false 
     ? replace(yourNewPolicySnippet, '{{TEMPLATE_VAR}}', contractRequest.yourNewPolicy.configParam)
     : ''
   
   var finalPolicyXml = replace(policyXml, '<!-- PLACEHOLDER:YOUR_NEW_POLICY -->', yourNewPolicy)
   ```

## Template Variable Escaping

When using template variables in policy expressions:
- Use `&lt;` for `<` in C# code
- Use `&gt;` for `>` in C# code
- Use `&amp;` for `&` in conditions
- Regular XML escaping applies for attribute values

Example:
```xml
<when condition="@(context.Variables.GetValueOrDefault&lt;string&gt;("var") == "value")">
```

## Best Practices

1. **Keep snippets focused**: Each snippet should address one concern
2. **Use meaningful template variables**: Make variable names self-explanatory
3. **Provide defaults**: Always have sensible default values
4. **Document prerequisites**: Note any required APIM fragments or backends
5. **Test thoroughly**: Validate generated policies before deployment
6. **Version control**: Track changes to snippets in source control

## Related Documentation

- [Master Policy Template](templates/master-policy-template.xml)
- [JSON Schema](schemas/agent-access-contract-request.schema.json)
- [Main README](README.md)
- [Azure APIM Policy Reference](https://learn.microsoft.com/en-us/azure/api-management/api-management-policies)
