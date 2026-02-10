#!/usr/bin/env python3
"""
Agent Access Contract Request Processor

This tool processes Agent Access Contract Request JSON files and generates:
1. APIM policy XML file
2. Bicep parameter file for deployment

Usage:
    python process_contract_request.py <contract-request-json-file> [options]

Options:
    --output-dir <dir>          Output directory for generated files (default: ./generated)
    --policy-output <file>      Custom path for generated policy XML
    --params-output <file>      Custom path for generated parameters file
    --validate-only             Only validate the JSON, don't generate files
"""

import json
import argparse
import sys
from pathlib import Path
from typing import Dict, List, Any, Optional

class ContractRequestProcessor:
    """Processes Agent Access Contract Requests and generates policy/parameter files"""
    
    def __init__(self, contract_json: Dict[str, Any], templates_dir: Path):
        self.contract = contract_json
        self.templates_dir = templates_dir
        self.master_template = self._load_template('master-policy-template.xml')
        
    def _load_template(self, filename: str) -> str:
        """Load a template file"""
        template_path = self.templates_dir / filename
        if not template_path.exists():
            raise FileNotFoundError(f"Template not found: {template_path}")
        return template_path.read_text()
    
    def _load_snippet(self, filename: str) -> str:
        """Load a policy snippet"""
        snippet_path = self.templates_dir / 'snippets' / filename
        if not snippet_path.exists():
            raise FileNotFoundError(f"Snippet not found: {snippet_path}")
        return snippet_path.read_text()
    
    def generate_policy_xml(self) -> str:
        """Generate the complete APIM policy XML"""
        policy = self.master_template
        
        # Replace each placeholder
        policy = policy.replace('<!-- PLACEHOLDER:ALLOWED_BACKENDS -->', self._generate_allowed_backends())
        policy = policy.replace('<!-- PLACEHOLDER:MODEL_RESTRICTIONS -->', self._generate_model_restrictions())
        policy = policy.replace('<!-- PLACEHOLDER:CONTENT_SAFETY -->', self._generate_content_safety())
        policy = policy.replace('<!-- PLACEHOLDER:MODEL_SPECIFIC_TOKEN_LIMITS -->', self._generate_model_token_limits())
        policy = policy.replace('<!-- PLACEHOLDER:GLOBAL_TOKEN_LIMITS -->', self._generate_global_token_limits())
        policy = policy.replace('<!-- PLACEHOLDER:PII_ANONYMIZATION -->', self._generate_pii_anonymization())
        policy = policy.replace('<!-- PLACEHOLDER:USAGE_TRACKING_VARIABLES -->', self._generate_usage_tracking())
        policy = policy.replace('<!-- PLACEHOLDER:CUSTOM_INBOUND_POLICIES -->', self._generate_custom_inbound())
        policy = policy.replace('<!-- PLACEHOLDER:PII_DEANONYMIZATION -->', self._generate_pii_deanonymization())
        policy = policy.replace('<!-- PLACEHOLDER:CUSTOM_OUTBOUND_POLICIES -->', self._generate_custom_outbound())
        
        return policy
    
    def _generate_allowed_backends(self) -> str:
        """Generate allowed backends policy snippet"""
        access_reqs = self.contract.get('accessRequirements', {})
        backends = access_reqs.get('allowedBackends', [])
        
        if not backends:
            return ''
        
        snippet = self._load_snippet('allowed-backends.xml')
        return snippet.replace('{{ALLOWED_BACKENDS}}', ','.join(backends))
    
    def _generate_model_restrictions(self) -> str:
        """Generate model restrictions policy snippet"""
        access_reqs = self.contract.get('accessRequirements', {})
        models = access_reqs.get('models', [])
        
        if not models:
            return ''
        
        model_names = [f'"{m["modelName"]}"' for m in models]
        snippet = self._load_snippet('model-restrictions.xml')
        return snippet.replace('{{ALLOWED_MODELS}}', ', '.join(model_names))
    
    def _generate_content_safety(self) -> str:
        """Generate content safety policy snippet"""
        content_safety = self.contract.get('contentSafety', {})
        
        if not content_safety.get('enabled', False):
            return ''
        
        snippet = self._load_snippet('content-safety.xml')
        
        # Replace backend ID
        backend_id = content_safety.get('backendId', 'content-safety-backend')
        snippet = snippet.replace('{{BACKEND_ID}}', backend_id)
        
        # Replace shield prompt
        shield_prompt = str(content_safety.get('shieldPrompt', False)).lower()
        snippet = snippet.replace('{{SHIELD_PROMPT}}', shield_prompt)
        
        # Replace applicable models
        applicable_models = content_safety.get('applicableModels', [])
        if applicable_models:
            models_str = ', '.join([f'"{m}"' for m in applicable_models])
        else:
            models_str = '""'
        snippet = snippet.replace('{{APPLICABLE_MODELS}}', models_str)
        
        # Replace categories
        categories = content_safety.get('categories', [])
        categories_xml = '\n        '.join([
            f'<category name="{cat["name"]}" threshold="{cat["threshold"]}" />'
            for cat in categories
        ])
        snippet = snippet.replace('{{CATEGORIES}}', categories_xml)
        
        return snippet
    
    def _generate_model_token_limits(self) -> str:
        """Generate model-specific token limits policy snippet"""
        access_reqs = self.contract.get('accessRequirements', {})
        models = access_reqs.get('models', [])
        
        # Filter models that have token limits
        models_with_limits = [m for m in models if 'tokensPerMinute' in m or 'tokenQuota' in m]
        
        if not models_with_limits:
            return ''
        
        # Build when cases for each model
        when_cases = []
        for model in models_with_limits:
            model_name = model['modelName']
            tpm = model.get('tokensPerMinute', 1000)
            
            when_case = f'''  <when condition="@((string)context.Variables["target-deployment"] == "{model_name}")">
    <azure-openai-token-limit 
      counter-key="@(context.Subscription.Id + "-{model_name}")" 
      tokens-per-minute="{tpm}" 
      estimate-prompt-tokens="false" 
      tokens-consumed-header-name="consumed-tokens" 
      remaining-tokens-header-name="remaining-tokens" '''
            
            if 'tokenQuota' in model:
                quota = model['tokenQuota']
                period = model.get('tokenQuotaPeriod', 'Monthly')
                when_case += f'\n      token-quota="{quota}"\n      token-quota-period="{period}"'
            
            when_case += '\n      retry-after-header-name="retry-after" />\n  </when>'
            when_cases.append(when_case)
        
        # Build complete policy
        policy = '''<!-- Capacity management - Subscription Level: allow only assigned tpm for each use case subscription -->
<set-variable name="target-deployment" value="@((string)context.Request.MatchedParameters["deployment-id"])" />
<choose>
'''
        policy += '\n'.join(when_cases)
        policy += '''
  <otherwise>
    <!-- Default token limit for models not explicitly configured -->
    <azure-openai-token-limit 
      counter-key="@(context.Subscription.Id + "-default")" 
      tokens-per-minute="1000" 
      estimate-prompt-tokens="false" 
      tokens-consumed-header-name="consumed-tokens" 
      remaining-tokens-header-name="remaining-tokens" 
      retry-after-header-name="retry-after" />
  </otherwise>
</choose>'''
        
        return policy
    
    def _generate_global_token_limits(self) -> str:
        """Generate global token limits policy snippet"""
        access_reqs = self.contract.get('accessRequirements', {})
        global_limits = access_reqs.get('globalLimits', {})
        
        if not global_limits:
            return ''
        
        snippet = self._load_snippet('global-token-limits.xml')
        
        # Replace TPM
        tpm = global_limits.get('tokensPerMinute', 1000)
        snippet = snippet.replace('{{TOKENS_PER_MINUTE}}', str(tpm))
        
        # Replace quota params
        if 'tokenQuota' in global_limits:
            quota = global_limits['tokenQuota']
            period = global_limits.get('tokenQuotaPeriod', 'Monthly')
            quota_params = f'token-quota="{quota}"\n  token-quota-period="{period}"'
        else:
            quota_params = ''
        
        snippet = snippet.replace('{{TOKEN_QUOTA_PARAMS}}', quota_params)
        
        return snippet
    
    def _generate_pii_anonymization(self) -> str:
        """Generate PII anonymization policy snippet"""
        pii_handling = self.contract.get('piiHandling', {})
        
        if not pii_handling.get('enabled', False):
            return ''
        
        snippet = self._load_snippet('pii-anonymization.xml')
        
        # Replace confidence threshold
        threshold = pii_handling.get('confidenceThreshold', 0.75)
        snippet = snippet.replace('{{CONFIDENCE_THRESHOLD}}', str(threshold))
        
        # Replace entity exclusions
        exclusions = pii_handling.get('entityCategoryExclusions', [])
        exclusions_str = ','.join(exclusions) if exclusions else ''
        snippet = snippet.replace('{{ENTITY_EXCLUSIONS}}', exclusions_str)
        
        # Replace detection language
        language = pii_handling.get('detectionLanguage', 'en')
        snippet = snippet.replace('{{DETECTION_LANGUAGE}}', language)
        
        # Replace regex patterns
        patterns = pii_handling.get('customRegexPatterns', [])
        if patterns:
            patterns_js = ',\n        '.join([
                f'''new JObject {{
          ["pattern"] = @"{p['pattern']}",
          ["category"] = "{p['category']}"
        }}'''
                for p in patterns
            ])
        else:
            patterns_js = ''
        snippet = snippet.replace('{{REGEX_PATTERNS}}', patterns_js)
        
        return snippet
    
    def _generate_pii_deanonymization(self) -> str:
        """Generate PII deanonymization policy snippet"""
        pii_handling = self.contract.get('piiHandling', {})
        
        if not pii_handling.get('enabled', False):
            return ''
        
        snippet = self._load_snippet('pii-deanonymization.xml')
        
        # Add state saving if enabled
        if pii_handling.get('stateSaving', False):
            state_saving_block = '''
    <set-variable name="piiStateSavingEnabled" value="true" />
    <set-variable name="originalRequest" value="@(context.Variables.GetValueOrDefault&lt;string&gt;("piiInputContent"))" />
    <set-variable name="originalResponse" value="@(context.Variables.GetValueOrDefault&lt;string&gt;("responseBodyContent"))" />
    
    <!-- Include the PII state saving fragment to push pii detection results to event hub -->
    <include-fragment fragment-id="pii-state-saving" />
    '''
        else:
            state_saving_block = ''
        
        snippet = snippet.replace('{{STATE_SAVING_BLOCK}}', state_saving_block)
        
        return snippet
    
    def _generate_usage_tracking(self) -> str:
        """Generate usage tracking variables policy snippet"""
        usage_tracking = self.contract.get('usageTracking', {})
        
        variables = []
        
        if usage_tracking.get('trackEndUserId', False):
            variables.append('<set-variable name="endUserId" value="@(context.Request.Headers.GetValueOrDefault(&quot;endUserId&quot;, &quot;NA-HEADER&quot;))" />')
        
        if usage_tracking.get('trackSessionId', False):
            variables.append('<set-variable name="sessionId" value="@(context.Request.Headers.GetValueOrDefault(&quot;sessionId&quot;, &quot;NA-HEADER&quot;))" />')
        
        if usage_tracking.get('trackAppId', False):
            variables.append('<set-variable name="appId" value="@(context.Request.Headers.GetValueOrDefault(&quot;appId&quot;, &quot;NA-HEADER&quot;))" />')
        
        # Add custom dimensions
        custom_dims = usage_tracking.get('customDimensions', [])
        for dim in custom_dims:
            variables.append(f'<set-variable name="{dim}" value="@(context.Request.Headers.GetValueOrDefault(&quot;{dim}&quot;, &quot;NA-HEADER&quot;))" />')
        
        if variables:
            return '<!-- Set variables for OpenAI usage logging -->\n' + '\n'.join(variables)
        return ''
    
    def _generate_custom_inbound(self) -> str:
        """Generate custom inbound policies"""
        additional = self.contract.get('additionalPolicies', {})
        custom_inbound = additional.get('customInboundPolicies', [])
        return '\n'.join(custom_inbound)
    
    def _generate_custom_outbound(self) -> str:
        """Generate custom outbound policies"""
        additional = self.contract.get('additionalPolicies', {})
        custom_outbound = additional.get('customOutboundPolicies', [])
        return '\n'.join(custom_outbound)
    
    def generate_bicep_parameters(self, apim_config: Dict, kv_config: Dict, existing_services: Dict) -> Dict:
        """Generate Bicep deployment parameters"""
        metadata = self.contract['contractMetadata']
        
        params = {
            "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
            "contentVersion": "1.0.0.0",
            "parameters": {
                "apim": {"value": apim_config},
                "keyVault": {"value": kv_config},
                "useCase": {
                    "value": {
                        "businessUnit": metadata['businessUnit'],
                        "useCaseName": metadata['agentName'],
                        "environment": metadata['environment']
                    }
                },
                "existingServices": {"value": existing_services},
                "services": {
                    "value": [
                        {
                            "code": "OAI",
                            "endpointSecretName": "AzureOpenAI-Endpoint",
                            "apiKeySecretName": "AzureOpenAI-Key",
                            "policyXml": ""  # Will be filled from generated policy file
                        }
                    ]
                },
                "productTerms": {
                    "value": f"Agent Access Contract for {metadata['agentName']} in {metadata['businessUnit']}"
                }
            }
        }
        
        return params


