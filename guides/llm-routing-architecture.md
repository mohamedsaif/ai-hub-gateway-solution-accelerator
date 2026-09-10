# LLM Routing Architecture Guide

## Overview

The AI Citadel Governance Hub provides intelligent, model-based routing to LLM backends through Azure API Management (APIM). This guide explains how requests are routed to different backend/backend pools when using the **Unified AI API**, **Universal LLM API**, or **Azure OpenAI API**.

## Supported APIs

The following APIs are configured out-of-the-box for handling LLM requests:

| API | Path | Use Case |
|-----|------|----------|
| **Unified AI API** | `/unified-ai/*` | **RECOMMENDED** Single wildcard endpoint supporting all API types (OpenAI, Inference, Responses, Gemini, OpenAI-Compatible) with dynamic routing |
| **Universal LLM API** | `/models/*` | OpenAI-compatible inference endpoints that supports various models |
| **Azure OpenAI API** | `/openai/deployments/{deployment-id}/*` | Azure OpenAI SDK compatibility |

The Unified AI API includes an **OpenAI-Compatible path** (`/unified-ai/v1/*`) that allows clients to use standard OpenAI SDKs without modification. See the [OpenAI-Compatible API Guide](openai-compatible-api-guide.md) for details.

The **Universal LLM API** and **Azure OpenAI API** share the same underlying routing fragments. The **Unified AI API** extends these with additional fragments for dynamic path-based routing, centralized configuration caching, and multi-API-type support.

## Approach

The routing relies on APIM Policy Fragments to implement dynamic routing logic without modifying the main API policies.

Using policy fragments allows to keep the routing logic modular and reusable across multiple APIs.

**Shared fragments** (used by all three APIs):
- `set-backend-pools`: Loads backend pool configurations that include supported models by which backends
- `set-target-backend-pool`: Matches the requested model to a backend pool (extended with `apiTypeOverrideBackend` for Unified AI)
- `set-backend-authorization`: Configures appropriate authentication for the target backend (respects `skipBackendUrlRewrite` for Unified AI)
- `set-llm-usage`: Collects token usage metrics
- `validate-model-access`: Model access control per product

**Shared fragment** (used by Universal LLM and Azure OpenAI only):
- `set-llm-requested-model`: Extracts the requested model from the request path or body

**Unified AI-specific fragments:**
- `metadata-config`: Centralized JSON configuration for models, API types, and timeout settings
- `central-cache-manager`: Caches and parses the metadata configuration with TTL-based expiry
- `request-processor`: Analyzes request paths to detect API type and extract model (replaces `set-llm-requested-model` for the Unified AI API)
- `security-handler`: Unified authentication (API Key + optional JWT per product)
- `path-builder`: Reconstructs backend URIs based on API type
- `set-response-headers`: Injects UAIG-* debug headers in responses (when enabled)

## Architecture Overview

### Universal LLM API / Azure OpenAI API

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Client Request                                    │
│   POST /models/chat/completions  OR  POST /openai/deployments/gpt-4o/...    │
└────────────────────────────────────┬────────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        APIM Gateway (Inbound)                               │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │ 1. Authentication (Entra ID / API Key)                                │  │
│  │ 2. Extract Model (from body or deployment-id path)                    │  │
│  │ 3. Load Backend Pools Configuration                                   │  │
│  │ 4. Match Model → Backend Pool                                         │  │
│  │ 5. Validate RBAC (allowed pools check)                                │  │
│  │ 6. Set Authorization (Managed Identity)                               │  │
│  │ 7. Route to Backend Pool                                              │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────┬────────────────────────────────────────┘
                                     │
                                     ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                         Backend Pool Selection                             │
│                                                                            │
│   ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐        │
│   │  gpt-4o-pool    │    │ deepseek-v3.2-pool│    │ Direct Backend  │        │
│   │  ┌───────────┐  │    │  ┌───────────┐  │    │                 │        │
│   │  │ Backend 1 │  │    │  │ Backend 1 │  │    │  Single backend │        │
│   │  │(P:1,W:100)│  │    │  │(P:1,W:100)│  │    │  for unique     │        │
│   │  └───────────┘  │    │  └───────────┘  │    │  models         │        │
│   │  ┌───────────┐  │    │  ┌───────────┐  │    │                 │        │
│   │  │ Backend 2 │  │    │  │ Backend 2 │  │    └─────────────────┘        │
│   │  │ (P:2,W:50)│  │    │  │ (P:2,W:50)│  │                               │
│   │  └───────────┘  │    │  └───────────┘  │                               │
│   └─────────────────┘    └─────────────────┘                               │
└────────────────────────────────────┬───────────────────────────────────────┘
                                     │
                                     ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                          LLM Backend Targets                               │
