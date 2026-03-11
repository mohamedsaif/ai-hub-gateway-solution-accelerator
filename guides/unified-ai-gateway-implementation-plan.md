# Unified AI Gateway – Technical Implementation Plan

> **Status: IMPLEMENTED** — This plan has been fully implemented. The changes described below are live in the codebase on the `citadel-v1-unified-gateway` branch.

## Executive Summary

This plan extends the AI Hub Gateway Solution Accelerator with a **Unified AI Gateway** – a third wildcard APIM API endpoint that joins the existing Azure OpenAI API and Universal LLM API. All three API endpoints share a **single unified fragment pipeline** with metadata-driven configuration auto-generated from the Backend Onboarding `llmBackendConfig`. There is **no duplication** of central configurations – the same shared fragments power every endpoint.

This design is inspired by the [APIM-Unified-AI-Gateway-Sample](https://github.com/Azure-Samples/APIM-Unified-AI-Gateway-Sample) which uses a `/*` wildcard path, metadata-driven configuration, and a modular policy fragment pipeline.

### Key Objectives

1. **Three API endpoints, one pipeline**: Azure OpenAI API (`/openai/*`), Universal LLM API (`/models/*`), and new Unified AI Gateway (`/unified-ai/*`) all share the same fragment set and backend configuration
2. **API Key always required**: APIM subscription (API Key) is mandatory on every product. JWT (Entra ID) is an optional additional security layer activated per-product via Access Contract policy
3. **Metadata-driven routing**: Centralized JSON configuration (`metadata-config` fragment) replaces generated C# code injection approach. Auto-generated from `llmBackendConfig` by Backend Onboarding
4. **Zero duplication**: No `unified-` prefixed fragment copies. All APIs consume the same fragments with the same variable contracts
5. **Unified model extraction and authorization**: A single model extraction flow handles `MatchedParameters["deployment-id"]` (Azure OpenAI), body `model` field (Inference), and path analysis (wildcard)
6. **Discovery endpoints**: `/deployments` and `/deployments/{deploymentname}` continue to work, honoring Access Contract `allowedModels` filtering, now powered by metadata-config
7. **Extended backendconfig**: `llmBackendConfig` gains new per-model attributes (`tier`, `apiVersion`, `timeout`) so metadata-config is fully generated from a single source of truth

---

## 1. Architecture Overview

### Current State

```
Client                     APIM Gateway                         Backends
  │                            │                                   │
  ├── /models/*  ──────────►  Universal LLM API  ──────────────►  AI Foundry / OpenAI
  │   (AzureAI format)        (aad-auth                           (Backend Pools)
  │                            set-llm-requested-model
  │                            set-backend-pools      ← C# code injection
  │                            set-target-backend-pool
  │                            set-backend-authorization
  │                            set-llm-usage)
  │
  ├── /openai/*  ──────────►  Azure OpenAI API   ──────────────►  AI Foundry / OpenAI
  │   (AzureOpenAI format)    (Same fragment chain + rewrite)     (Backend Pools)
  │
  ├── /search/*  ──────────►  AI Search API      ──────────────►  Azure AI Search
  └── /doc-intel/*  ───────►  Doc Intelligence    ──────────────►  Document Intelligence
```

**Authentication**: Either API Key **OR** JWT (mutually exclusive via `entraAuth` parameter)
**Backend Config**: Generated C# code injected into `set-backend-pools` and `get-available-models` fragments
**Discovery**: `/deployments` and `/deployments/{name}` with C# generated model list

### Target State

```
Client                     APIM Gateway                                Backends
  │                            │                                          │
  │                    ┌──── SHARED FRAGMENT PIPELINE ────┐               │
  │                    │ 1. metadata-config (JSON)        │               │
  │                    │ 2. central-cache-manager          │               │
  │                    │ 3. request-processor              │               │
  │                    │ 4. aad-auth (API Key always,     │               │
  │                    │    JWT optional per-product)      │               │
  │                    │ 5. validate-model-access          │               │
  │                    │ 6. backend-selector               │               │
  │                    │ 7. path-builder                   │               │
  │                    │ 8. set-llm-usage                  │               │
  │                    │ 9. diagnostic-headers (outbound)  │               │
  │                    └──────────────────────────────────┘               │
  │                                    │                                  │
  ├── /openai/*  ──────────────────────┤                                  │
  │   (Azure OpenAI format)            ├─────────────────────────────────►│
  ├── /models/*  ──────────────────────┤                                  │
  │   (AI Inference format)            │  Backend Pools / Direct Backends │
  ├── /unified-ai/*  ──────────────────┤                                  │
  │   (Any format, wildcard)           │                                  │
  │                                    │                                  │
  │ All endpoints:                     │                                  │
  │  • subscriptionRequired: true      │                                  │
  │  • JWT optional via product policy │                                  │
  │  • /deployments discovery          │                                  │
  └────────────────────────────────────┘                                  │
```

**Authentication**: API Key (APIM subscription) ALWAYS required. JWT is an additional optional layer activated per-product.
**Backend Config**: Metadata-config JSON auto-generated from `llmBackendConfig` by Backend Onboarding
**Discovery**: `/deployments` and `/deployments/{name}` powered by metadata-config (replaces C# code injection)

### Shared Fragment Pipeline

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         INBOUND PIPELINE (shared by all 3 APIs)              │
│                                                                              │
│  ┌──────────────┐    ┌──────────────────┐    ┌────────────────────────────┐  │
│  │ metadata-    │───►│ central-cache-   │───►│ request-processor          │  │
│  │ config       │    │ manager          │    │                            │  │
│  │  (NEW)       │    │  (NEW)           │    │  (NEW)                     │  │
│  │              │    │                  │    │ • Detects api-type from    │  │
│  │ JSON config  │    │ Caches parsed    │    │   api-endpoint-type var    │  │
│  │ auto-gen     │    │ config in APIM   │    │   or path analysis         │  │
│  │ from backend │    │ cache. Version-  │    │ • Extracts model from      │  │
│  │ onboarding   │    │ based invalidate │    │   MatchedParams/body/path  │  │
│  │              │    │                  │    │ • Sets requestedModel      │  │
│  └──────────────┘    └──────────────────┘    └───────────┬────────────────┘  │
│                                                          │                   │
│  ┌──────────────────┐  ┌───────────────────┐  ┌──────────▼─────────────┐     │
│  │ validate-model-  │◄─│ aad-auth          │◄─│ (api-key validated     │     │
│  │ access           │  │  (MODIFIED)       │  │  by APIM subscription  │     │
│  │  (UNCHANGED)     │  │                   │  │  automatically on all  │     │
│  │                  │  │ JWT optional per-  │  │  products)             │     │
│  │ Checks           │  │ product. Reads    │  └────────────────────────┘     │
│  │ requestedModel   │  │ jwt-auth-required │                                 │
│  │ vs allowedModels │  │ variable from     │                                 │
│  └──────┬───────────┘  │ product policy    │                                 │
│         │              └───────────────────┘                                 │
│  ┌──────▼───────────┐  ┌───────────────────┐  ┌────────────────────────┐     │
│  │ backend-selector │─►│ path-builder      │─►│ set-llm-usage          │     │
│  │  (REPLACES       │  │  (NEW)            │  │  (EXTENDED)            │     │
│  │   set-backend-   │  │                   │  │                        │     │
│  │   pools +        │  │ Constructs URL per │  │ Token metrics with     │     │
│  │   set-target-    │  │ api-type + model.  │  │ api-type dimension     │     │
│  │   backend-pool + │  │ Handles auth for   │  │                        │     │
│  │   set-backend-   │  │ backend (MI, key)  │  │                        │     │
│  │   authorization) │  │                   │  │                        │     │
│  └──────────────────┘  └───────────────────┘  └────────────────────────┘     │
│                                                                              │
│  OUTBOUND: diagnostic-headers (NEW) - UAIG-* response headers               │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Breaking Changes & Impact Analysis

### 2.1 Authentication Model Change (BREAKING)

| Aspect | Current Behavior | New Behavior | Impact |
|--------|-----------------|--------------|--------|
| **API Key** | Required on some products, not on JWT products | **Always required** on ALL products (`subscriptionRequired: true` on every product) | **BREAKING**: Any existing JWT-only products must add subscription requirement |
| **JWT (Entra ID)** | Toggled globally via `entraAuth` named value (boolean). Mutually exclusive with API Key | **Optional per-product**. Product policy sets `jwt-auth-required` variable to activate JWT validation as an additional layer on top of API Key | **BREAKING**: `entraAuth` global toggle is removed. JWT activation moves to product-level policy |
| **Auth flow** | Either API Key validates subscription OR JWT validates token | API Key always validated by APIM subscription. If product sets `jwt-auth-required=true`, JWT is additionally validated after subscription auth | **BREAKING**: Two-layer model replaces either/or model |

### 2.2 Fragment Pipeline Changes (BREAKING for existing APIs)

| Aspect | Current Behavior | New Behavior | Impact |
|--------|-----------------|--------------|--------|
| **Fragment set** | `aad-auth` → `set-llm-requested-model` → `set-backend-pools` → `set-target-backend-pool` → `set-backend-authorization` → `set-llm-usage` | `metadata-config` → `central-cache-manager` → `request-processor` → `aad-auth` → `validate-model-access` → `backend-selector` → `path-builder` → `set-llm-usage` | **BREAKING**: All 3 API policies must switch to new pipeline |
| **Retired fragments** | `set-backend-pools`, `set-target-backend-pool`, `set-backend-authorization`, `set-llm-requested-model` | Functionality merged into `request-processor`, `backend-selector`, `path-builder` | **BREAKING**: Old fragments no longer used by API policies |
| **Variable contract** | `requestedModel`, `targetBackendPool`, `targetPoolType`, `backendPools` JArray | `requestedModel` (unchanged name), `model-id` (alias), `api-type`, `selected-backend`, `config-models` JObject | **BREAKING**: Downstream consumers must use new variable names |

### 2.3 Backend Onboarding Changes (BREAKING - extended config)

| Aspect | Current Behavior | New Behavior | Impact |
|--------|-----------------|--------------|--------|
| **`llmBackendConfig` schema** | Per-model: `name`, `sku`, `capacity`, `modelFormat`, `modelVersion`, `retirementDate` | Per-model adds: `tier` (premium/standard), `apiVersion`, `inferenceApiVersion`, `timeout` | **BREAKING**: New required attributes in `llmBackendConfig[].supportedModels[]` |
| **Generated fragments** | C# code injected into `set-backend-pools` and `get-available-models` templates | Generates `metadata-config` JSON fragment instead. Discovery endpoint reads from `config-models`. Old C# generation removed | **BREAKING**: `frag-set-backend-pools.xml` and `frag-get-available-models.xml` templates replaced by `metadata-config` generation |
| **Output** | `backendPoolsCode` and `modelDeploymentsCode` C# strings | `metadata-config` JSON string with models, api-types, cache-settings, timeout-settings | **BREAKING**: Different output format |

### 2.4 Access Contract Changes (NON-BREAKING)

| Aspect | Current Behavior | New Behavior | Impact |
|--------|-----------------|--------------|--------|
| **`apiNameMapping`** | `LLM: ['universal-llm-api', 'azure-openai-api']` | Adds `UAI: ['unified-ai-gateway-api']` alongside existing mappings. `LLM` mapping updated to include all 3 APIs | **Non-breaking**: Additive |
| **Product policy template** | Sets `allowedModels`, capacity limits, usage tracking | Same + optionally sets `jwt-auth-required` variable for JWT layer | **Non-breaking**: Additive variable |
| **Discovery endpoints** | `/deployments` and `/deployments/{name}` via C# generated model list | Same endpoints via metadata-config. Same `allowedModels` filtering | **Non-breaking**: Same external behavior |

### 2.5 Summary

1. **All 3 API endpoints migrate to the new shared fragment pipeline** – this is a clean replacement, not a parallel approach
2. **API Key is always on** – `subscriptionRequired: true` on every product
3. **JWT moves from global toggle to per-product opt-in** via `jwt-auth-required` variable in product policy
4. **`llmBackendConfig` schema extends** with `tier`, `apiVersion`, `inferenceApiVersion`, `timeout` per model
5. **Backend Onboarding generates `metadata-config` JSON** instead of C# code injection
6. **Old fragments retired**: `set-backend-pools`, `set-target-backend-pool`, `set-backend-authorization`, `set-llm-requested-model` replaced by `request-processor`, `backend-selector`, `path-builder`

---

## 3. Implementation Phases

### Phase 1: Shared Fragment Pipeline

**Goal**: Replace the existing per-API fragment chains with a single shared fragment set consumed by all three APIs (Azure OpenAI API, Universal LLM API, and new Unified AI Gateway API). No `unified-` prefixed duplicates – the existing fragments are either modified in-place, replaced, or new shared fragments are added.

#### 3.1.1 Metadata Configuration Fragment (NEW)

**File**: `bicep/infra/modules/apim/policies/frag-metadata-config.xml`
**Fragment ID**: `metadata-config`

Centralized JSON configuration fragment auto-generated by Backend Onboarding from `llmBackendConfig`. Defines all model→backend mappings, API type definitions, cache settings, and timeout settings. Replaces the C# code injection approach used by `frag-set-backend-pools.xml` and `frag-get-available-models.xml`.

**Structure** (example – actual values generated from `llmBackendConfig`):
```xml
<fragment>
    <set-variable name="metadata-config" value="@{return @"{
        'models': {
            'gpt-4o': {
                'backend': 'gpt-4o-backend-pool',
                'tier': 'premium',
                'api-version': '2024-02-15-preview',
                'timeout': 120
            },
            'gpt-4o-mini': {
                'backend': 'gpt-4o-mini-backend-pool',
                'tier': 'standard',
                'api-version': '2024-02-15-preview',
                'timeout': 120
            },
            'DeepSeek-R1': {
                'backend': 'deepseek-r1-backend',
                'tier': 'standard',
                'api-version': '2024-05-01-preview',
                'inference-api-version': '2024-05-01-preview',
                'timeout': 120
            },
            'Phi-4': {
                'backend': 'phi-4-backend',
                'tier': 'standard',
                'api-version': '2024-05-01-preview',
                'inference-api-version': '2024-05-01-preview',
                'timeout': 120
            }
        },
        'api-types': {
            'openai': {
                'base-path': '/openai',
                'path-segment': '/deployments',
                'api-version': '2024-02-15-preview'
            },
            'inference': {
                'base-path': '/models',
                'path-segment': '/models',
                'api-version': '2024-05-01-preview'
            },
            'responses': {
                'base-path': '/openai/responses',
                'path-segment': '/openai/responses',
                'backend': 'responses-backend',
                'api-version': '2025-03-01-preview'
            }
        },
        'cache-settings': {
            'config-version': '1.0.0',
            'ttl-seconds': 300
        },
        'timeout-settings': {
            'streaming-multiplier': 3
        }
    }";}" />
</fragment>
```

**Auto-Generation from Backend Onboarding**:
- `llm-policy-fragments.bicep` generates this fragment from `llmBackendConfig[]`
- For each model in `llmBackendConfig[].supportedModels[]`: maps to its pool name (if multi-backend) or backend ID (if single)
- New per-model attributes from extended `llmBackendConfig`: `tier`, `apiVersion`, `inferenceApiVersion`, `timeout`
- The `api-types` section is static (defined in the Bicep template, not generated from backend config)
- Model names MUST match `llmBackendConfig[].supportedModels[].name` (case-sensitive)
- Backend values MUST match pool names or backend IDs created by backend onboarding

**Replaces**: The C# code injection into `frag-set-backend-pools.xml` (`//{backendPoolsCode}`) and `frag-get-available-models.xml` (`//{modelDeploymentsCode}`)

#### 3.1.2 Central Cache Manager Fragment (NEW)

**File**: `bicep/infra/modules/apim/policies/frag-central-cache-manager.xml`
**Fragment ID**: `central-cache-manager`

Caches the parsed metadata-config JSON in APIM internal cache to avoid re-parsing on every request.

**Behavior**:
1. Check for `UAIG-Config-Cache-Bypass` header → bypass cache if `true`
2. Build cache key: `metadata-config-v{config-version}`
3. Try `cache-lookup-value` for an existing cached config
4. On cache miss: Parse metadata-config JSON string into JObject sections
5. Extract and set context variables: `config-models`, `config-api-types`, `config-timeout-settings`, `cache-settings`
6. Store parsed config in APIM cache with configurable TTL
7. Trace cache operation (bypass/loaded/store)

**Key Design Decisions**:
- Uses APIM built-in `cache-lookup-value` / `cache-store-value` policies
- Cache key includes config version for invalidation on metadata updates
- TTL configurable via `cache-settings.ttl-seconds` (default: 300s)

#### 3.1.3 Request Processor Fragment (NEW – replaces `frag-set-llm-requested-model.xml`)

**File**: `bicep/infra/modules/apim/policies/frag-request-processor.xml`
**Fragment ID**: `request-processor`

Analyzes incoming requests to detect API type, extract model, and parse the request body. Replaces `frag-set-llm-requested-model.xml` with a unified extraction flow that handles all three model extraction patterns.

**Processing Steps**:
1. **API type detection**: Each API policy sets `api-endpoint-type` variable before calling this fragment (`openai`, `inference`, or `unified-ai`). For `unified-ai`, detect from path by matching against `config-api-types` base-paths (longest match wins). For `openai` and `inference`, the type is known from the API definition.
2. **Path normalization**: Strip API-specific path prefix from request URL
3. **Path validation**: Return 403 if no API type matches (only applicable for wildcard API)
4. **Body parsing**: Parse POST/PUT/PATCH bodies as JSON (skip for GET/DELETE)
5. **Streaming detection**: Check for `stream: true` in parsed body
6. **Model extraction** (unified across all approaches):
   - First: Try `context.Request.MatchedParameters["deployment-id"]` (Azure OpenAI API has this from its route template)
   - Second: Try body `model` field (Universal LLM / Inference format)
   - Third: Path segment extraction (wildcard API path analysis)
   - GET requests → `"non-llm-request"` (preserves existing behavior)
7. **API version selection**: Model-specific → API-type default → hardcoded fallback

**Output Variables**:
- `api-type`: Detected API type string (`openai`, `inference`, `responses`)
- `requestedModel`: Extracted model identifier (preserves existing variable name for downstream compatibility with `validate-model-access` and `set-llm-usage`)
- `model-id`: Alias for `requestedModel` (used by new fragments)
- `routing-processed-path`: Path with prefix removed
- `parsed-request-body`: Parsed JObject (or null for GET/DELETE)
- `is-streaming`: `"true"` / `"false"` string
- `selected-api-version`: API version string

**Key Compatibility Decision**: The `requestedModel` variable name is preserved (not renamed to `model-id`) because `frag-validate-model-access.xml` and `frag-set-llm-usage.xml` depend on it. Both names are set to the same value so new and existing code paths work.

#### 3.1.4 AAD Auth Fragment (MODIFIED – `frag-aad-auth.xml`)

**File**: `bicep/infra/modules/apim/policies/frag-aad-auth.xml` (modified in place)
**Fragment ID**: `aad-auth` (unchanged)

Modified to support per-product JWT activation instead of the global `{{entra-auth}}` toggle.

**Current Behavior** (being replaced):
- Reads `{{entra-auth}}` named value (global boolean)
- If `"true"`: validates JWT for all requests
- Mutually exclusive with API Key auth

**New Behavior**:
- Reads `jwt-auth-required` context variable (set by product policy, defaults to `"false"`)
- If `"true"`: validates JWT as an additional layer on top of API Key
- API Key (APIM subscription) is always validated by APIM automatically (`subscriptionRequired: true`)
- JWT validation uses same named values: `{{tenant-id}}`, `{{audience}}`, `{{client-id}}`
- Sets `auth-type` variable: `"api-key+jwt"` if JWT active and valid, `"api-key"` otherwise
- Sets `user-id` variable: JWT `azp`/`appid` claim if JWT present, else `context.Subscription.Name`

**Backend Authentication** (always applied regardless of client auth):
- Uses `authentication-managed-identity` policy
- Resource: `https://cognitiveservices.azure.com`
- Client ID: `{{uami-client-id}}` (user-assigned managed identity)
- Exception: External backends (e.g., Gemini) use API key override in `backend-selector`

**Named Values** (unchanged, shared):
- `tenant-id`, `audience`, `client-id` – JWT validation config
- `uami-client-id` – Backend managed identity

**Retirement**: The global `{{entra-auth}}` named value is removed. `frag-aad-auth-custom.xml` is retired (its dynamic validation pattern is absorbed into the modified `aad-auth`).

#### 3.1.5 Validate Model Access Fragment (UNCHANGED)

**File**: `bicep/infra/modules/apim/policies/frag-validate-model-access.xml`
**Fragment ID**: `validate-model-access`

No changes needed. This fragment already:
- Reads `requestedModel` variable (preserved by request-processor)
- Reads `allowedModels` variable (set by product policy / Access Contract)
- Returns 401 if model not in allowed list
- Skips check for `"non-llm-request"` (GET /deployments etc.)
- Case-insensitive comparison, comma-separated allowedModels

#### 3.1.6 Backend Selector Fragment (NEW – replaces `frag-set-backend-pools.xml` + `frag-set-target-backend-pool.xml` + auth portion of `frag-set-backend-authorization.xml`)

**File**: `bicep/infra/modules/apim/policies/frag-backend-selector.xml`
**Fragment ID**: `backend-selector`

Selects the correct backend based on model and API type configuration from `config-models`, then calls `set-backend-service`.

**Selection Algorithm**:
1. Check if the detected `api-type` has an explicit `backend` property in `config-api-types` → use it (e.g., Responses API → `responses-backend`)
2. Otherwise, look up `requestedModel` in `config-models` → use model's `backend` value (e.g., `gpt-4o` → `gpt-4o-backend-pool`)
3. If neither found → return 500 error with trace

**Replaces**:
- `frag-set-backend-pools.xml` (backend pool definitions – now in metadata-config)
- `frag-set-target-backend-pool.xml` (model-to-pool routing – now direct model→backend lookup)
- Backend selection portion of `frag-set-backend-authorization.xml`

**Backend Pool Compatibility**:
- Backend pools created by Backend Onboarding are referenced by name in `metadata-config`
- For single-backend models, the backend ID is used directly
- For multi-backend models, the pool name (e.g., `gpt-4o-backend-pool`) is used

**Special Handling**:
- External backends (e.g., Gemini): Override Authorization header with API key from Named Value
- Uses `set-backend-service` policy with `backend-id` attribute

#### 3.1.6 Path Builder Fragment

**File**: `bicep/infra/modules/apim/policies/frag-path-builder.xml`
**Fragment ID**: `path-builder`

Constructs backend URI paths based on API type and model. Takes over URL rewriting responsibility from `frag-set-backend-authorization.xml` (which did auth + URL rewrite + backend selection – now split across `aad-auth`, `backend-selector`, and `path-builder`).

**Path Patterns by API Type**:
- **openai**: `/openai/deployments/{requestedModel}/{remaining-path}?api-version={selected-api-version}` (replaces the `openai/{path}` rewrite currently in `azure-open-ai-api-policy.xml` and the `/openai/deployments/{model}/{path}?api-version=...` rewrite in `frag-set-backend-authorization.xml`)
- **inference**: `/models/{remaining-path}?api-version={selected-api-version}` (replaces the `/models/{path}?api-version=...` rewrite in `frag-set-backend-authorization.xml`)
- **responses**: `/openai/responses[/{response-id}]?api-version={selected-api-version}`

**Additional Transformations**:
- Injects `model` field into request body when missing (Azure OpenAI deployments API pattern)
- Injects `api-version` query parameter for Azure API types
- Uses `rewrite-uri` policy with `copy-unmatched-params="true"`

**Key Design Decision**: Azure OpenAI API currently applies `rewrite-uri` TWICE – once in `frag-set-backend-authorization.xml` and again via `openAIRewriteTemplate` at the end of inbound in `azure-open-ai-api-policy.xml`. The new `path-builder` handles this in one place, eliminating the double-rewrite pattern.

#### 3.1.7 Token Limiter Fragment (OPTIONAL – Phase 2 enhancement)

**File**: `bicep/infra/modules/apim/policies/frag-token-limiter.xml`
**Fragment ID**: `token-limiter`

Tier-based rate limiting using APIM's `llm-token-limit` policy. This is an optional fragment that can be included in the pipeline for products that need per-tier rate limiting beyond what Access Contract capacity management already provides.

**Tier Defaults** (overridable via product policy variables):
- **Premium**: 10,000 TPM, 100,000 tokens/hour quota
- **Standard**: 5,000 TPM, 50,000 tokens/hour quota

**Counter Key Generation**:
- API Key auth: `uaig-sub-{subscription-id}-{tier}`
- API Key + JWT auth: `uaig-jwt-{user-id}-{tier}`

**Integration with Access Contracts**:
- Existing `llm-token-limit` usage in default product policy continues to work for existing Access Contract capacity management
- Token limiter provides a unified tier-based approach for products that want auto-tier limits from metadata-config

#### 3.1.8 Set LLM Usage Fragment (EXTENDED – `frag-set-llm-usage.xml`)

**File**: `bicep/infra/modules/apim/policies/frag-set-llm-usage.xml` (modified in place)
**Fragment ID**: `set-llm-usage` (unchanged)

Extended to include `api-type` as an additional metric dimension and to route metrics to per-api-type namespaces.

**Current Dimensions** (preserved):
- `productName`: From `context.Product.Name`
- `deploymentName`: From `requestedModel` variable
- `Backend ID`: From backend context
- `appId`: From `context.Subscription.Id` or custom header
- `customDimension1`: From `x-sub-agent-id` header
- `customDimension2`: From `x-enduser-id` header

**New Dimension**:
- `apiType`: From `api-type` variable (set by request-processor)

**Namespace Routing** (NEW):
Instead of a single `llm-usage` namespace, routes to per-api-type namespaces:
- `openai` api-type → `UAIG-OpenAI` namespace
- `inference` api-type → `UAIG-Inference` namespace
- `responses` api-type → `UAIG-Responses` namespace
- Default → `llm-usage` namespace (backward compatible for existing API traffic)

**Backward Compatibility**: When `api-type` variable is not set (e.g., during transition), falls back to existing `llm-usage` namespace and omits the `apiType` dimension. Existing Event Hub logging (`frag-openai-usage.xml`, `frag-openai-usage-streaming.xml`) continues to work alongside this fragment.

#### 3.1.9 Diagnostic Headers Fragment (NEW)

**File**: `bicep/infra/modules/apim/policies/frag-diagnostic-headers.xml`
**Fragment ID**: `diagnostic-headers`

Injects `UAIG-*` response headers for debugging. Placed in outbound and on-error sections of all 3 API policies.

**Header Categories**:
- **Cache**: `UAIG-Config-Version`, `UAIG-Cache-Operation`, `UAIG-Config-Loaded`
- **Security**: `UAIG-Auth-Type`, `UAIG-User-ID`, `UAIG-JWT-Active`
- **Request**: `UAIG-Model-ID`, `UAIG-API-Type`, `UAIG-Streaming`, `UAIG-Original-Path`, `UAIG-Processed-Path`
- **Route**: `UAIG-Selected-Backend`, `UAIG-Forwarded-Path`, `UAIG-Request-Timeout`, `UAIG-API-Version`
- **Usage**: `UAIG-Product-Name`, `UAIG-Subscription-ID`

**Conditional Output**: Headers are only emitted when the corresponding variables exist in context (graceful degradation if a fragment is skipped or errors).

#### 3.1.10 Fragment Retirement

The following fragments are **retired** (no longer referenced by any API policy):

| Retired Fragment | Replaced By | Reason |
|---|---|---|
| `frag-set-backend-pools.xml` | `metadata-config` + `backend-selector` | Backend pool definitions move to metadata JSON; pool routing becomes direct model→backend lookup |
| `frag-set-target-backend-pool.xml` | `backend-selector` | Model-to-pool routing merged into backend-selector |
| `frag-set-backend-authorization.xml` | `aad-auth` + `backend-selector` + `path-builder` | Auth, backend selection, and URL rewriting split into dedicated fragments |
| `frag-set-llm-requested-model.xml` | `request-processor` | Model extraction unified into request-processor |
| `frag-get-available-models.xml` | `metadata-config` (config-models) | Discovery endpoints read model list from config-models JObject |
| `frag-aad-auth-custom.xml` | `aad-auth` (modified) | Dynamic JWT validation absorbed into modified aad-auth |

**Note**: The retired XML template files remain in the repository but are no longer loaded or registered as APIM policy fragments. Backend Onboarding no longer generates C# code for injection into these templates.

---

### Phase 2: Backend Onboarding & Infrastructure Changes

**Goal**: Extend `llmBackendConfig` schema, generate `metadata-config` instead of C# code, create unified AI wildcard API resource.

#### 3.2.1 Extended `llmBackendConfig` Schema

**File**: `bicep/infra/modules/apim/llm-backend-onboarding/main.bicep`

Extend the `supportedModels` object in `llmBackendConfig` with new per-model attributes:

```bicep
param llmBackendConfig array = [
  {
    backendId: 'aoai-eastus-1'
    backendType: 'azure-openai'            // 'azure-openai' | 'ai-foundry' | 'external'
    endpoint: 'https://aoai-eastus-1.openai.azure.com'
    authScheme: 'managedIdentity'          // 'managedIdentity' | 'apiKey' | 'token'
    supportedModels: [
      {
        name: 'gpt-4o'
        sku: 'Standard'
        capacity: 100
        modelFormat: 'OpenAI'
        modelVersion: '2024-08-06'
        // NEW ATTRIBUTES:
        tier: 'premium'                    // 'premium' | 'standard' – for rate limiting tiers
        apiVersion: '2024-02-15-preview'   // Azure OpenAI API version
        timeout: 120                       // Base timeout in seconds
      }
    ]
    priority: 1
    weight: 100
  }
]
```

**New Attributes per Model**:
| Attribute | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `tier` | string | No | `'standard'` | Rate limiting tier (`premium` or `standard`) |
| `apiVersion` | string | No | `'2024-02-15-preview'` | API version for Azure OpenAI requests |
| `inferenceApiVersion` | string | No | `'2024-05-01-preview'` | API version for AI Foundry / Inference requests |
| `timeout` | int | No | `120` | Base request timeout in seconds |

#### 3.2.2 Metadata Config Generation (replaces C# code injection)

**File**: `bicep/infra/modules/apim/llm-backend-onboarding/modules/llm-policy-fragments.bicep`

Replace the existing C# code generation (`backendPoolsCode`, `modelDeploymentsCode`) with metadata-config JSON generation.

**Current Generation** (being replaced):
- Generates `backendPoolsCode`: C# code that creates a JArray of pool objects (for `frag-set-backend-pools.xml`)
- Generates `modelDeploymentsCode`: C# code that creates a JArray of model deployment objects (for `frag-get-available-models.xml`)
- Injects code into XML templates via `replace()` on `//{backendPoolsCode}` and `//{modelDeploymentsCode}` placeholders

**New Generation**:
- Generates `metadataConfigJson`: A JSON string with `models`, `api-types`, `cache-settings`, `timeout-settings`
- For each unique model across all `llmBackendConfig[].supportedModels[]`:
  - Look up if model appears in a backend pool → use pool name as `backend`
  - If single-backend → use `backendId` directly
  - Include `tier` (default: `'standard'`), `api-version`, `inference-api-version`, `timeout` from model config
- `api-types` section is static (defined in Bicep template)
- `cache-settings.config-version` incremented on each deployment (use `utcNow()` or a hash)
- Generates the `metadata-config` fragment XML and registers it as a `Microsoft.ApiManagement/service/policyFragments` resource

**Fragment Registration Changes**:
- **Remove**: Fragment registrations for `set-backend-pools`, `set-target-backend-pool`, `set-backend-authorization`, `set-llm-requested-model`, `get-available-models`
- **Add**: Fragment registration for `metadata-config` (generated), `central-cache-manager`, `request-processor`, `backend-selector`, `path-builder`, `diagnostic-headers` (loaded from XML files)
- **Modify**: Fragment registration for `aad-auth` (modified XML), `set-llm-usage` (extended XML)

#### 3.2.3 Unified AI Gateway API Bicep Module (NEW)

**File**: `bicep/infra/modules/apim/unified-ai-api.bicep`

Creates the wildcard API resource in APIM.

```bicep
resource api 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = {
  name: 'unified-ai-gateway-api'
  parent: apimService
  properties: {
    apiType: 'http'
    description: 'Unified AI Gateway - routes to all AI backends via wildcard path'
    displayName: 'Unified AI Gateway API'
    format: 'openapi+json'
    path: 'unified-ai'
    protocols: ['https']
    subscriptionKeyParameterNames: {
      header: 'api-key'
      query: 'api-key'
    }
    subscriptionRequired: true
    type: 'http'
    value: string(loadJsonContent('./unified-ai-api/unified-ai-gateway-wildcard.json'))
  }
}
```

**OpenAPI Schema**:
- Create `bicep/infra/modules/apim/unified-ai-api/unified-ai-gateway-wildcard.json`
- Single path `/*` with GET, POST, PUT, PATCH, DELETE operations
- Authentication: `api-key` header/query parameter

#### 3.2.4 All Three API Policies Updated

All 3 API policies are updated to use the shared fragment pipeline:

**Azure OpenAI API** (`azure-open-ai-api-policy.xml`):
```xml
<policies>
    <inbound>
        <base />
        <set-variable name="api-endpoint-type" value="openai" />
        <include-fragment fragment-id="metadata-config" />
        <include-fragment fragment-id="central-cache-manager" />
        <include-fragment fragment-id="request-processor" />
        <include-fragment fragment-id="aad-auth" />
        <include-fragment fragment-id="validate-model-access" />
        <include-fragment fragment-id="backend-selector" />
        <include-fragment fragment-id="path-builder" />
        <include-fragment fragment-id="set-llm-usage" />
        <!-- Calculate request timeout from metadata-config -->
        <set-variable name="request-timeout" value="@{ ... }" />
    </inbound>
    <backend>
        <forward-request timeout="@(context.Variables.GetValueOrDefault<int>(\"request-timeout\", 120))" />
    </backend>
    <outbound>
        <base />
        <include-fragment fragment-id="diagnostic-headers" />
    </outbound>
    <on-error>
        <base />
        <include-fragment fragment-id="diagnostic-headers" />
    </on-error>
</policies>
```

**Universal LLM API** (`universal-llm-api-policy-v2.xml`):
```xml
<!-- Same structure, but with: -->
<set-variable name="api-endpoint-type" value="inference" />
<!-- Then same shared fragment pipeline -->
```

**Unified AI Gateway API** (`unified-ai-gateway-api-policy.xml`) – NEW:
```xml
<policies>
    <inbound>
        <base />
        <!-- Validate product context -->
        <choose>
            <when condition="@(context.Product == null)">
                <return-response>
                    <set-status code="401" reason="Unauthorized" />
                    <set-body>Access denied. Requests must be made through a product.</set-body>
                </return-response>
            </when>
        </choose>
        <set-variable name="api-endpoint-type" value="unified-ai" />
        <include-fragment fragment-id="metadata-config" />
        <include-fragment fragment-id="central-cache-manager" />
        <include-fragment fragment-id="request-processor" />
        <include-fragment fragment-id="aad-auth" />
        <include-fragment fragment-id="validate-model-access" />
        <include-fragment fragment-id="backend-selector" />
        <include-fragment fragment-id="path-builder" />
        <include-fragment fragment-id="set-llm-usage" />
        <!-- Calculate request timeout -->
        <set-variable name="request-timeout" value="@{
            var modelId = context.Variables.GetValueOrDefault<string>(\"requestedModel\", \"unknown\");
            var models = context.Variables.GetValueOrDefault<JObject>(\"config-models\");
            var timeoutSettings = context.Variables.GetValueOrDefault<JObject>(\"config-timeout-settings\");
            var isStreaming = context.Variables.GetValueOrDefault<string>(\"is-streaming\", \"false\");
            int baseTimeout = 120;
            try {
                var modelConfig = models?[modelId];
                if (modelConfig != null) {
                    baseTimeout = modelConfig[\"timeout\"]?.Value<int>() ?? 120;
                }
                if (isStreaming.Equals(\"true\", StringComparison.OrdinalIgnoreCase)) {
                    var multiplier = timeoutSettings?[\"streaming-multiplier\"]?.Value<int>() ?? 3;
                    baseTimeout = baseTimeout * multiplier;
                }
            } catch { }
            return baseTimeout;
        }" />
    </inbound>
    <backend>
        <forward-request timeout="@(context.Variables.GetValueOrDefault<int>(\"request-timeout\", 120))" />
    </backend>
    <outbound>
        <base />
        <include-fragment fragment-id="diagnostic-headers" />
    </outbound>
    <on-error>
        <base />
        <include-fragment fragment-id="diagnostic-headers" />
    </on-error>
</policies>
```

**Key Point**: All 3 API policies have identical fragment pipelines. The only differences are:
1. `api-endpoint-type` variable set before the pipeline (`openai`, `inference`, `unified-ai`)
2. The unified-ai API includes product context validation (the other two already have it from their existing product setup)

#### 3.2.5 Discovery Endpoints Updated

**Files**:
- `universal-llm-api-deployments-policy.xml` (modified)
- `universal-llm-api-deployment-by-name-policy.xml` (modified)

Currently these use `frag-get-available-models.xml` (C# code injection with `//{modelDeploymentsCode}`). Updated to read from `config-models` instead:

```xml
<!-- Before: -->
<include-fragment fragment-id="get-available-models" />

<!-- After: -->
<include-fragment fragment-id="metadata-config" />
<include-fragment fragment-id="central-cache-manager" />
<!-- Build model list from config-models JObject -->
<set-variable name="available-models" value="@{
    var models = context.Variables.GetValueOrDefault<JObject>(\"config-models\");
    var allowedModels = context.Variables.GetValueOrDefault<string>(\"allowedModels\", \"\");
    var result = new JArray();
    if (models != null) {
        foreach (var prop in models.Properties()) {
            // Filter by allowedModels if set
            if (!string.IsNullOrEmpty(allowedModels)) {
                var allowed = allowedModels.Split(',').Select(m => m.Trim());
                if (!allowed.Contains(prop.Name, StringComparer.OrdinalIgnoreCase)) continue;
            }
            result.Add(new JObject(
                new JProperty(\"id\", prop.Name),
                new JProperty(\"name\", prop.Name),
                new JProperty(\"tier\", prop.Value[\"tier\"]?.ToString() ?? \"standard\")
            ));
        }
    }
    return result.ToString();
}" />
```

The `allowedModels` filtering preserves Access Contract behavior. The same discovery endpoints work for all 3 APIs.

#### 3.2.6 Main Deployment Integration

**File**: `bicep/infra/modules/apim/apim.bicep`

Add the unified API module call alongside existing API modules:

```bicep
module apiUnifiedAI './unified-ai-api.bicep' = {
  name: 'unified-ai-gateway-api'
  params: {
    apiManagementName: apimService.name
    policyXml: loadTextContent('./policies/unified-ai-gateway-api-policy.xml')
  }
  dependsOn: [
    llmBackends
    llmBackendPools
    policyFragments
  ]
}
```

**Named Values** (shared, already exist):
- `tenant-id`, `audience`, `client-id` – JWT config
- `uami-client-id` – Backend managed identity
- External API keys – Per-backend Named Values

---

### Phase 3: Access Contract & Auth Updates

**Goal**: Integrate the unified AI API into Access Contracts and update auth model.

#### 3.3.1 Access Contract `apiNameMapping` Updates

**File**: `bicep/infra/modules/apim/citadel-access-contracts/main.bicep` (or equivalent)

Update the default `apiNameMapping` to include the unified AI gateway and ensure all 3 LLM APIs are mapped together:

```bicep
apiNameMapping = {
  LLM: ['azure-openai-api', 'universal-llm-api', 'unified-ai-gateway-api']  // All 3 LLM APIs
  UAI: ['unified-ai-gateway-api']                                            // Unified AI only
  DOC: ['document-intelligence-api']
  SRCH: ['azure-ai-search-index-api']
}
```

**Key Change**: The `LLM` code now includes all 3 LLM APIs. Existing Access Contracts using `code: 'LLM'` automatically gain access to the unified AI gateway. The `UAI` code is available for contracts that only want the wildcard endpoint.

#### 3.3.2 Product Policy Template for JWT Activation

**File**: `bicep/infra/modules/apim/citadel-access-contracts/snippets/jwt-auth.xml` (NEW snippet)

Access Contract product policies can now optionally activate JWT validation:

```xml
<!-- Snippet injected into product policy when JWT auth is requested -->
<set-variable name="jwt-auth-required" value="true" />
```

This is controlled by a new `policies.jwtAuth` field in the Access Contract request JSON:

```json
{
  "policies": {
    "jwtAuth": {
      "enabled": true
    }
  }
}
```

When not specified, `jwt-auth-required` defaults to `"false"` and only API Key auth is active.

#### 3.3.3 Product `subscriptionRequired` Enforcement

All products must have `subscriptionRequired: true`. The `apimProduct.bicep` module is updated to enforce this:

```bicep
resource product 'Microsoft.ApiManagement/service/products@2024-06-01-preview' = {
  properties: {
    subscriptionRequired: true  // Always true – API Key is always required
    // ... other properties
  }
}
```

This is a breaking change for any existing products that had `subscriptionRequired: false` (JWT-only products). Those products must now require a subscription key alongside their JWT token.

---

### Phase 4: Testing & Validation

#### 3.4.1 Test Cases

Create a test file `test/unified-ai-gateway-tests.http` with REST Client test cases covering all 3 API endpoints:

**API Key Authentication (all endpoints)**:
```http
### Azure OpenAI format via original endpoint
POST {{apim-url}}/openai/deployments/gpt-4o/chat/completions
api-key: {{subscription-key}}
Content-Type: application/json

{"messages": [{"role": "user", "content": "Hello"}]}

### Inference format via original endpoint
POST {{apim-url}}/models/chat/completions
api-key: {{subscription-key}}
Content-Type: application/json

{"model": "Phi-4", "messages": [{"role": "user", "content": "Hello"}]}

### Azure OpenAI format via unified endpoint
POST {{apim-url}}/unified-ai/openai/deployments/gpt-4o/chat/completions
api-key: {{subscription-key}}
Content-Type: application/json

{"messages": [{"role": "user", "content": "Hello"}]}

### Inference format via unified endpoint
POST {{apim-url}}/unified-ai/models/chat/completions
api-key: {{subscription-key}}
Content-Type: application/json

{"model": "Phi-4", "messages": [{"role": "user", "content": "Hello"}]}
```

**API Key + JWT Authentication**:
```http
### API Key + JWT together (product with jwt-auth-required=true)
POST {{apim-url}}/unified-ai/openai/deployments/gpt-4o/chat/completions
api-key: {{subscription-key}}
Authorization: Bearer {{jwt-token}}
Content-Type: application/json

{"messages": [{"role": "user", "content": "Hello"}]}

### API Key only on JWT-required product (expect 401 JWT missing)
POST {{apim-url}}/unified-ai/openai/deployments/gpt-4o/chat/completions
api-key: {{jwt-product-subscription-key}}
Content-Type: application/json

{"messages": [{"role": "user", "content": "Hello"}]}

### No authentication at all (expect 401)
POST {{apim-url}}/unified-ai/openai/deployments/gpt-4o/chat/completions
Content-Type: application/json

{"messages": [{"role": "user", "content": "Hello"}]}
```

**Discovery Endpoints**:
```http
### List all available models
GET {{apim-url}}/models/deployments
api-key: {{subscription-key}}

### Get specific model
GET {{apim-url}}/models/deployments/gpt-4o
api-key: {{subscription-key}}

### Discovery with restricted product (should only show allowed models)
GET {{apim-url}}/models/deployments
api-key: {{restricted-subscription-key}}
```

**Error Cases**:
```http
### Invalid path on wildcard (expect 403)
POST {{apim-url}}/unified-ai/invalid/path
api-key: {{subscription-key}}

### Unauthorized model (expect 401 from validate-model-access)
POST {{apim-url}}/unified-ai/openai/deployments/gpt-4o/chat/completions
api-key: {{restricted-subscription-key}}
Content-Type: application/json

{"messages": [{"role": "user", "content": "Hello"}]}
```

#### 3.4.2 Validation Checklist

- [ ] All 3 APIs (`/openai/*`, `/models/*`, `/unified-ai/*`) use the shared fragment pipeline
- [ ] API Key authentication works on all endpoints
- [ ] JWT + API Key authentication works on products with `jwt-auth-required=true`
- [ ] API Key alone works on products without JWT requirement
- [ ] Request without API Key returns 401 on all endpoints
- [ ] Model extraction works via `MatchedParameters["deployment-id"]` (Azure OpenAI)
- [ ] Model extraction works via body `model` field (Inference / Universal LLM)
- [ ] Model extraction works via path analysis (wildcard unified-ai)
- [ ] Backend selection routes to correct pool/backend via metadata-config
- [ ] Path rewriting produces correct backend URLs for all api-types
- [ ] `validate-model-access` correctly filters by `allowedModels`
- [ ] Discovery endpoints (`/deployments`, `/deployments/{name}`) work with metadata-config
- [ ] Discovery honors `allowedModels` filtering from Access Contracts
- [ ] Usage metrics emit to Application Insights with `apiType` dimension
- [ ] Event Hub logging continues to work
- [ ] Diagnostic headers appear in responses
- [ ] Config cache works and can be bypassed via header
- [ ] Backend Onboarding generates correct `metadata-config` from extended `llmBackendConfig`

---

## 4. File Inventory

### New Files

| File | Type | Description |
|------|------|-------------|
| `modules/apim/policies/frag-metadata-config.xml` | Policy Fragment (generated) | Centralized JSON configuration – auto-generated by Backend Onboarding |
| `modules/apim/policies/frag-central-cache-manager.xml` | Policy Fragment | Cross-request config caching |
| `modules/apim/policies/frag-request-processor.xml` | Policy Fragment | Unified request analysis and model extraction |
| `modules/apim/policies/frag-backend-selector.xml` | Policy Fragment | Backend selection from metadata-config |
| `modules/apim/policies/frag-path-builder.xml` | Policy Fragment | Backend URI construction per api-type |
| `modules/apim/policies/frag-token-limiter.xml` | Policy Fragment (optional) | Tier-based rate limiting |
| `modules/apim/policies/frag-diagnostic-headers.xml` | Policy Fragment | Debug UAIG-* response headers |
| `modules/apim/policies/unified-ai-gateway-api-policy.xml` | API Policy | Unified AI wildcard API orchestration |
| `modules/apim/unified-ai-api.bicep` | Bicep Module | Unified AI Gateway API resource |
| `modules/apim/unified-ai-api/unified-ai-gateway-wildcard.json` | OpenAPI Schema | Wildcard API definition |
| `citadel-access-contracts/snippets/jwt-auth.xml` | Snippet | JWT activation for product policies |
| `test/unified-ai-gateway-tests.http` | Test File | REST Client test cases |

### Modified Files

| File | Change Description |
|------|-------------------|
| `modules/apim/policies/frag-aad-auth.xml` | Per-product JWT activation replaces global `{{entra-auth}}` toggle |
| `modules/apim/policies/frag-set-llm-usage.xml` | Extended with `apiType` dimension and per-api-type namespaces |
| `modules/apim/policies/azure-open-ai-api-policy.xml` | Switched to shared fragment pipeline with `api-endpoint-type=openai` |
| `modules/apim/policies/universal-llm-api-policy-v2.xml` | Switched to shared fragment pipeline with `api-endpoint-type=inference` |
| `modules/apim/policies/universal-llm-api-deployments-policy.xml` | Uses metadata-config instead of `frag-get-available-models.xml` |
| `modules/apim/policies/universal-llm-api-deployment-by-name-policy.xml` | Uses metadata-config instead of `frag-get-available-models.xml` |
| `modules/apim/apim.bicep` | Add unified AI API module call |
| `llm-backend-onboarding/main.bicep` | Extended `llmBackendConfig` schema with `tier`, `apiVersion`, `timeout` |
| `llm-backend-onboarding/modules/llm-policy-fragments.bicep` | Generate `metadata-config` JSON instead of C# code injection |
| `citadel-access-contracts/main.bicep` | Add `UAI` to `apiNameMapping`, update `LLM` mapping |
| `citadel-access-contracts/modules/apimProduct.bicep` | Enforce `subscriptionRequired: true` |

### Retired Files (no longer referenced)

| File | Replaced By |
|------|-------------|
| `modules/apim/policies/frag-set-backend-pools.xml` | `frag-metadata-config.xml` + `frag-backend-selector.xml` |
| `modules/apim/policies/frag-set-target-backend-pool.xml` | `frag-backend-selector.xml` |
| `modules/apim/policies/frag-set-backend-authorization.xml` | `frag-aad-auth.xml` + `frag-backend-selector.xml` + `frag-path-builder.xml` |
| `modules/apim/policies/frag-set-llm-requested-model.xml` | `frag-request-processor.xml` |
| `modules/apim/policies/frag-get-available-models.xml` | `frag-metadata-config.xml` (config-models) |
| `modules/apim/policies/frag-aad-auth-custom.xml` | `frag-aad-auth.xml` (modified) |

---

## 5. Dependencies & Prerequisites

| Dependency | Status | Notes |
|-----------|--------|-------|
| APIM instance deployed | Required | Existing infrastructure |
| Backend pools created | Required | Via Backend Onboarding |
| Named Values for JWT | Required (for JWT auth) | `tenant-id`, `audience`, `client-id` |
| Named Values for UAMI | Required | `uami-client-id` |
| App Registration in Entra ID | Required (for JWT auth) | Existing or new |
| Key Vault | Required | For external API keys |
| Application Insights | Recommended | For usage metrics |
| Event Hub | Optional | For downstream analytics pipeline |

---

## 6. Implementation Order

```
Step 1: Extend llmBackendConfig schema (Phase 2.1)
        └── Add tier, apiVersion, timeout to supportedModels

Step 2: Create new shared fragment XML files (Phase 1)
        ├── frag-metadata-config.xml (template for generation)
        ├── frag-central-cache-manager.xml
        ├── frag-request-processor.xml
        ├── frag-backend-selector.xml
        ├── frag-path-builder.xml
        ├── frag-token-limiter.xml (optional)
        └── frag-diagnostic-headers.xml

Step 3: Modify existing fragments (Phase 1)
        ├── frag-aad-auth.xml (per-product JWT)
        └── frag-set-llm-usage.xml (apiType dimension)

Step 4: Update Backend Onboarding (Phase 2.2)
        └── llm-policy-fragments.bicep → generate metadata-config JSON

Step 5: Update all 3 API policies (Phase 2.4)
        ├── azure-open-ai-api-policy.xml → shared pipeline
        ├── universal-llm-api-policy-v2.xml → shared pipeline
        └── unified-ai-gateway-api-policy.xml (NEW)

Step 6: Update discovery endpoints (Phase 2.5)
        ├── universal-llm-api-deployments-policy.xml → metadata-config
        └── universal-llm-api-deployment-by-name-policy.xml → metadata-config

Step 7: Create unified AI API Bicep module (Phase 2.3)
        └── unified-ai-api.bicep

Step 8: Integrate into main deployment (Phase 2.6)
        └── Update apim.bicep

Step 9: Update Access Contracts (Phase 3)
        ├── apiNameMapping
        ├── jwt-auth snippet
        └── subscriptionRequired enforcement

Step 10: Create tests (Phase 4)
         └── unified-ai-gateway-tests.http

Step 11: Update documentation
         ├── LLM-Backend-Onboarding-Guide.md
         ├── Access Contracts README
         └── Main README
```

---

## 7. Naming Conventions

| Resource | Convention | Example |
|----------|-----------|---------|
| New API | `unified-ai-gateway-api` | APIM API resource |
| New API Path | `unified-ai` | Base URL path |
| Shared Fragments | `{function}` (no prefix) | `metadata-config`, `request-processor`, `backend-selector` |
| Existing Fragments | Unchanged names | `aad-auth`, `validate-model-access`, `set-llm-usage` |
| Access Contract Code | `UAI` | Service code for unified AI only |
| Context Variables | Kebab-case | `api-type`, `model-id`, `selected-backend`, `requestedModel` |
| Diagnostic Headers | `UAIG-{Category}-{Name}` | `UAIG-Model-ID`, `UAIG-Auth-Type` |
| Cache Keys | `metadata-config-v{version}` | `metadata-config-v1.0.0` |

---

## 8. Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| **Fragment size limit (32KB)** | Metadata-config may grow with many models – Bicep generation can split or compress if approaching limit |
| **Cache invalidation** | Version-based cache keys ensure config updates propagate on redeployment. Bypass header available for debugging |
| **JWT Named Values missing** | `aad-auth` fragment skips JWT validation when `jwt-auth-required` is `"false"` (default). Returns 401 only when JWT is required but token missing/invalid |
| **Backend pool name mismatch** | Metadata-config auto-generated from same backend onboarding config that creates pools – names always match |
| **Performance impact** | Config caching minimizes JSON parsing overhead. Fragments are lightweight C# expressions |
| **Breaking existing API policies** | All 3 API policies switch to new pipeline simultaneously. Fragment IDs have no prefix to avoid duplication |
| **requestedModel variable compatibility** | Both `requestedModel` and `model-id` variables are set to same value – existing downstream code (validate-model-access, set-llm-usage) works unchanged |
| **Discovery endpoint regression** | Same external behavior (same JSON response format). Only internal mechanism changes (metadata-config vs C# code injection) |

---

## 9. Key Differences from Reference Implementation (APIM-Unified-AI-Gateway-Sample)

| Aspect | Reference (Terraform) | This Implementation (Bicep) |
|--------|----------------------|---------------------------|
| **IaC** | Terraform modules | Bicep modules |
| **Scope** | Single wildcard API only | 3 APIs sharing one pipeline |
| **Backend Definition** | Static in Terraform variables | Dynamic via Backend Onboarding (`llmBackendConfig`) |
| **Metadata Config** | Hand-crafted JSON in fragment | Auto-generated from backend onboarding config |
| **Products** | 2 static products (API Key / JWT) | Dynamic via Access Contracts |
| **Auth Model** | API Key OR JWT (mutually exclusive) | API Key always + JWT optional per-product |
| **Rate Limiting** | Tier-based hardcoded limits | Tier-based defaults + product-level overrides via Access Contracts |
| **Usage Metrics** | App Insights only | App Insights + Event Hub (existing pipeline) |
| **Model Access Control** | Not implemented | Via `allowedModels` from Access Contracts |
| **Discovery Endpoints** | Not implemented | `/deployments` and `/deployments/{name}` with allowedModels filtering |
| **Fragment Naming** | No prefix (standalone) | No prefix (shared across APIs) |
| **Existing API Migration** | N/A (greenfield) | Existing Azure OpenAI + Universal LLM APIs migrate to shared pipeline |
