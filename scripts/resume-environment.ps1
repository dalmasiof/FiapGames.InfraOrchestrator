[CmdletBinding()]
param(
    [string]$SubscriptionId = "64f434dd-5cb0-4c01-971d-7e0e6ba4db9b",
    [string]$ResourceGroup = "rg-fiapgames-prod"
)

$ErrorActionPreference = "Stop"
$aksCluster = "aks-fiapgames-prod"
$sqlServer = "sql-fiapgames-prod-64f434dd"
$functionApp = "func-fcg-notify-64f434dd"
$databases = @("fiapgames_auth", "fiapgames_catalog", "fiapgames_payment", "fiapgames_notification")

az account set --subscription $SubscriptionId
$activeSubscription = az account show --query id --output tsv
if ($activeSubscription -ne $SubscriptionId) {
    throw "Azure CLI is not targeting the expected subscription $SubscriptionId."
}

foreach ($database in $databases) {
    az sql db update --name $database --server $sqlServer --resource-group $ResourceGroup --edition GeneralPurpose --family Gen5 --capacity 1 --compute-model Serverless --auto-pause-delay 60 --min-capacity 0.5 --output none
}

$aksState = az aks show --name $aksCluster --resource-group $ResourceGroup --query powerState.code --output tsv 2>$null
if ($LASTEXITCODE -eq 0 -and $aksState -eq "Stopped") {
    az aks start --name $aksCluster --resource-group $ResourceGroup --output none
}

$containerApps = @("ca-auth-api", "ca-catalog-api", "ca-payment-api", "ca-rabbitmq-prod")
foreach ($app in $containerApps) {
    $latestRevision = az containerapp revision list --name $app --resource-group $ResourceGroup --all --query "sort_by(@, &properties.createdTime)[-1].name" --output tsv
    if ([string]::IsNullOrWhiteSpace($latestRevision)) {
        throw "Nenhuma revisao encontrada para $app."
    }
    az containerapp revision activate --name $app --resource-group $ResourceGroup --revision $latestRevision --output none
}

az containerapp update --name "ca-rabbitmq-prod" --resource-group $ResourceGroup --min-replicas 1 --max-replicas 1 --output none

foreach ($app in @("ca-auth-api", "ca-catalog-api", "ca-payment-api")) {
    az containerapp update --name $app --resource-group $ResourceGroup --min-replicas 0 --max-replicas 1 --output none
}

az functionapp start --name $functionApp --resource-group $ResourceGroup --output none

Write-Host "Ambiente reativado. As APIs podem levar alguns segundos no primeiro acesso."
Write-Warning "APIM, Cosmos DB, Redis, ACR, Key Vault, Storage, Log Analytics, discos e IPs são recursos persistentes e podem continuar cobrando durante a suspensão."
