[CmdletBinding()]
param(
    [string]$SubscriptionId = "64f434dd-5cb0-4c01-971d-7e0e6ba4db9b",
    [string]$ResourceGroup = "rg-fiapgames-prod",
    [int]$TimeoutMinutes = 45
)

$ErrorActionPreference = "Stop"
$aksCluster = "aks-fiapgames-prod"
$keyVault = "kv-fiapgames-64f434dd"
$sqlServer = "sql-fiapgames-prod-64f434dd"
$acrName = "acrfiapgamesprod64f434dd"
$databases = @("fiapgames_auth", "fiapgames_catalog", "fiapgames_payment", "fiapgames_notification")
$terraformDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) "aks"
$workspaceRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$authPath = Join-Path $workspaceRoot "FiapGame.AuthService"
$catalogPath = Join-Path $workspaceRoot "FiapGames.Catalog"
$imageTag = Get-Date -Format "yyyyMMddHHmmss"

function Require-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) { throw "Required command '$Name' was not found. Install it and retry." }
}
function Invoke-Az([string[]]$Arguments) {
    $output = & az @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Azure CLI command failed: az $($Arguments -join ' ')" }
    return $output
}
function Invoke-AzText([string[]]$Arguments) { return ((Invoke-Az $Arguments) -join "`n").Trim() }
function Invoke-Kubectl([string[]]$Arguments) {
    $output = & kubectl @Arguments
    if ($LASTEXITCODE -ne 0) { throw "kubectl command failed: kubectl $($Arguments -join ' ')" }
    return $output
}
function Apply-ManifestWithImage([string]$Path, [string]$ImageName) {
    $manifest = Get-Content -LiteralPath $Path -Raw
    $manifest = $manifest.Replace("${ImageName}:bootstrap", "${ImageName}:$imageTag")
    $manifest | & kubectl apply -f - | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Could not apply manifest $Path." }
}
function Wait-ForAksRunning {
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    do {
        $state = Invoke-AzText @("aks", "show", "--name", $aksCluster, "--resource-group", $ResourceGroup, "--query", "powerState.code", "--output", "tsv")
        if ($state -eq "Running") { return }
        Start-Sleep -Seconds 15
    } while ((Get-Date) -lt $deadline)
    throw "AKS did not reach Running within $TimeoutMinutes minutes. Last state: $state"
}
function Wait-ForApiHealth([string]$ServiceName, [int]$Port) {
    $deadline = (Get-Date).AddMinutes(10)
    $uri = $null
    do {
        $service = (Invoke-Kubectl @("get", "service", $ServiceName, "-o", "json") -join "`n") | ConvertFrom-Json
        $ingress = $service.status.loadBalancer.ingress | Select-Object -First 1
        if ($ingress) {
            $hostName = if ($ingress.ip) { $ingress.ip } else { $ingress.hostname }
            if ($hostName) {
                $uri = "http://{0}:{1}/health/ready" -f $hostName, $Port
                try {
                    $response = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 10
                    if ($response.StatusCode -eq 200) { return $uri }
                } catch { }
            }
        }
        Start-Sleep -Seconds 15
    } while ((Get-Date) -lt $deadline)
    throw "$ServiceName did not return HTTP 200 from /health/ready within 10 minutes. Last address: $uri"
}
function Set-KubernetesRabbitSecret {
    $username = Invoke-AzText @("keyvault", "secret", "show", "--vault-name", $keyVault, "--name", "RabbitMq--UserName", "--query", "value", "--output", "tsv")
    $password = Invoke-AzText @("keyvault", "secret", "show", "--vault-name", $keyVault, "--name", "RabbitMq--Password", "--query", "value", "--output", "tsv")
    if ([string]::IsNullOrWhiteSpace($username) -or [string]::IsNullOrWhiteSpace($password)) { throw "RabbitMQ username/password secrets are empty in Key Vault $keyVault." }
    $username64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($username))
    $password64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($password))
    $secretYaml = @("apiVersion: v1", "kind: Secret", "metadata:", "  name: rabbitmq-auth", "type: Opaque", "data:", "  username: $username64", "  password: $password64") -join "`n"
    $secretYaml | & kubectl apply -f - | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Could not create Kubernetes secret rabbitmq-auth from Key Vault." }
    $username = $null; $password = $null; $secretYaml = $null
}

Require-Command "az"
Require-Command "terraform"
Require-Command "kubectl"
Require-Command "dotnet"

