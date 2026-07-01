$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$rootDir = Resolve-Path "$scriptDir\.."

$repos = @(
    @{ Name = 'FiapGame.AuthService'; Path = "$rootDir\FiapGame.AuthService"; Url = 'https://github.com/SEU_USUARIO/FiapGame.AuthService.git' },
    @{ Name = 'FiapGame.PaymentService'; Path = "$rootDir\FiapGame.PaymentService"; Url = 'https://github.com/SEU_USUARIO/FiapGame.PaymentService.git' },
    @{ Name = 'FiapGames.Catalog'; Path = "$rootDir\FiapGames.Catalog"; Url = 'https://github.com/SEU_USUARIO/FiapGames.Catalog.git' },
    @{ Name = 'FiapGames.Notification'; Path = "$rootDir\FiapGames.Notification"; Url = 'https://github.com/SEU_USUARIO/FiapGames.Notification.git' }
)

function Ensure-GitInstalled {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'Git não está instalado ou não está no PATH. Instale o Git antes de continuar.'
    }
}

function CloneOrUpdateRepo($repo) {
    if (-not (Test-Path $repo.Path)) {
        if (-not $repo.Url) {
            throw "Repositório local ausente e URL de clone não configurada para $($repo.Name)."
        }

        Write-Host "Clonando $($repo.Name) para $($repo.Path)..."
        git clone $repo.Url $repo.Path
        return
    }

    if (-not (Test-Path (Join-Path $repo.Path '.git'))) {
        Write-Warning "$($repo.Name) existe em disco, mas não parece ser um repositório Git. Pulando atualização."
        return
    }

    Write-Host "Atualizando $($repo.Name)..."
    git -C $repo.Path pull --ff-only
}

Ensure-GitInstalled

Write-Host 'Bootstrap: checando repositórios...'
foreach ($repo in $repos) {
    CloneOrUpdateRepo $repo
}

Write-Host 'Bootstrap: subindo a aplicação com Docker Compose...'
Push-Location $scriptDir
try {
    docker compose up -d --build
} finally {
    Pop-Location
}

Write-Host 'Aplicação orquestrada iniciada com sucesso.'
