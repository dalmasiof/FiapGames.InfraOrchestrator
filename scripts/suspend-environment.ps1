[CmdletBinding()]
param(
    [string]$SubscriptionId = "64f434dd-5cb0-4c01-971d-7e0e6ba4db9b",
    [string]$ResourceGroup = "rg-fiapgames-prod"
)

$ErrorActionPreference = "Stop"
$aksCluster = "aks-fiapgames-prod"
$sqlServer = "sql-fiapgames-prod-64f434dd"
$databases = @("fiapgames_auth", "fiapgames_catalog", "fiapgames_payment", "fiapgames_notification")
$containerApps = @("ca-auth-api", "ca-catalog-api", "ca-payment-api", "ca-rabbitmq-prod")
$redisName = "redis-fiapgames-64f434dd"

function Require-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found. Install it and retry."
    }
}

function Invoke-Az([string[]]$Arguments) {
    $output = & az @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI command failed: az $($Arguments -join ' ')"
    }
    return $output
}

function Invoke-AzText([string[]]$Arguments) {
    $output = Invoke-Az $Arguments
    return (($output -join "`n").Trim())
}

Require-Command "az"
Require-Command "kubectl"

$activeSubscription = Invoke-AzText @("account", "show", "--query", "id", "--output", "tsv")
if ($activeSubscription -ne $SubscriptionId) {
    Invoke-Az @("account", "set", "--subscription", $SubscriptionId) | Out-Null
    $activeSubscription = Invoke-AzText @("account", "show", "--query", "id", "--output", "tsv")
}
if ($activeSubscription -ne $SubscriptionId) {
    throw "Azure CLI is not targeting the expected subscription $SubscriptionId."
}

$aksState = Invoke-AzText @("aks", "show", "--name", $aksCluster, "--resource-group", $ResourceGroup, "--query", "powerState.code", "--output", "tsv")
if ($aksState -ne "Stopped") {
    Invoke-Az @("aks", "get-credentials", "--resource-group", $ResourceGroup, "--name", $aksCluster, "--overwrite-existing") | Out-Null

    # Remove public LoadBalancer frontends before stopping the nodes to avoid retaining their IP allocations.
    & kubectl delete service auth-api catalog-api --ignore-not-found=true --wait=true
    if ($LASTEXITCODE -ne 0) { throw "Could not remove the AKS public services. AKS was not stopped." }

    # Keep the deployments and RabbitMQ data, but prevent APIs from restarting against a deleted cache.
    & kubectl scale deployment/auth-api deployment/catalog-api --replicas=0
    if ($LASTEXITCODE -ne 0) { throw "Could not scale API deployments to zero. AKS was not stopped." }
}

Invoke-Az @("functionapp", "stop", "--name", "func-fcg-notify-64f434dd", "--resource-group", $ResourceGroup, "--output", "none") | Out-Null

# Keep legacy Container Apps deactivated; the active demo runtime is AKS.
foreach ($app in $containerApps) {
    $appName = Invoke-AzText @("containerapp", "list", "--resource-group", $ResourceGroup, "--query", "[?name=='$app'].name | [0]", "--output", "tsv")
    if (-not [string]::IsNullOrWhiteSpace($appName)) {
        Invoke-Az @("containerapp", "update", "--name", $app, "--resource-group", $ResourceGroup, "--min-replicas", "0", "--max-replicas", "1", "--output", "none") | Out-Null
        $activeRevisions = Invoke-AzText @("containerapp", "revision", "list", "--name", $app, "--resource-group", $ResourceGroup, "--query", "[?properties.active].name", "--output", "tsv")
        foreach ($revision in ($activeRevisions -split "\r?\n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
            Invoke-Az @("containerapp", "revision", "deactivate", "--name", $app, "--resource-group", $ResourceGroup, "--revision", $revision, "--output", "none") | Out-Null
        }
    }
}

if ($aksState -ne "Stopped") {
    Invoke-Az @("aks", "stop", "--name", $aksCluster, "--resource-group", $ResourceGroup, "--output", "none") | Out-Null
}

$deadline = (Get-Date).AddMinutes(30)
do {
    $aksState = Invoke-AzText @("aks", "show", "--name", $aksCluster, "--resource-group", $ResourceGroup, "--query", "powerState.code", "--output", "tsv")
    if ($aksState -eq "Stopped") { break }
    Start-Sleep -Seconds 15
} while ((Get-Date) -lt $deadline)
if ($aksState -ne "Stopped") {
    throw "AKS did not reach Stopped state within 30 minutes. Last state: $aksState"
}

# Shorten idle delay for the next automatic pause. General Purpose serverless permits a 15-minute minimum.
foreach ($database in $databases) {
    Invoke-Az @("sql", "db", "update", "--name", $database, "--server", $sqlServer, "--resource-group", $ResourceGroup, "--edition", "GeneralPurpose", "--family", "Gen5", "--capacity", "1", "--compute-model", "Serverless", "--auto-pause-delay", "15", "--min-capacity", "0.5", "--output", "none") | Out-Null
}
# The cache is disposable and has no pause mode in this setup. Terraform recreates it on resume.
$redisNames = Invoke-AzText @("redis", "list", "--resource-group", $ResourceGroup, "--query", "[?name=='$redisName'].name | [0]", "--output", "tsv")
if (-not [string]::IsNullOrWhiteSpace($redisNames)) {
    Write-Host "Deleting disposable Redis cache $redisName..."
    Invoke-Az @("redis", "delete", "--name", $redisName, "--resource-group", $ResourceGroup, "--yes", "--output", "none") | Out-Null
    $redisDeleteDeadline = (Get-Date).AddMinutes(30)
    do {
        $remainingRedis = Invoke-AzText @("redis", "list", "--resource-group", $ResourceGroup, "--query", "[?name=='$redisName'].name | [0]", "--output", "tsv")
        if ([string]::IsNullOrWhiteSpace($remainingRedis)) { break }
        Start-Sleep -Seconds 15
    } while ((Get-Date) -lt $redisDeleteDeadline)
    if (-not [string]::IsNullOrWhiteSpace($remainingRedis)) {
        throw "Redis deletion did not complete within 30 minutes. AKS is already stopped; inspect Redis deletion before resuming."
    }
}
else {
    Write-Host "Redis cache is already absent."
}


Write-Host "AKS, APIs, Redis, Function and legacy Container Apps are suspended. SQL databases will auto-pause after up to 15 minutes of inactivity."
Write-Warning "This is not zero-cost: APIM Developer, ACR, Key Vault, Storage, Log Analytics, SQL storage, AKS disks/IP and Elastic Marketplace may still be billed. Elastic is externally managed and was not deleted."