│                                                                            │
│   ┌─────────────┐      ┌─────────────┐      ┌─────────────┐      ┌───────────┐  │
│   │   Foundry   │      │ Azure OpenAI│      │   Amazon    │      │ External  │  │
│   │  Endpoint   │      │  Endpoint   │      │  Bedrock    │      │ Provider  │  │
│   └─────────────┘      └─────────────┘      └─────────────┘      └───────────┘  │
└────────────────────────────────────────────────────────────────────────────┘
```

### Unified AI API

The Unified AI API uses a wildcard catch-all (`/*`) to handle all request patterns through a single endpoint, with dynamic API-type detection and path reconstruction.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Client Request                                    │
│  POST /unified-ai/openai/deployments/gpt-4o/chat/completions                │
│  POST /unified-ai/models/chat/completions (body: model)                     │
│  POST /unified-ai/v1beta/openai/chat/completions (Gemini)                   │
│  POST /unified-ai/openai/responses (Responses API)                          │
│  GET  /unified-ai/deployments (Model Discovery)                             │
└────────────────────────────────────┬────────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    APIM Gateway (Unified AI Inbound)                        │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │ 1. Load Metadata Config (models, api-types, timeouts)                 │  │
│  │ 2. Cache Manager (version-keyed cache with 300s TTL)                  │  │
│  │ 3. Request Processor (detect api-type from path, extract model)       │  │
│  │ 4. Security Handler (API Key + optional JWT per product)              │  │
│  │ 5. Validate Model Access (per product allowedModels)                  │  │
│  │ 6. Load Backend Pools Configuration                   [SHARED]        │  │
│  │ 7. Match Model → Backend Pool (with api-type override)[SHARED]        │  │
│  │ 8. Set Authorization (Managed Identity)               [SHARED]        │  │
│  │ 9. Path Builder (reconstruct backend URI per api-type)                │  │
│  │ 10. Token Usage Metrics                               [SHARED]        │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────┬────────────────────────────────────────┘
                                     │
                              ┌──────┴──────┐
                              │ API Type    │
                              │ Detection   │
                              └──────┬──────┘
            ┌─────────┬──────────┬───┴───┬──────────┬────────────┬────────────┐
            ▼         ▼          ▼       ▼          ▼            ▼            ▼
       ┌─────────┐┌────────┐┌────────┐┌────────┐┌──────────┐┌──────────┐┌──────────┐
       │ openai  ││infer-  ││respon- ││respon- ││openai-v1 ││gemini-   ││bedrock   │
       │         ││ence    ││ses     ││ses-v1  ││          ││openai    ││          │
       │/openai/ ││/models/││/openai/││/openai/││/openai/  ││/v1beta/  ││/model/   │
       │deploy...││chat/.. ││respon..││v1/resp.││v1/deploy.││openai/.. ││converse  │
       └────┬────┘└───┬────┘└───┬────┘└───┬────┘└────┬─────┘└────┬─────┘└────┬─────┘
            └─────────┴─────────┴────┬────┴──────────┴────────────┴───────────┘
                                     ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                         Backend Pool Selection                             │
│           (same pool infrastructure as other APIs)                         │
└────────────────────────────────────┬───────────────────────────────────────┘
                                     │
                                     ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                          LLM Backend Targets                               │
│                                                                            │
│   ┌─────────────┐      ┌─────────────┐      ┌─────────────┐      ┌─────────────┐  │
│   │   Foundry   │      │ Azure OpenAI│      │   Amazon    │      │ External    │  │
│   │  Endpoint   │      │  Endpoint   │      │  Bedrock    │      │ Provider    │  │
│   └─────────────┘      └─────────────┘      └─────────────┘      └─────────────┘  │
└────────────────────────────────────────────────────────────────────────────┘
```

## Routing Flow Details

### Universal LLM API / Azure OpenAI API Flow

These two APIs use shared fragments for a straightforward model → backend pool → backend routing flow.

#### Step 1: Model Extraction (set-llm-requested-model)

The `set-llm-requested-model` policy fragment extracts the model from the request:

| Source | Pattern | Example |
|--------|---------|---------|
| **GET/DELETE Request** | Any GET or DELETE operation | Returns `"non-llm-request"` (skips model extraction) |
| **URL Path Parameter** | `/deployments/{deployment-id}/...` | Azure OpenAI API (named operations) |
| **URL Path Segment** | `/openai/deployments/{model}/...` | Universal LLM API (wildcard operations) |
| **Request Body** | `{"model": "gpt-4o", ...}` | Universal LLM / Inference API |

**Supported Patterns:**
1. **GET/DELETE Requests**: Returns `"non-llm-request"` to skip model-based routing (used for operations like listing models or deleting responses)
2. Azure OpenAI: Model from `deployment-id` path parameter (`/deployments/{deployment-id}/chat/completions`)
3. Universal LLM: Model from URL path by detecting `/deployments/{model}/` segment (wildcard operations where APIM has no named path parameters)
4. Inference Endpoint: Model from request body JSON (`{"model": "model-name", ...}`)

**Output Variable:**
- requestedModel: The extracted model name, `"non-llm-request"` for GET/DELETE operations, or empty string if not found

Logic:
- GET/DELETE requests return `"non-llm-request"` (no model routing needed)
- First attempts to extract from `deployment-id` path parameter (Azure OpenAI named operations)
- If not found, scans the URL path for `/deployments/{model}/` segment (wildcard operations)
- If not found, attempts to extract from request body `model` field (Inference pattern)
- Returns empty string if no pattern matches

#### Step 1.5: Responses API ID Security (`responses-id-security` / `responses-id-cache-store`)

The OpenAI **Responses API** (`POST /responses`, `GET /responses/{response_id}`, `GET /responses/{response_id}/input_items`, `DELETE /responses/{response_id}`) is stateful: a `response_id` returned by the backend can be re-used by the client to fetch or chain (`previous_response_id`) prior outputs. To prevent **cross-subscription access** to those server-side conversations, the gateway adds a single shared pair of fragments that are wired into all three API surfaces (Azure OpenAI API, Universal LLM API, Unified AI API):

| Fragment | Stage | Responsibility |
|---|---|---|
| `responses-id-security` | inbound | Detects `/responses*` routes, resolves the `response_id` (URL path or `previous_response_id` body), looks up its owner in APIM cache, returns **403** on subscription mismatch and **404** when no cache entry exists for a GET/DELETE. For GET/DELETE it also **hydrates `requestedModel`** from the cache so model-based routing keeps working for those previously model-less operations. |
| `responses-id-cache-store` | outbound | After a successful `POST /responses`, parses the response body, extracts `id`, and writes `key=response-id-{id}` → `value=<subscriptionId>\|<requestedModel>\|<userId>` to APIM internal cache (24h TTL). |

Cache contract:

```
key   = "response-id-" + response_id
value = "<subscriptionId>|<requestedModel>|<userId>"   // userId from JWT 'azp' claim, falling back to subscription name
ttl   = 86400 seconds
```

Routing impact on `set-target-backend-pool`:

- For `POST /responses`, model-based routing is unchanged (model is in body or path).
- For `GET /responses/{id}` and `DELETE /responses/{id}`, the inbound fragment hydrates `requestedModel` from the cache, so `set-target-backend-pool` resolves the **same backend pool** that served the original `POST` — guaranteeing consistent per-conversation backend affinity without any new branches in `set-target-backend-pool` itself.
- For Unified AI, an `apiTypeOverrideBackend` may also be configured for the `responses` api-type; the override still wins, but the ownership check runs first.

Diagnostic outputs:

- `x-aihub-response-id-cached` response header echoes the just-cached id after a successful POST.
- Trace source `Responses-API-Security` logs hydration, ownership mismatches, and cache misses.

#### Step 2: Backend Pool Configuration (set-backend-pools)

The `set-backend-pools` fragment loads all available backend pools:

**Expected Input Variables:**
- requestedModel: The model name extracted from the request payload
- defaultBackendPool: Default backend pool to use when model is not mapped (empty string = error for unmapped models)
- allowedBackendPools: Comma-separated list of allowed backend pool IDs (empty string = all pools allowed)
        
**Output Variables:**
- backendPools: JArray containing all backend pool configurations

```csharp
// Example pool configuration (auto-generated from Bicep)
var pool_0 = new JObject()
{
    { "poolName", "DeepSeek-V3.2-backend-pool" },
    { "poolType", "ai-foundry" },
    { "supportedModels", new JArray("DeepSeek-V3.2") }
};
backendPools.Add(pool_0);
// Pool: aif-citadel-primary (Type: ai-foundry)
var pool_1 = new JObject()
{
    { "poolName", "aif-citadel-primary" },
    { "poolType", "ai-foundry" },
    { "supportedModels", new JArray("gpt-4o") }
};
backendPools.Add(pool_1);
// Pool: aif-citadel-primary (Type: ai-foundry)
var pool_2 = new JObject()
{
    { "poolName", "aif-citadel-primary" },
    { "poolType", "ai-foundry" },
    { "supportedModels", new JArray("gpt-4o-mini") }
};
```

It is worth noting that:
- Each backend supporting multiple models will have multiple pool entries (one per model)
- Backends supporting the same model are grouped into a single load-balanced pool (like in `DeepSeek-V3.2-backend-pool` in the above example)
- This policy fragment can be gateway-region aware to support different routing pools for different regions if needed (like have a self-hosted gateway that will only route to on-premises LLMs while cloud gateway will route to cloud LLMs).
- Policy can be set to allow a default backend pool to be returned if no matching model is found.

#### Step 3: Target Pool Selection (set-target-backend-pool)

The `set-target-backend-pool` fragment matches the requested model to a backend:

**Purpose:**
- Determines which backend pool to route the request to based on the requested model and access permissions
- For non-LLM requests (GET operations), skips backend pool routing entirely
        
**Expected Input Variables:**
- requestedModel: The model name extracted from the request payload (or `"non-llm-request"` for GET operations)
- defaultBackendPool: Default backend pool to use when model is not mapped (default behavior empty string = error for unmapped models)
- allowedBackendPools: Comma-separated list of allowed backend pool IDs (empty string = all pools allowed) - This is usually set at APIM product level to restrict access to certain backend pools per use case
- backendPools: JArray containing all backend pool configurations

**Output Variables:**
- targetBackendPool: The selected backend pool name, `"non-llm-request"` for GET operations, or error code (ERROR_NO_MODEL, ERROR_NO_ALLOWED_POOLS)
- targetPoolType: The type of the selected backend pool (e.g., "azure-openai", "ai-foundry", "non-llm-request")

#### Step 4: Authentication & Routing (set-backend-authorization)

The `set-backend-authorization` fragment configures backend-specific authentication:

**Purpose:** Configures authentication headers and URL rewriting based on backend pool type

**Expected Input Variables:**
- targetPoolType: The type of the target backend pool (e.g., "azure-openai", "ai-foundry", "non-llm-request")
- targetBackendPool: The selected backend pool name
- requestedModel: The model name extracted from the request payload

**Expected `Named Values`:**
- uami-client-id: User-assigned managed identity client ID for authentication

**Side Effects:**
- Sets Authorization header with managed identity token
- Rewrites request URL for Azure OpenAI to include deployment path
- Sets backend service to the target backend pool
- For `non-llm-request`: Skips authentication and backend routing (handled by operation-specific policy)

It is worth noting there is default implementations for Azure LLMs, but this can be extended to support external LLM providers with different authentication schemes (API keys, tokens,...).

| Backend Type | Authentication | URL Rewriting |
|--------------|----------------|---------------|
| `non-llm-request` | Skipped (operation-specific) | None |
| `ai-foundry` | APIM's Managed Identity → Cognitive Services | None (or `/models/` prefix when `skipBackendUrlRewrite` is not set) |
| `azure-openai` | APIM's Managed Identity → Cognitive Services | Injects `/deployments/{model}/` (skipped when `skipBackendUrlRewrite` is set) |
| `aws-bedrock` | AWS SigV4 (IAM access keys via named values) | Path constructed as `/model/{model}/converse` by path-builder |
| `external` | Backend credentials | None |

> **Note:** When the Unified AI API sets `skipBackendUrlRewrite`, the `set-backend-authorization` fragment skips URL rewriting because the `path-builder` fragment handles URI construction instead.

### Unified AI API Routing Flow

The Unified AI API uses a different routing approach: instead of relying on APIM named path parameters, it uses wildcard operations (`/*`) and dynamically detects the API type from the request path. This allows a single API endpoint to serve OpenAI, Inference, Responses, and Gemini patterns.

#### Supported API Types

The `metadata-config` fragment defines the supported API types with their path patterns:

| API Type | Base Path | Path Segment | Default API Version | Use Case |
|----------|-----------|--------------|---------------------|----------|
| `openai` | `/openai` | `/deployments` | `2024-02-15-preview` | Azure OpenAI chat completions |
| `inference` | `/models` | `/models` | `2024-05-01-preview` | AI Foundry inference models |
| `responses` | `/openai/responses` | `/responses` | `2025-03-01-preview` | OpenAI Responses API |
| `responses-v1` | `/openai/v1/responses` | `/openai/v1/responses` | `v1` | OpenAI Responses API (v1) |
| `openai-v1` | `/openai/v1` | `/deployments` | `v1` | OpenAI v1 completions |
| `geminiopenai` | `/v1beta/openai` | `/v1beta/openai` | `v1beta` | Google Gemini OpenAI-compatible |
| `bedrock` | `/model` | `/model` | `bedrock-2024-04-15` | Amazon Bedrock Converse API |

Each API type can optionally define a `backend` property to override pool-based model routing and route to a specific backend directly (via `apiTypeOverrideBackend`).

#### Step 1: Metadata Configuration (metadata-config)

Loads the centralized JSON configuration containing model definitions, API type specs, cache settings, and timeout settings.

**Output Variable:**
- `metadata-config`: Raw JSON string with the full configuration

The models section is dynamically generated from `llmBackendConfig` during Bicep deployment. The API types, cache settings, and timeout settings are static definitions.

#### Step 2: Cache Management (central-cache-manager)

Parses the `metadata-config` JSON and manages caching using APIM's internal cache for performance.

**Cache Behavior:**
- Cache key: `metadata-config-v{config-version}` (e.g., `metadata-config-v1.0.0`)
- TTL: Configurable via `cache-settings.ttl-seconds` (default: 300 seconds)
- Bypass: Send `UAIG-Config-Cache-Bypass: true` header to force a cache miss

**Output Variables:**
- `config-models`: JObject — model name → backend, apiVersion, timeout
- `config-api-types`: JObject — api-type → base-path, path-segment, api-version
- `config-timeout-settings`: JObject — streaming-multiplier and other timeout settings
- `cache-operation`: `"cache-hit"` or `"cache-miss"`

#### Step 3: Request Processing (request-processor)

Analyzes the incoming request to detect the API type and extract the model. This fragment replaces `set-llm-requested-model` for the Unified AI API.

**API Type Detection:**
1. Removes the API path prefix (`/unified-ai`) from the request URL
2. Matches the remaining path against configured `base-path` patterns in `config-api-types` using **case-insensitive prefix matching (`StartsWith`)** and selects the **longest matching base-path** so nested prefixes (e.g. `/openai/v1/responses` vs `/openai/v1` vs `/openai`) always resolve to the most specific api-type independent of declaration order
3. Rejects unrecognized paths with a `403 Forbidden` response (`PathNotAllowed`). For example, `/v2/openai/chat/completions` does **not** match `/openai` and is rejected with 403

**Model Extraction** (in priority order):
1. **GET requests, and DELETE on `/responses*`**: Returns `"non-llm-request"` (operation-level policies handle these). For `/responses/{id}` GET/DELETE the model is later **hydrated from the response-id ownership cache** by `responses-id-security` so model-based routing in `set-target-backend-pool` and `path-builder` still selects the original backend.
2. **Request body**: Extracts `model` field from JSON body
3. **URL path segment**: Extracts model from path using `api-path-segment` (e.g., `/openai/deployments/{model}/...`)

> **Note**: `request-processor` no longer short-circuits GET/DELETE requests — `api-type`, `api-base-path`, `apiTypeOverrideBackend`, and `skipBackendUrlRewrite` are always populated. This is required so that `path-builder` can correctly construct backend paths such as `{api-base-path}/{response-id}` for Responses API GET/DELETE after `responses-id-security` hydrates the model.

**Output Variables:**
- `api-type`: Detected API type (e.g., `openai`, `inference`, `geminiopenai`)
- `requestedModel`: Extracted model identifier (compatible with shared fragments)
- `routing-processed-path`: Request path with API prefix removed
- `response-id`: Response ID for responses API operations
- `parsed-request-body`: Parsed JSON body for downstream use
- `selected-api-version`: API version for backend requests (model-specific or api-type default)
- `is-streaming`: Whether the request has `stream: true`
- `apiTypeOverrideBackend`: Backend override from api-type config (empty for pool-based routing)
- `skipBackendUrlRewrite`: Always `"true"` — tells `set-backend-authorization` to defer URI rewriting to `path-builder`

#### Step 4: Security Handler (security-handler)

Provides unified authentication across all API endpoints.

- **API Key**: Always required (APIM subscription validation)
- **JWT**: Optionally enforced per product via the `jwtRequired` context variable
- **App Roles**: Optionally enforced when `requiredRoles` is set in the product policy

**Output Variables:**
- `auth-type`: `"api-key"`, `"jwt"`, `"api-key-jwt"`, or `"none"`
- `user-id`: From JWT `azp` claim or subscription name
- `jwt-roles`: Comma-separated list of app roles from the JWT token

#### Steps 5–8: Shared Fragment Execution

Steps 5 through 8 use the same shared fragments as the Universal LLM and Azure OpenAI APIs:
- **validate-model-access**: Checks `allowedModels` per product
- **set-backend-pools**: Loads backend pool configurations
- **set-target-backend-pool**: Matches model to pool. For Unified AI, also checks `apiTypeOverrideBackend` — when set, bypasses pool matching and routes to the specified backend directly
- **set-backend-authorization**: Sets managed identity token and backend service. Skips URL rewriting because `skipBackendUrlRewrite` is set by `request-processor`

#### Step 9: Path Builder (path-builder)

Reconstructs the backend URI from known components based on the detected API type. This ensures all requests route to valid backend endpoints.

**Path Construction by API Type:**

| API Type | Backend Path Pattern |
|----------|---------------------|
| `openai` (default) | `{api-base-path}/deployments/{model}/chat/completions` |
| `inference` | `{api-base-path}/chat/completions` |
| `geminiopenai` | `{api-base-path}/chat/completions` |
| `openai-v1` | `{api-base-path}/chat/completions` |
| `responses` / `responses-v1` | `{api-base-path}` or `{api-base-path}/{response-id}` |
| `bedrock` | `/model/{model}/converse` |

**Additional Behavior:**
- Auto-injects `api-version` query parameter for `responses` and `inference` types
- Adds `model` field to request body if not present (for `openai` type)
- Non-LLM requests (GET/DELETE) skip path building entirely (handled by operation-level policies)

#### Step 10: Response Headers (set-response-headers)

Injects `UAIG-*` debug headers into responses when `enableResponseHeaders` is set to `true` in the product policy.

| Header | Source | Description |
|--------|--------|-------------|
| `UAIG-Auth-Type` | security-handler | Authentication method used |
| `UAIG-User-Id` | security-handler | User identifier |
| `UAIG-Subscription` | security-handler | Subscription name |
| `UAIG-Model-Id` | request-processor | Requested model |
| `UAIG-API-Type` | request-processor | Detected API type |
| `UAIG-Processed-Path` | request-processor | Path after prefix removal |
| `UAIG-API-Version` | request-processor | API version sent to backend |
| `UAIG-Is-Streaming` | request-processor | Whether request is streaming |
| `UAIG-Backend` | set-target-backend-pool | Backend that served the request |
| `UAIG-Final-Path` | path-builder | Reconstructed backend path |
| `UAIG-Cache-Operation` | central-cache-manager | `cache-hit` or `cache-miss` |

### Unified AI Deployment Discovery

The Unified AI API includes named operations for model discovery that bypass the wildcard routing:

- **`GET /unified-ai/deployments`** — Lists all available models the subscription has access to (filtered by product policy)
- **`GET /unified-ai/deployments/{deployment-id}`** — Returns details for a specific model, or `404` if not found

These operations use the shared `get-available-models` fragment and are handled by operation-level policies, not the wildcard catch-all.

## Backend Pool Types

### Single Backend (Direct Routing)
When a model is only available on one backend, requests route directly:

```
Model: "Phi-4" → Backend: "aif-citadel-primary"
```

### Backend Pool (Load Balanced)
When multiple backends support the same model, a pool is created:

```
Model: "gpt-4o" → Pool: "gpt-4o-backend-pool"
                    ├── Backend 1 (Priority: 1, Weight: 100)
                    └── Backend 2 (Priority: 2, Weight: 50)
```

**Load Balancing Behavior:**
- **Priority**: Lower value = higher priority (1 is highest)
- **Weight**: Traffic distribution ratio among same-priority backends
- **Failover**: Automatic retry to next backend on 429/503 errors

## Circuit Breaker Protection

Each backend has circuit breaker configuration:

```bicep
circuitBreaker: {
  rules: [{
    failureCondition: {
      count: 3              // Failures before tripping
      interval: 'PT5M'      // Time window
      statusCodeRanges: [
        { min: 429, max: 429 },  // Throttling
        { min: 500, max: 503 }   // Server errors
      ]
    }
    tripDuration: 'PT1M'    // Circuit open duration
    acceptRetryAfter: true  // Honor Retry-After headers
  }]
}
```

## Retry Logic

Both APIs implement automatic retry on transient failures:

```xml
<retry count="2" interval="0" first-fast-retry="true" 
       condition="@(context.Response.StatusCode == 429 || 
                    context.Response.StatusCode >= 500)">
    <forward-request buffer-request-body="true" />
</retry>
```

The Unified AI API extends this with configurable timeouts from `metadata-config`:
- **Base timeout**: 120 seconds (or model-specific value from config)
- **Streaming multiplier**: 3x (configurable via `timeout-settings.streaming-multiplier`)
- Model-specific timeouts are defined in the `models` section of `metadata-config`

## RBAC Integration

Access contracts (applied at a product level) can restrict which backend pools a client can use:

```xml
<!-- Product Policy for specific use case -->
<se t-variable name="allowedBackendPools" 
              value="gpt-4o-backend-pool,aif-citadel-primary" />
```

| Scenario | Behavior |
|----------|----------|
| `requestedModel = "non-llm-request"` | Access control bypassed (GET operations) |
| `allowedBackendPools = ""` | All pools accessible |
| `allowedBackendPools = "pool1,pool2"` | Only listed pools accessible |
| Model supported but pool blocked | 403 Forbidden |

### Non-LLM Request Handling

GET operations (like listing available models) are identified as `"non-llm-request"` and bypass:
- Model validation
- Backend pool routing
- Token usage metrics collection
- Model-based access control

This allows auxiliary endpoints to function without requiring a model parameter in the request.

## Usage Metrics Collection

The `set-llm-usage` fragment emits token metrics for monitoring:

```xml
<llm-emit-token-metric namespace="llm-usage">
    <dimension name="productName" />      <!-- Use case identifier -->
    <dimension name="deploymentName" />   <!-- Model requested -->
    <dimension name="Backend ID" />       <!-- Backend that served request -->
    <dimension name="appId" />            <!-- Client identifier -->
</llm-emit-token-metric>
```

## Policy Fragments Reference

### Shared Fragments (All APIs)

| Fragment | Purpose |
|----------|---------|
| `set-backend-pools` | Loads backend pool configurations |
| `set-target-backend-pool` | Matches model to backend pool with RBAC (extended with `apiTypeOverrideBackend` for Unified AI) |
| `set-backend-authorization` | Sets authentication and backend service (respects `skipBackendUrlRewrite` for Unified AI) |
| `set-llm-usage` | Collects token usage metrics |
| `validate-model-access` | Model access control per product |
| `get-available-models` | Returns filtered list of models for deployment discovery |
| `ai-foundry-compatibility` | CORS configuration for AI Foundry |
| `raise-throttling-events` | Sends throttling metrics on errors |

### Universal LLM / Azure OpenAI Only

| Fragment | Purpose |
|----------|---------|
| `set-llm-requested-model` | Extracts model from request body, URL path parameter, or URL path segment |

### Unified AI-Specific Fragments

| Fragment | Purpose |
|----------|---------|
| `metadata-config` | Centralized JSON configuration for models, API types, cache, and timeout settings |
| `central-cache-manager` | Caches and parses metadata configuration with version-keyed TTL |
| `request-processor` | Detects API type from path, extracts model, sets routing variables |
| `security-handler` | Unified authentication (API Key required + optional JWT per product) |
| `path-builder` | Reconstructs backend URI based on detected API type |
| `set-response-headers` | Injects UAIG-* debug headers when enabled |

## Example Request Flows

### Universal LLM API Request

```http
POST APIM_GATEWAY/models/chat/completions
Content-Type: application/json
api-key: <subscription-key>

{
  "model": "gpt-4o",
  "messages": [{"role": "user", "content": "Hello"}]
}
```

**Flow:**
1. Extract model: `"gpt-4o"` from request body
2. Find pool: `"gpt-4o-backend-pool"` (supports gpt-4o)
3. Pool type: `"ai-foundry"`
4. Authenticate: Managed Identity token
5. Route: Forward to healthy backend in pool

### Azure OpenAI API Request

```http
POST APIM_GATEWAY/openai/deployments/gpt-4o/chat/completions?api-version=2024-02-01
Content-Type: application/json
api-key: <subscription-key>

{
  "messages": [{"role": "user", "content": "Hello"}]
}
```

**Flow:**
1. Extract model: `"gpt-4o"` from URL path parameter
2. Inject model into body: `{"model": "gpt-4o", ...}`
3. Rewrite URL: `/chat/completions` (remove deployment path)
4. Find pool: `"gpt-4o-backend-pool"`
5. Authenticate & route same as Universal LLM API

### Unified AI API — OpenAI Pattern

```http
POST APIM_GATEWAY/unified-ai/openai/deployments/gpt-4o/chat/completions
Content-Type: application/json
api-key: <subscription-key>

{
  "messages": [{"role": "user", "content": "Hello"}]
}
```

**Flow:**
1. Load & cache metadata config
2. Request processor detects api-type: `"openai"` (path contains `/openai`)
3. Extract model: `"gpt-4o"` from path segment `/deployments/gpt-4o/...`
4. Security handler validates API key (JWT if required by product)
5. Find pool: `"gpt-4o-backend-pool"` (shared fragment)
6. Authenticate: Managed Identity token (shared fragment, URL rewrite skipped)
7. Path builder constructs: `/openai/deployments/gpt-4o/chat/completions`
8. Forward to backend with `api-version` query parameter

### Unified AI API — Inference Pattern (Foundry)

```http
POST APIM_GATEWAY/unified-ai/models/chat/completions
Content-Type: application/json
api-key: <subscription-key>

{
  "model": "DeepSeek-V3.2",
  "messages": [{"role": "user", "content": "Hello"}]
}
```

**Flow:**
1. Load & cache metadata config
2. Request processor detects api-type: `"inference"` (path contains `/models`)
3. Extract model: `"DeepSeek-V3.2"` from request body
4. Security handler validates API key
5. Find pool: `"DeepSeek-V3.2-backend-pool"` (shared fragment)
6. Authenticate: Managed Identity token
7. Path builder constructs: `/models/chat/completions`
8. Forward with `api-version=2024-05-01-preview`

### Unified AI API — Gemini Pattern

```http
POST APIM_GATEWAY/unified-ai/v1beta/openai/chat/completions
Content-Type: application/json
api-key: <subscription-key>

{
  "model": "gemini-2.0-flash",
  "messages": [{"role": "user", "content": "Hello"}]
}
```

**Flow:**
1. Load & cache metadata config
2. Request processor detects api-type: `"geminiopenai"` (path contains `/v1beta/openai`)
3. Extract model: `"gemini-2.0-flash"` from request body
4. Security handler validates API key
5. Find pool or use api-type override backend
6. Path builder constructs: `/v1beta/openai/chat/completions`
7. Forward to Gemini backend

### Unified AI API — Bedrock Pattern

```http
POST APIM_GATEWAY/unified-ai/model/us.anthropic.claude-3-5-haiku-20241022-v1:0/converse
Content-Type: application/json
api-key: <subscription-key>

{
  "messages": [
    {
      "role": "user",
      "content": [{"text": "Hello"}]
    }
  ],
  "inferenceConfig": {
    "maxTokens": 512,
    "temperature": 0.5,
    "topP": 0.9
  }
}
```

**Flow:**
1. Load & cache metadata config
2. Request processor detects api-type: `"bedrock"` (path contains `/model`)
3. Extract model: `"us.anthropic.claude-3-5-haiku-20241022-v1:0"` from path segment
4. Security handler validates API key
5. Find pool: `"bedrock-us-east-1"` or direct backend (shared fragment)
6. Authenticate: AWS SigV4 using IAM access keys from named values
7. Path builder constructs: `/model/us.anthropic.claude-3-5-haiku-20241022-v1%3A0/converse`
8. Forward to Bedrock runtime endpoint

### Unified AI API — Model Discovery

```http
GET APIM_GATEWAY/unified-ai/deployments
api-key: <subscription-key>
```

**Flow:**
1. Request processor identifies as `"non-llm-request"` (GET method)
2. Operation-level policy handles the request directly
3. `get-available-models` fragment returns filtered model list based on product access
4. Returns JSON array of available deployments with model metadata

## Troubleshooting

| Error | Cause | Solution |
|-------|-------|----------|
| `400: Model could not be detected` | No model in body or URL | Include `"model"` in request body or path |
| `400: Model 'x' is not supported` | No backend supports model | Check backend configuration |
| `403: backend_pool_access_forbidden` | RBAC blocks pool access | Update product's `allowedBackendPools` |
| `403: PathNotAllowed` | Unified AI request path doesn't match any configured API type | Check `metadata-config` api-types base-paths |
| `401: product_required` | Request not associated with a product subscription | Provide a valid `api-key` header |
| `429: Too Many Requests` | All backends throttling | Wait for retry-after or add capacity |
| `503: Backend pool unavailable` | Circuit breaker open | Wait for trip duration to expire |
| `403: AWS SigV4 auth failure` | Invalid AWS credentials for Bedrock | Verify `aws-access-key`, `aws-secret-key`, and `aws-region` named values contain real credentials (not `NOT_CONFIGURED`) |
| `500: AWSCredentialsNotConfigured` | AWS named values still set to placeholder defaults | Redeploy with `awsAccessKey`, `awsSecretKey`, `awsRegion` parameters or update named values manually |

**Unified AI Debug Headers:**
When `enableResponseHeaders` is set to `true` in the product policy, response headers like `UAIG-API-Type`, `UAIG-Backend`, and `UAIG-Final-Path` help trace the routing decisions made by the gateway.

## Related Guides

- [LLM Backend Onboarding](../bicep/infra/llm-backend-onboarding/README.md) - Configure backends
- [Onboarding New API Types](unified-ai-api-type-onboarding.md) - Add new API types to the Unified AI API
- [Citadel Access Contracts](citadel-access-contracts.md) - Configure use case access
