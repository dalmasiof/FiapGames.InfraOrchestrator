param(
    [Parameter(Mandatory)]
    [ValidateSet("auth", "catalog", "payment")]
    [string] $Service,

    [string] $ResourceGroup = "rg-fiapgames-prod",
    [string] $EnvironmentName = "cae-fiapgames-prod",
    [string] $RegistryName = "acrfiapgamesprod64f434dd",
    [string] $ImageTag = "subscription-migration",
    [string] $KeyVaultUri = "https://kv-fiapgames-64f434dd.vault.azure.net/",
    [string] $ManagedIdentityResourceId = "/subscriptions/64f434dd-5cb0-4c01-971d-7e0e6ba4db9b/resourceGroups/rg-fiapgames-prod/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-fiapgames-workloads-prod",
    [string] $ManagedIdentityClientId = "dfff11eb-a350-4ccb-a466-dee3265a9bf1"
)

$ErrorActionPreference = "Stop"
$jobName = "${Service}-migration-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
$registryServer = "${RegistryName}.azurecr.io"
$image = "${registryServer}/${Service}-api:${ImageTag}"

try {
    $credentials = az acr credential show --name $RegistryName --output json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw "Unable to read ACR credentials." }

    az containerapp job create `
        --name $jobName `
        --resource-group $ResourceGroup `
        --environment $EnvironmentName `
        --trigger-type Manual `
        --replica-timeout 1800 `
        --replica-retry-limit 0 `
        --replica-completion-count 1 `
        --parallelism 1 `
        --image $image `
        --cpu 0.5 `
        --memory 1Gi `
        --registry-server $registryServer `
        --registry-username $credentials.username `
        --registry-password $credentials.passwords[0].value `
        --env-vars ASPNETCORE_ENVIRONMENT=Production KeyVaultUri=$KeyVaultUri AZURE_CLIENT_ID=$ManagedIdentityClientId `
        --args=--migrate `
        --output none
    if ($LASTEXITCODE -ne 0) { throw "Unable to create migration job." }

    $identityAssigned = $false
    foreach ($attempt in 1..12) {
        az containerapp job identity assign `
            --name $jobName `
            --resource-group $ResourceGroup `
            --user-assigned $ManagedIdentityResourceId `
            --output none
        if ($LASTEXITCODE -eq 0) {
            $identityAssigned = $true
            break
        }
        Start-Sleep -Seconds 10
    }
    if (-not $identityAssigned) { throw "Unable to assign the workload identity to the migration job." }

    $executionName = az containerapp job start --name $jobName --resource-group $ResourceGroup --query name --output tsv
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($executionName)) { throw "Unable to start migration job." }

    foreach ($attempt in 1..180) {
        Start-Sleep -Seconds 10
        $status = az containerapp job execution show --name $jobName --resource-group $ResourceGroup --job-execution-name $executionName --query properties.status --output tsv
        Write-Host "Migration status: $status"
        if ($status -eq "Succeeded") { return }
        if ($status -in @("Failed", "Stopped", "Degraded", "Unknown")) { throw "Migration execution ended with status $status." }
    }

    throw "Migration timed out after 30 minutes."
}
finally {
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    az containerapp job delete --name $jobName --resource-group $ResourceGroup --yes --output none 2>$null
    $ErrorActionPreference = $previousErrorActionPreference
}