def validate_contract_request(contract: Dict) -> List[str]:
    """Validate the contract request JSON"""
    errors = []
    
    # Check required top-level keys
    required_keys = ['contractMetadata', 'accessRequirements']
    for key in required_keys:
        if key not in contract:
            errors.append(f"Missing required field: {key}")
    
    if 'contractMetadata' in contract:
        metadata = contract['contractMetadata']
        required_metadata = ['agentName', 'businessUnit', 'environment']
        for key in required_metadata:
            if key not in metadata:
                errors.append(f"Missing required contractMetadata field: {key}")
    
    if 'accessRequirements' in contract:
        access_reqs = contract['accessRequirements']
        if 'models' in access_reqs:
            for i, model in enumerate(access_reqs['models']):
                if 'modelName' not in model:
                    errors.append(f"Model at index {i} is missing 'modelName'")
    
    return errors


def main():
    parser = argparse.ArgumentParser(
        description='Process Agent Access Contract Request JSON and generate policy/parameter files'
    )
    parser.add_argument('contract_file', help='Path to the Agent Access Contract Request JSON file')
    parser.add_argument('--output-dir', default='./generated', help='Output directory for generated files')
    parser.add_argument('--policy-output', help='Custom path for generated policy XML')
    parser.add_argument('--params-output', help='Custom path for generated parameters file')
    parser.add_argument('--validate-only', action='store_true', help='Only validate the JSON')
    
    args = parser.parse_args()
    
    # Load contract request
    contract_path = Path(args.contract_file)
    if not contract_path.exists():
        print(f"Error: Contract file not found: {contract_path}", file=sys.stderr)
        sys.exit(1)
    
    with open(contract_path, 'r') as f:
        contract = json.load(f)
    
    # Validate
    errors = validate_contract_request(contract)
    if errors:
        print("Validation errors:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        sys.exit(1)
    
    print("✓ Contract request validation passed")
    
    if args.validate_only:
        sys.exit(0)
    
    # Find templates directory
    script_dir = Path(__file__).parent
    templates_dir = script_dir.parent / 'templates'
    
    if not templates_dir.exists():
        print(f"Error: Templates directory not found: {templates_dir}", file=sys.stderr)
        sys.exit(1)
    
    # Process contract
    processor = ContractRequestProcessor(contract, templates_dir)
    
    # Generate policy XML
    policy_xml = processor.generate_policy_xml()
    
    # Determine output paths
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    agent_name = contract['contractMetadata']['agentName']
    env = contract['contractMetadata']['environment']
    
    policy_output = Path(args.policy_output) if args.policy_output else output_dir / f'{agent_name}-{env}-policy.xml'
    params_output = Path(args.params_output) if args.params_output else output_dir / f'{agent_name}-{env}.parameters.json'
    
    # Write policy XML
    policy_output.write_text(policy_xml)
    print(f"✓ Generated policy XML: {policy_output}")
    
    # Generate parameter template (user needs to fill in APIM/KV details)
    params = processor.generate_bicep_parameters(
        apim_config={
            "subscriptionId": "<sub-guid>",
            "resourceGroupName": "<apim-rg>",
            "name": "<apim-name>"
        },
        kv_config={
            "subscriptionId": "<sub-guid>",
            "resourceGroupName": "<kv-rg>",
            "name": "<kv-name>"
        },
        existing_services={
            "OAI": {
                "apiResourceIds": [
                    "/subscriptions/<sub-guid>/resourceGroups/<apim-rg>/providers/Microsoft.ApiManagement/service/<apim-name>/apis/azure-openai-service-api"
                ]
            }
        }
    )
    
    with open(params_output, 'w') as f:
        json.dump(params, f, indent=2)
    
    print(f"✓ Generated parameters file: {params_output}")
    print(f"\nNext steps:")
    print(f"1. Review the generated policy XML: {policy_output}")
    print(f"2. Update the parameters file with your APIM and Key Vault details: {params_output}")
    print(f"3. Add the generated policy XML content to the policyXml field in the parameters file")
    print(f"4. Deploy using: az deployment sub create --template-file infra/usecase-onboarding/main.bicep --parameters @{params_output}")


if __name__ == '__main__':
    main()
