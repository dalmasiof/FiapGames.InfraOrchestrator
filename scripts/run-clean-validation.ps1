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

function Run-K8s {
    Require-Command -Name 'kubectl'

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
