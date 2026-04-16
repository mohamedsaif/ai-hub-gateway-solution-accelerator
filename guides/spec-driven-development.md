# 📐 Spec-Driven Development Guide

## Overview

Citadel Governance Hub follows a **spec-driven development** approach for all API surfaces managed through Azure API Management. API specifications (OpenAPI/Swagger) serve as the **source of truth** — they define the contract before implementation, drive automated validation in CI/CD, and flow into the API Center catalog for enterprise discovery.

This guide explains how to work with API specs in this repository, what governance checks are enforced, and how specs flow through the system.

---

## Why Spec-Driven Development?

| Benefit | How Citadel Implements It |
|---------|--------------------------|
| **Contract-first design** | OpenAPI specs define each API surface before APIM policies or backend logic |
| **Automated governance** | Spectral linting enforces naming, versioning, tagging, and security standards on every PR |
| **Breaking change protection** | oasdiff compares PR specs against the base branch and blocks breaking changes |
| **Centralized discovery** | Specs are synced to Azure API Center — all consumers discover APIs from one catalog |
| **Parallel development** | Teams build consumers against the spec while APIM policies are implemented independently |

---

## Spec File Locations

All API specifications live under `bicep/infra/modules/apim/`:

```
bicep/infra/modules/apim/
├── ai-model-inference/          # AI Model Inference API
│   └── ai-model-inference-api-spec.yaml
├── ai-search-api/               # Azure AI Search
│   ├── ai-search-api-spec.yaml
│   └── Azure AI Search Service API.openapi.yaml
├── doc-intel-api/               # Document Intelligence
│   ├── document-intelligence-2024-11-30.openapi.yaml
│   └── document-intelligence-2024-11-30-compressed.openapi.yaml
├── openai-api/                  # Azure OpenAI
│   ├── OpenAI-Import.openapi.yaml
│   ├── oai-api-spec-2024-02-01.yaml
│   ├── oai-api-spec-2024-05-01-preview.yaml
│   ├── oai-api-spec-2024-06-01.yaml
│   └── oai-api-spec-2024-10-21.yaml
├── translator-api/              # Translator
│   └── translator-api-spec.yaml
├── universal-llm-api/           # Universal LLM (Citadel-authored)
│   ├── Universal-LLM-API.openapi.yaml
│   └── Universal-LLM-Basic-API.openapi.yaml
└── ...                          # Additional API surfaces
```

### Naming Conventions

| Pattern | Usage | Example |
|---------|-------|---------|
| `*-api-spec.yaml` | Citadel-authored or adapted specs | `ai-search-api-spec.yaml` |
| `*.openapi.yaml` | Vendor-imported or standard specs | `Universal-LLM-API.openapi.yaml` |
| `oai-api-spec-{version}.yaml` | Versioned Azure OpenAI specs | `oai-api-spec-2024-06-01.yaml` |

---

## How to Add or Modify an API Spec

### Adding a New API Spec

1. **Create a directory** under `bicep/infra/modules/apim/` for the new API surface:
   ```
   bicep/infra/modules/apim/my-new-api/
   ```

2. **Add the OpenAPI spec** following naming conventions:
   ```
   my-new-api/my-new-api-spec.yaml
   ```

3. **Ensure the spec includes** (enforced by linting):
   - `info.version` — a version string (e.g., `'1.0'`)
   - `operationId` on every operation
   - At least one success response per operation
   - Tags on operations (for API Center categorization)
   - No `localhost` in server URLs

4. **Run linting locally** before committing:
   ```bash
   npm install          # first time only
   npm run lint:spec -- bicep/infra/modules/apim/my-new-api/my-new-api-spec.yaml
   ```

5. **Wire it into APIM** by creating or updating the corresponding Bicep module.

### Modifying an Existing Spec

1. **Make your changes** to the spec file.

2. **Run linting locally**:
   ```bash
   npm run lint:specs
   ```

3. **Check for breaking changes** against the current main branch:
   ```bash
   # Install oasdiff: https://github.com/Tufin/oasdiff
   oasdiff breaking <path-to-original-spec> <path-to-modified-spec>
   ```