$activeSubscription = Invoke-AzText @("account", "show", "--query", "id", "--output", "tsv")
if ($activeSubscription -ne $SubscriptionId) {
    Invoke-Az @("account", "set", "--subscription", $SubscriptionId) | Out-Null
    $activeSubscription = Invoke-AzText @("account", "show", "--query", "id", "--output", "tsv")
}
if ($activeSubscription -ne $SubscriptionId) { throw "Azure CLI is not targeting expected subscription $SubscriptionId." }

# Run local builds and tests before starting billable compute. These include uncommitted local changes.
foreach ($path in @($authPath, $catalogPath)) {
    if (-not (Test-Path (Join-Path $path "Dockerfile"))) { throw "Expected service checkout/Dockerfile was not found at $path." }
}
if (-not (Test-Path (Join-Path $authPath "k8s/auth-api-migration-job.yaml")) -or -not (Test-Path (Join-Path $catalogPath "k8s/catalog-api-migration-job.yaml"))) {
    throw "Required Auth/Catalog Kubernetes manifests are missing."
}
Write-Host "Running Auth and Catalog automated tests before starting Azure compute..."
Push-Location $authPath
try { & dotnet test "FiapGames.Auth.slnx" --configuration Release; if ($LASTEXITCODE -ne 0) { throw "Auth automated tests failed." } }
finally { Pop-Location }
Push-Location $catalogPath
try { & dotnet test "FiapGames.Catalog.slnx" --configuration Release; if ($LASTEXITCODE -ne 0) { throw "Catalog automated tests failed." } }
finally { Pop-Location }

$elasticEndpoint = Invoke-AzText @("keyvault", "secret", "show", "--vault-name", $keyVault, "--name", "Elasticsearch--Endpoint", "--query", "value", "--output", "tsv")
$elasticKeyId = Invoke-AzText @("keyvault", "secret", "show", "--vault-name", $keyVault, "--name", "Elasticsearch--ApiKey", "--query", "id", "--output", "tsv")
$parsedElasticEndpoint = $null
if ([string]::IsNullOrWhiteSpace($elasticEndpoint) -or [string]::IsNullOrWhiteSpace($elasticKeyId) -or
    -not [Uri]::TryCreate($elasticEndpoint, [UriKind]::Absolute, [ref]$parsedElasticEndpoint) -or $parsedElasticEndpoint.Scheme -ne "https") {
    throw "Elastic HTTPS endpoint/API key is missing or invalid. Recreate the Elastic project and update Key Vault first."
}
if (-not (Test-Path (Join-Path $terraformDirectory "terraform.tfstate"))) { throw "AKS Terraform state is missing at $terraformDirectory." }

Write-Host "Planning AKS and Redis. The script will refuse a Terraform plan that deletes or replaces resources."
$planPath = Join-Path ([IO.Path]::GetTempPath()) ("fiapgames-resume-{0}.tfplan" -f [guid]::NewGuid().ToString("N"))
Push-Location $terraformDirectory
try {
    & terraform init -input=false
    if ($LASTEXITCODE -ne 0) { throw "Terraform init failed." }
    & terraform plan -input=false -var-file="terraform.tfvars.example" -out="$planPath"
    if ($LASTEXITCODE -ne 0) { throw "Terraform plan failed; no infrastructure changes applied." }
    $planJson = (& terraform show -json $planPath) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "Could not inspect Terraform plan." }
    $plan = $planJson | ConvertFrom-Json
    $changes = @($plan.resource_changes | Where-Object { $_.change.actions -notcontains "no-op" })
    $deletions = @($changes | Where-Object { $_.change.actions -contains "delete" })
    if ($deletions.Count -gt 0) { throw "Terraform proposed deleting/replacing resources: $(($deletions | ForEach-Object address) -join ', '). Nothing applied." }
    if ($changes.Count -gt 0) {
        $changes | ForEach-Object { Write-Host ("  {0}: {1}" -f $_.address, ($_.change.actions -join "/")) }
        & terraform apply -input=false -auto-approve $planPath
        if ($LASTEXITCODE -ne 0) { throw "Terraform apply failed." }
    } else { Write-Host "Terraform reports no infrastructure changes." }
} finally { Pop-Location; Remove-Item -LiteralPath $planPath -Force -ErrorAction SilentlyContinue }

foreach ($database in $databases) {
    Invoke-Az @("sql", "db", "update", "--name", $database, "--server", $sqlServer, "--resource-group", $ResourceGroup, "--edition", "GeneralPurpose", "--family", "Gen5", "--capacity", "1", "--compute-model", "Serverless", "--auto-pause-delay", "60", "--min-capacity", "0.5", "--output", "none") | Out-Null
}

