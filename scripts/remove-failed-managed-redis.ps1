<#
.SYNOPSIS
    Removes an Azure Managed Redis (Microsoft.Cache/redisEnterprise) resource that is stuck in a
    terminal "Failed" provisioning state before `azd up` / `azd provision` runs.

.DESCRIPTION
    Azure Managed Redis (Redis Enterprise) can hit a transient create failure that leaves the
    cluster in provisioningState = "Failed" ("Create failed" in the portal). A subsequent
    deployment issues an in-place PUT against that failed cluster and the provider rejects it with
    "A resource with this name already exists or is in a conflicting state.", blocking the whole
    deployment. Deleting the failed resource and rerunning succeeds.

    This azd preprovision hook automates that recovery. It discovers Redis Enterprise resources
    tagged for the current azd environment, and deletes ONLY those whose provisioningState is
    exactly "Failed". Resources that are absent, Creating, Updating, or Succeeded are left
    untouched, so the hook is a no-op on healthy environments and safe to run on every deployment.

.NOTES
    Relies on azd-provided environment variables: AZURE_SUBSCRIPTION_ID and AZURE_ENV_NAME.
#>

$ErrorActionPreference = 'Stop'

$subscriptionId = $env:AZURE_SUBSCRIPTION_ID
$environmentName = $env:AZURE_ENV_NAME

if ([string]::IsNullOrWhiteSpace($subscriptionId)) {
    Write-Host 'AZURE_SUBSCRIPTION_ID is not set; skipping failed Managed Redis cleanup.'
    return
}

if ([string]::IsNullOrWhiteSpace($environmentName)) {
    Write-Host 'AZURE_ENV_NAME is not set; skipping failed Managed Redis cleanup.'
    return
}

Write-Host "Checking for failed Azure Managed Redis resources in environment '$environmentName'..."

# Note: `az resource list` cannot combine --tag with --resource-type, so filter by tag and
# narrow to the Redis Enterprise type in the JMESPath query instead.
$resourceIds = az resource list `
    --subscription $subscriptionId `
    --tag "azd-env-name=$environmentName" `
    --query "[?type=='Microsoft.Cache/redisEnterprise'].id" `
    --output tsv

if ($LASTEXITCODE -ne 0) {
    throw 'Failed to list Managed Redis resources.'
}

if ([string]::IsNullOrWhiteSpace($resourceIds)) {
    Write-Host 'No Managed Redis resource currently exists for this azd environment. Nothing to clean up.'
    return
}

foreach ($resourceId in ($resourceIds -split "`n")) {
    $resourceId = $resourceId.Trim()
    if ([string]::IsNullOrWhiteSpace($resourceId)) {
        continue
    }

    $provisioningState = az resource show `
        --ids $resourceId `
        --query 'properties.provisioningState' `
        --output tsv

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to read provisioning state for $resourceId"
    }

    $provisioningState = $provisioningState.Trim()

    if ($provisioningState -eq 'Failed') {
        Write-Host "Managed Redis '$resourceId' is in a Failed state. Deleting it so the deployment can recreate it..."
        az resource delete --ids $resourceId | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to delete the failed Managed Redis resource $resourceId"
        }
        Write-Host "Deleted failed Managed Redis '$resourceId'."
    }
    else {
        Write-Host "Managed Redis '$resourceId' is in state '$provisioningState'. Leaving it untouched."
    }
}