4. **If breaking changes are detected**, follow the [versioning strategy](#versioning-strategy) below.

---

## CI Validation Workflow

Every pull request that modifies spec files triggers automated validation:

```
PR opened/updated
    │
    ├── Job 1: Spectral Linting
    │   ├── Runs all Citadel governance rules
    │   ├── Checks operationId, versioning, tagging, security
    │   └── Fails on errors, reports warnings
    │
    └── Job 2: Breaking Change Detection
        ├── Compares modified specs against base branch
        ├── Uses oasdiff to detect breaking changes
        └── Generates summary report on the PR
```

### What Gets Checked

| Rule | Severity | Description |
|------|----------|-------------|
| `operation-operationId` | Error | Every operation must have an operationId |
| `operation-success-response` | Error | Operations must define at least one success response |
| `citadel-info-version-required` | Error | `info.version` must be present |
| `citadel-no-localhost-servers` | Error | Server URLs must not reference localhost |
| `citadel-paths-not-empty` | Error | Specs must define at least one path |
| `citadel-operation-tags` | Warning | Operations should be tagged for API Center |
| `citadel-response-schema` | Warning | Success responses should define a schema |
| `info-description` | Warning | API should have a description |
| `info-contact` | Warning | Contact info is recommended |

### How to Fix Linting Failures

1. Run `npm run lint:specs` locally to see all issues.
2. Errors must be fixed before the PR can merge.
3. Warnings are informational — fix them when practical.
4. For vendor-imported specs with pre-existing issues, some rules are relaxed to `warn` severity. See `.spectral.yaml` for details.

---

## Versioning Strategy

Citadel uses **date-based versioning** for Azure service specs (e.g., `2024-06-01`) and **semver** for Citadel-authored specs (e.g., `1.0`).

### Breaking vs Non-Breaking Changes

| Change Type | Breaking? | Action |
|-------------|-----------|--------|
| Add optional parameter | No | Update spec in place |
| Add new endpoint | No | Update spec in place |
| Remove endpoint or parameter | **Yes** | Create new versioned spec file |
| Change parameter from optional to required | **Yes** | Create new versioned spec file |
| Change response schema | **Yes** | Create new versioned spec file |

### When Breaking Changes Are Necessary

1. Create a new spec file with the updated version in the filename.
2. Keep the old spec file for backward compatibility.
3. Update the APIM Bicep modules to reference the new spec.
4. Document the migration path in the PR description.

---

## How Specs Flow into APIM and API Center

```
                                    ┌──────────────────┐
                                    │   API Center     │
                                    │  (Discovery &    │
                                    │   Catalog)       │
                                    └────────▲─────────┘
                                             │ sync
┌──────────┐    ┌──────────────┐    ┌────────┴─────────┐    ┌──────────────┐
│ OpenAPI   │───▸│ Bicep Module │───▸│   Azure APIM     │───▸│  Consumers   │
│ Spec File │    │ (api.bicep)  │    │  (Gateway)       │    │  (Agents,    │
└──────────┘    └──────────────┘    └──────────────────┘    │   Apps)      │
                                                            └──────────────┘
```

1. **Spec files** define the API contract (paths, schemas, parameters).
2. **Bicep modules** reference the spec and configure APIM (policies, backends, products).
3. **APIM** imports the spec and enforces runtime policies.
4. **API Center** catalogs the API for enterprise-wide discovery.

---

## Access Contracts and Specs

[Citadel Access Contracts](../bicep/infra/citadel-access-contracts/README.md) define how specific use cases connect to the gateway. Each contract references APIs that are defined by specs:

```
bicep/infra/citadel-access-contracts/contracts/
├── hr-chatagent/           # HR Chat Agent use case
├── sales-assistant/        # Sales Assistant use case
├── support-bot/            # Support Bot use case
└── ...
```

When creating a new access contract, ensure the APIs it references have validated specs.

---

## Available npm Scripts

| Command | Description |
|---------|-------------|
| `npm run lint:specs` | Lint all specs (errors fail CI) |
| `npm run lint:specs:warn` | Lint all specs showing all warnings |
| `npm run lint:specs:all` | Lint all specs including vendor files with known issues |
| `npm run lint:spec -- <file>` | Lint a single spec file |
| `npm run validate` | Alias for `lint:specs` |

---

## Configuration

Linting rules are configured in [`.spectral.yaml`](../.spectral.yaml) at the repository root. The configuration:

- Extends the standard OpenAPI ruleset (`spectral:oas`)
- Adds 5 custom Citadel governance rules
- Relaxes certain rules for vendor-imported specs (OpenAI, Azure Cognitive Services) that use OAS 3.1 features in 3.0 documents
- Includes overrides for specific vendor specs with known issues

To customize rules, edit `.spectral.yaml` and refer to the [Spectral documentation](https://docs.stoplight.io/docs/spectral/).

---

## Further Reading

- [Spectral OpenAPI Linting](https://docs.stoplight.io/docs/spectral/)
- [oasdiff Breaking Change Detection](https://github.com/Tufin/oasdiff)
- [Azure API Center](https://learn.microsoft.com/en-us/azure/api-center/overview)
- [Azure API Management](https://learn.microsoft.com/en-us/azure/api-management/)
- [Citadel Access Contracts Guide](../bicep/infra/citadel-access-contracts/README.md)