Write-Host "Building and publishing local Auth/Catalog source in Azure Container Registry (tag $imageTag)..."
Invoke-Az @("acr", "build", "--registry", $acrName, "--image", "auth-api:$imageTag", "--file", "Dockerfile", $authPath) | Out-Null
Invoke-Az @("acr", "build", "--registry", $acrName, "--image", "catalog-api:$imageTag", "--file", "Dockerfile", $catalogPath) | Out-Null

$aksState = Invoke-AzText @("aks", "show", "--name", $aksCluster, "--resource-group", $ResourceGroup, "--query", "powerState.code", "--output", "tsv")
if ($aksState -eq "Stopped") { Invoke-Az @("aks", "start", "--name", $aksCluster, "--resource-group", $ResourceGroup, "--output", "none") | Out-Null }
Wait-ForAksRunning
Invoke-Az @("aks", "get-credentials", "--resource-group", $ResourceGroup, "--name", $aksCluster, "--overwrite-existing") | Out-Null
Invoke-Kubectl @("wait", "--for=condition=Ready", "nodes", "--all", "--timeout=10m") | Out-Null

Set-KubernetesRabbitSecret
Invoke-Kubectl @("apply", "-f", (Join-Path $authPath "k8s/auth-api-configmap.yaml")) | Out-Null
Invoke-Kubectl @("apply", "-f", (Join-Path $catalogPath "k8s/catalog-api-configmap.yaml")) | Out-Null
Invoke-Kubectl @("apply", "-f", (Join-Path $authPath "k8s/auth-api-service-account.yaml")) | Out-Null
Invoke-Kubectl @("apply", "-f", (Join-Path $catalogPath "k8s/catalog-api-service-account.yaml")) | Out-Null
Invoke-Kubectl @("apply", "-f", (Join-Path $authPath "k8s/rabbitmq.yaml")) | Out-Null
Invoke-Kubectl @("rollout", "status", "statefulset/rabbitmq", "--timeout=10m") | Out-Null

foreach ($job in @("auth-api-migration", "catalog-api-migration")) {
    Invoke-Kubectl @("delete", "job", $job, "--ignore-not-found=true", "--wait=true") | Out-Null
}
Apply-ManifestWithImage (Join-Path $authPath "k8s/auth-api-migration-job.yaml") "auth-api"
Invoke-Kubectl @("wait", "--for=condition=complete", "job/auth-api-migration", "--timeout=30m") | Out-Null
Apply-ManifestWithImage (Join-Path $catalogPath "k8s/catalog-api-migration-job.yaml") "catalog-api"
Invoke-Kubectl @("wait", "--for=condition=complete", "job/catalog-api-migration", "--timeout=30m") | Out-Null

Invoke-Kubectl @("apply", "-f", (Join-Path $authPath "k8s/auth-api-service.yaml")) | Out-Null
Invoke-Kubectl @("apply", "-f", (Join-Path $catalogPath "k8s/catalog-api-service.yaml")) | Out-Null
Apply-ManifestWithImage (Join-Path $authPath "k8s/auth-api-deployment.yaml") "auth-api"
Apply-ManifestWithImage (Join-Path $catalogPath "k8s/catalog-api-deployment.yaml") "catalog-api"
Invoke-Kubectl @("rollout", "status", "deployment/auth-api", "--timeout=10m") | Out-Null
Invoke-Kubectl @("rollout", "status", "deployment/catalog-api", "--timeout=10m") | Out-Null

Invoke-Az @("functionapp", "start", "--name", "func-fcg-notify-64f434dd", "--resource-group", $ResourceGroup, "--output", "none") | Out-Null
$functionDeadline = (Get-Date).AddMinutes(5)
do {
    $functionState = Invoke-AzText @("functionapp", "show", "--name", "func-fcg-notify-64f434dd", "--resource-group", $ResourceGroup, "--query", "state", "--output", "tsv")
    if ($functionState -eq "Running") { break }
    Start-Sleep -Seconds 10
} while ((Get-Date) -lt $functionDeadline)
if ($functionState -ne "Running") { throw "Notification Function did not reach Running state. Last state: $functionState" }

$authHealthUri = Wait-ForApiHealth "auth-api" 8081
$catalogHealthUri = Wait-ForApiHealth "catalog-api" 8082
Write-Host "Environment is ready (image tag $imageTag):"
Write-Host "  Auth:    $authHealthUri"
Write-Host "  Catalog: $catalogHealthUri"
Write-Host "  Auth/Catalog migrations completed; RabbitMQ StatefulSet and API rollouts are healthy; Notification Function is running."
Write-Warning "APIM Developer, ACR, Key Vault, Storage, Log Analytics, SQL storage, AKS disks/IP and Elastic may still incur charges."
