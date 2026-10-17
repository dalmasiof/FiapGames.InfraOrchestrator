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
$containerApps = @("ca-auth-api", "ca-catalog-api", "ca-payment-api", "ca-rabbitmq-prod")

az account set --subscription $SubscriptionId
$activeSubscription = az account show --query id --output tsv
if ($activeSubscription -ne $SubscriptionId) {
    throw "Azure CLI is not targeting the expected subscription $SubscriptionId."
}

foreach ($app in $containerApps) {
    az containerapp update --name $app --resource-group $ResourceGroup --min-replicas 0 --max-replicas 1 --output none

    $activeRevisions = az containerapp revision list --name $app --resource-group $ResourceGroup --query "[?properties.active].name" --output tsv
    foreach ($revision in $activeRevisions) {
        az containerapp revision deactivate --name $app --resource-group $ResourceGroup --revision $revision --output none
    }
}

az functionapp stop --name $functionApp --resource-group $ResourceGroup --output none

$aksState = az aks show --name $aksCluster --resource-group $ResourceGroup --query powerState.code --output tsv 2>$null
if ($LASTEXITCODE -eq 0 -and $aksState -ne "Stopped") {
    az aks stop --name $aksCluster --resource-group $ResourceGroup --output none
}

foreach ($database in $databases) {
    az sql db update --name $database --server $sqlServer --resource-group $ResourceGroup --edition GeneralPurpose --family Gen5 --capacity 1 --compute-model Serverless --auto-pause-delay 60 --min-capacity 0.5 --output none
}

Write-Host "Ambiente suspenso sem excluir recursos."
Write-Warning "APIM, Cosmos DB, Redis, ACR, Key Vault, Storage, Log Analytics, discos e IPs podem continuar gerando custos."
Write-Host "Consulte os custos residuais antes de considerar a suspensão como custo zero."
