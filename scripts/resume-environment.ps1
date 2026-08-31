[CmdletBinding()]
param(
    [string]$SubscriptionId = "64f434dd-5cb0-4c01-971d-7e0e6ba4db9b",
    [string]$ResourceGroup = "rg-fiapgames-prod"
)

$ErrorActionPreference = "Stop"
$sqlServer = "sql-fiapgames-prod-64f434dd"
$functionApp = "func-fcg-notify-64f434dd"
$databases = @("fiapgames_auth", "fiapgames_catalog", "fiapgames_payment", "fiapgames_notification")

az account set --subscription $SubscriptionId

foreach ($database in $databases) {
    az sql db update --name $database --server $sqlServer --resource-group $ResourceGroup --edition Basic --capacity 5 --compute-model Provisioned --output none
}

az containerapp update --name "ca-rabbitmq-prod" --resource-group $ResourceGroup --min-replicas 1 --max-replicas 1 --output none

foreach ($app in @("ca-auth-api", "ca-catalog-api", "ca-payment-api")) {
    az containerapp update --name $app --resource-group $ResourceGroup --min-replicas 0 --max-replicas 1 --output none
}

az functionapp start --name $functionApp --resource-group $ResourceGroup --output none

Write-Host "Ambiente reativado. As APIs podem levar alguns segundos no primeiro acesso."
