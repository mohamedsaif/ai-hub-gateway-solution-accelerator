#!/usr/bin/env bash
#
# Removes an Azure Managed Redis (Microsoft.Cache/redisEnterprise) resource that is stuck in a
# terminal "Failed" provisioning state before `azd up` / `azd provision` runs.
#
# Azure Managed Redis (Redis Enterprise) can hit a transient create failure that leaves the
# cluster in provisioningState = "Failed" ("Create failed" in the portal). A subsequent
# deployment issues an in-place PUT against that failed cluster and the provider rejects it with
# "A resource with this name already exists or is in a conflicting state.", blocking the whole
# deployment. Deleting the failed resource and rerunning succeeds.
#
# This azd preprovision hook automates that recovery. It discovers Redis Enterprise resources
# tagged for the current azd environment, and deletes ONLY those whose provisioningState is
# exactly "Failed". Resources that are absent, Creating, Updating, or Succeeded are left
# untouched, so the hook is a no-op on healthy environments and safe to run on every deployment.
#
# Relies on azd-provided environment variables: AZURE_SUBSCRIPTION_ID and AZURE_ENV_NAME.

set -euo pipefail

subscription_id="${AZURE_SUBSCRIPTION_ID:-}"
environment_name="${AZURE_ENV_NAME:-}"

if [ -z "$subscription_id" ]; then
    echo "AZURE_SUBSCRIPTION_ID is not set; skipping failed Managed Redis cleanup."
    exit 0
fi

if [ -z "$environment_name" ]; then
    echo "AZURE_ENV_NAME is not set; skipping failed Managed Redis cleanup."
    exit 0
fi

echo "Checking for failed Azure Managed Redis resources in environment '$environment_name'..."

# Note: `az resource list` cannot combine --tag with --resource-type, so filter by tag and
# narrow to the Redis Enterprise type in the JMESPath query instead.
resource_ids="$(az resource list \
    --subscription "$subscription_id" \
    --tag "azd-env-name=$environment_name" \
    --query "[?type=='Microsoft.Cache/redisEnterprise'].id" \
    --output tsv)"

if [ -z "$resource_ids" ]; then
    echo "No Managed Redis resource currently exists for this azd environment. Nothing to clean up."
    exit 0
fi

while IFS= read -r resource_id; do
    [ -z "$resource_id" ] && continue

    provisioning_state="$(az resource show \
        --ids "$resource_id" \
        --query 'properties.provisioningState' \
        --output tsv)"

    if [ "$provisioning_state" = "Failed" ]; then
        echo "Managed Redis '$resource_id' is in a Failed state. Deleting it so the deployment can recreate it..."
        az resource delete --ids "$resource_id" >/dev/null
        echo "Deleted failed Managed Redis '$resource_id'."
    else
        echo "Managed Redis '$resource_id' is in state '$provisioning_state'. Leaving it untouched."
    fi
done <<< "$resource_ids"
