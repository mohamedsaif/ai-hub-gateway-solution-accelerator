# 🚀 AI Hub Gateway Landing Zone

> ## 🏰 **NEW: AI Citadel Governance Hub v1 - Now in Preview!**
> 
> **The next evolution of AI Hub Gateway is here!** AI Citadel Governance Hub expands enterprise AI governance with three powerful pillars:
> 
> - **🛡️ Governance & Security** - Unified AI gateway, managed credentials, multi-cloud support, AI content safety, AI registry
> - **📊 Observability & Compliance** - Platform-level monitoring, centralized AI evaluations, automated quality assessments
> - **🚀 AI Development Velocity** - Citadel Access & Publish Contracts, agent blueprints, DevOps integration
> 
> **Built on proven AI Hub Gateway practices + Microsoft's latest AI innovations**
> 
> 🎯 **Preview Available Now**: [`citadel-v1` branch](https://github.com/azure-samples/ai-hub-gateway-solution-accelerator/tree/citadel-v1)  
> 📚 **Quick Deployment Guide**: [Citadel Governance Hub Guide](https://github.com/azure-samples/ai-hub-gateway-solution-accelerator/blob/citadel-v1/guides/quick-deployment-guide.md)
> 
> **💡 Recommendation**: New deployments should use the `citadel-v1` branch for access to the latest features. Citadel will become the main branch upon GA.

**Enterprise-ready solution accelerator** for implementing a centralized AI API gateway that empowers organizations to securely leverage multiple Azure AI services with unified governance, monitoring, and cost management.



![AI Hub Gateway Landing Zone](./assets/architecture-1-0-6.png)

## ⭐ What's New (Latest Updates)

🏰 **AI Citadel Governance Hub v1 Preview**
- **Three Pillars Architecture** - Governance & Security, Observability & Compliance, AI Development Velocity
- **AI Registry** - Universal catalog for LLMs, tools (via Model Context Protocol), and agents
- **Citadel Contracts** - Infrastructure-as-code for AI Access & Publish governance
- **Platform AI Evaluations** - Automated quality assessments (groundedness, relevance, coherence, safety) -- Coming Soon
- **Agent Landing Zones** - Ready to integrate with [pre-configured spoke environments with AI Foundry or Container Apps](https://github.com/Azure/AI-Landing-Zones/tree/main)
- **Enhanced Multi-Cloud** - Unified governance across Azure OpenAI, AWS Bedrock, and open-source models

🔒 **Enterprise Security & Compliance**
- **[PII Detection & Masking](./guides/pii-masking-apim.md)** - Automatic detection and redaction of sensitive data
- **[Entra ID Integration](./guides/entraid-auth-validation.md)** - JWT token validation with Zero Trust principles
- **[Bring Your Own Network](./guides/bring-your-own-network.md)** - Deploy into existing VNets with private connectivity

🧠 **Expanded AI Service Portfolio**
- **[Azure OpenAI Realtime API](./guides/openai-onboarding.md)** - WebSocket-based real-time voice & text conversations
- **[Azure Document Intelligence](./guides/ai-search-integration.md)** - Advanced document processing and data extraction
- **[AI Model Inference](./guides/ai-studio-integration.md)** - Custom models from Azure AI Foundry integration
- **[Azure AI Search](./guides/ai-search-integration.md)** - Vector, hybrid, and semantic search capabilities

📊 **Advanced Monitoring & Operations**
- **[Throttling Events Monitoring](./guides/throttling-events-handling.md)** - Real-time 429 error tracking with alerts
- **[Dynamic Throttling Assignment](./guides/dynamic-throttling-assignment.md)** - Intelligent load balancing for PTU models
- **Enhanced Power BI Dashboards** - Advanced usage analytics with cost allocation

🧩 **Use Case Onboarding Automation**
- **[APIM Product + Subscription + KV Secrets (Bicep)](./infra/usecase-onboarding/README.md)** - Automate per-use-case onboarding to the AI Gateway; creates per-service products, subscriptions, and writes endpoint + key secrets to Key Vault. Includes a ready-to-use Financial Assistant example.

## 🎯 Core Capabilities

![ai-hub-gateway-benefits.png](./assets/ai-hub-gateway-benefits.png)

**🏢 Enterprise Governance**
- Centralized access control and API key management
- Managed identity integration (no master keys required)
- Multi-tenant isolation with product-based access control
- Per-use-case onboarding automation for APIM Products and Subscriptions

**⚡ Intelligent Routing**
- Priority-based backend selection with automatic failover
- Regional load balancing across multiple AI backend instances
- Capacity-aware routing with dynamic throttling for PTU models

**💰 Cost Management**
- Real-time usage tracking and charge-back allocation
- Token/Requests-level monitoring across all AI services
- Flexible json based usage data model that supports extension
- Power BI integration for self-service advanced analytics and reporting

**🔐 Security & Compliance**
- Private endpoint connectivity for all managed services services
- Network isolation with VNet integration
- Enterprise authentication with Entra ID
- PII detection and processing
- LLM content safety for prompt and content filtering

## ![one-click-deploy](./assets/one-click-deploy.png) One-click Deploy

Deploy enterprise-ready AI governance in minutes with Azure Developer CLI (azd) or Bicep templates.

### 🏗️ What Gets Deployed

![Azure components](./assets/azure-resources-diagram.svg)

| Component | Purpose | Enterprise Features |
|-----------|---------|-------------------|
| **🚪 API Management** | Central AI gateway with intelligent routing | Load balancing, throttling, JWT validation |
| **📊 Application Insights** | Real-time monitoring & analytics | Custom dashboards, throttling alerts |
| **📨 Event Hub** | Usage data streaming & processing | Real-time cost tracking, compliance logging |
| **🤖 Azure OpenAI** | Multi-region AI deployments (3 regions) | GPT-models, Realtime API, fully private |
| **🛡️ Azure Content Safety** | Centralized LLM protection | Prompt Shield and Content Safety protections |
| **💳 Azure Language Service** | PII entity detection | Natural language based PII entity detection, anonymization |
| **🗄️ Cosmos DB** | Usage analytics & cost allocation | Global distribution, automatic scaling |
| **⚡ Logic App** | Event processing & data transformation | Workflow-based processing |
| **🔐 Managed Identity** | Zero-credential authentication | Secure service-to-service communication |
| **🔗 Virtual Network** | Private connectivity & isolation | BYOVNET support, private endpoints |

### 📋 Prerequisites

**Azure Requirements:**
- Azure Account with [OpenAI access approved](https://aka.ms/oaiapply) 
- Subscription with `Microsoft.Authorization/roleAssignments/write` permissions
- Sufficient OpenAI capacity in target regions (East US, North Central US, East US 2)

**Development Tools:**
- [Azure Developer CLI (azd)](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd)
- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli)
- [VS Code](https://code.visualstudio.com/Download) (optional)

### 🚀 Quick Deploy

Review the [main.bicep](./infra/main.bicep) configuration, then deploy:

```bash
# Authenticate and setup environment
azd auth login
azd env new ai-hub-gateway-dev

# Deploy everything
azd up
```

> 💡 **Tip**: Use Azure Cloud Shell to avoid local setup. If deployment fails, retry `azd up` - it may be a [transient error](./guides/deployment-troubleshooting.md).

Once deployed, access your AI Gateway through the Azure API Management portal:

![apim-test](./assets/apim-test.png)

## ![docs](./assets/supporting-documents.png) Supporting Documents

Comprehensive guides to master AI Hub Gateway implementation and operations.

### 🏗️ **Architecture & Deployment**
| Guide | Description |
|-------|-------------|
| [Architecture Overview](./guides/architecture.md) | Complete system design and component relationships |
| [Deployment Guide](./guides/deployment.md) | Step-by-step deployment instructions |
| [Enterprise Provisioning](./guides/enterprise-provisioning.md) | **NEW**: Branch-based deployment strategy, parameter management, and CI/CD automation |
| [APIM Configuration](./guides/apim-configuration.md) | Advanced API Management policies and routing |
| [API Diagnostics Configuration](./guides/api-diagnostics-configuration.md) | **NEW**: Configure logging and observability for LLM inference APIs |
| [Bring Your Own Network](./guides/bring-your-own-network.md) | Deploy into existing VNets |
| [Deployment Troubleshooting](./guides/deployment-troubleshooting.md) | Common issues and solutions |

### 🔧 **Service Integration**
| Guide | Description |
|-------|-------------|
| [OpenAI Onboarding](./guides/openai-onboarding.md) | Add new OpenAI instances and models |
| [AI Search Integration](./guides/ai-search-integration.md) | Vector search and RAG capabilities |
| [AI Foundry Integration](./guides/ai-studio-integration.md) | Custom model deployment |
| [End-to-end Scenario](./guides/end-to-end-scenario.md) | Complete chat-with-data implementation |

### 🛡️ **Security & Compliance**
| Guide | Description |
|-------|-------------|
| [PII Detection & Masking](./guides/pii-masking-apim.md) | Automated data protection |
| [Entra ID Authentication](./guides/entraid-auth-validation.md) | JWT validation and Zero Trust |
| [Use Case Onboarding](./guides/use-case-onboarding-decision-guide.md) | Multi-service AI solution patterns |

### 📊 **Monitoring & Analytics**
| Guide | Description |
|-------|-------------|
| [Power BI Dashboard](./guides/power-bi-dashboard.md) | Usage analytics and cost allocation |
| [Throttling Events](./guides/throttling-events-handling.md) | Real-time 429 error monitoring |
| [Dynamic Throttling](./guides/dynamic-throttling-assignment.md) | Intelligent load balancing |
| [Usage Ingestion](./guides/openai-usage-ingestion.md) | Token tracking and billing |

### ⚙️ **Advanced Features**
| Guide | Description |
|-------|-------------|
| [Hybrid Deployment](./guides/ai-hub-gateway-hybrid-deployment.md) | Multi-cloud and edge scenarios |
| [Use Case Onboarding (APIM Product Automation)](./infra/usecase-onboarding/README.md) | Automate per-use-case APIM Products, Subscriptions, and Key Vault secrets; includes “Financial Assistant” example |