param(
    [ValidateSet('docker', 'k8s', 'all')]
    [string]$Mode = 'all',

    [switch]$Clean
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoDir = Resolve-Path "$scriptDir\.."
Set-Location $repoDir

function Require-Command {
    param([string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Command '$Name' not found in PATH."
    }
}

function Get-ManifestFiles {
    param([Parameter(Mandatory = $true)][string]$Pattern)

    return Get-ChildItem -Path (Join-Path $repoDir 'k8s') -Filter $Pattern -File | Select-Object -ExpandProperty FullName
}

function Invoke-KubectlForFiles {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('apply', 'delete')][string]$Action,
        [Parameter(Mandatory = $true)][string[]]$Files,
        [switch]$IgnoreNotFound
    )

    if (-not $Files -or $Files.Count -eq 0) {
        return
    }

    foreach ($file in $Files) {
        if ($Action -eq 'apply') {
            kubectl apply -f $file
        }
        else {
            if ($IgnoreNotFound) {
                kubectl delete -f $file --ignore-not-found=true
            }
            else {
                kubectl delete -f $file
            }
        }
    }
}

function Run-Docker {
    Require-Command -Name 'docker'

    if ($Clean) {
        Write-Host 'Docker clean: compose down -v --remove-orphans'
        docker compose down -v --remove-orphans
    }

    Write-Host 'Docker up: compose up -d --build'
    docker compose up -d --build

    Write-Host 'Docker status: compose ps'
    docker compose ps

    Write-Host 'Docker logs (tail 200)'
    docker compose logs --tail=200
}

function Build-K8sServiceImages {
    Require-Command -Name 'docker'

    $workspaceDir = Resolve-Path (Join-Path $repoDir '..')

    $images = @(
        @{ Name = 'fiapgames/auth-api:latest'; Context = (Join-Path $workspaceDir 'FiapGame.AuthService') },
        @{ Name = 'fiapgames/payment-api:latest'; Context = (Join-Path $workspaceDir 'FiapGame.PaymentService\FiapGames.PaymentService') },
        @{ Name = 'fiapgames/catalog-api:latest'; Context = (Join-Path $workspaceDir 'FiapGames.Catalog') },
        @{ Name = 'fiapgames/notification-worker:latest'; Context = (Join-Path $workspaceDir 'FiapGames.Notification') }
    )

    foreach ($img in $images) {
        if (-not (Test-Path $img.Context)) {
            throw "Docker build context not found: $($img.Context)"
        }

        Write-Host "Building image $($img.Name) from $($img.Context)"
        docker build -t $($img.Name) $($img.Context)
    }
}

function Run-K8s {
    Require-Command -Name 'kubectl'
    Write-Host 'Building local images for Kubernetes'
    Build-K8sServiceImages

    $deploymentFiles = Get-ManifestFiles -Pattern '*deployment.yaml'
    $serviceFiles = Get-ManifestFiles -Pattern '*service.yaml'
    $configMapFiles = Get-ManifestFiles -Pattern '*configmap.yaml'

    if ($Clean) {
        Write-Host 'Kubernetes clean: deleting deployments/services/configmaps/secrets from k8s folder where possible'
        Invoke-KubectlForFiles -Action 'delete' -Files $deploymentFiles -IgnoreNotFound
        Invoke-KubectlForFiles -Action 'delete' -Files $serviceFiles -IgnoreNotFound
        Invoke-KubectlForFiles -Action 'delete' -Files $configMapFiles -IgnoreNotFound
        kubectl delete secret auth-api-secret catalog-api-secret payment-api-secret notification-worker-secret rabbitmq-secret sqlserver-secret --ignore-not-found=true
    }

    Write-Host 'Applying configmaps'
    Invoke-KubectlForFiles -Action 'apply' -Files $configMapFiles

    Write-Host 'Applying secrets from environment variables'
    & "$scriptDir\apply-secrets.ps1"

    Write-Host 'Applying deployments and services'
    Invoke-KubectlForFiles -Action 'apply' -Files $deploymentFiles
    Invoke-KubectlForFiles -Action 'apply' -Files $serviceFiles

    Write-Host 'Restarting app deployments to force newest local images'
    kubectl rollout restart deployment auth-api catalog-api payment-api notification-worker

    Write-Host 'Waiting rollout status'
    kubectl rollout status deployment/auth-api
    kubectl rollout status deployment/catalog-api
    kubectl rollout status deployment/payment-api
    kubectl rollout status deployment/notification-worker

    Write-Host 'Kubernetes status'
    kubectl get pods,svc
}

switch ($Mode) {
    'docker' { Run-Docker }
    'k8s' { Run-K8s }
    'all' {
        Run-Docker
        Run-K8s
    }
}
