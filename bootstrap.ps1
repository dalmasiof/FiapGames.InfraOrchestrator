$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$rootDir = 'C:\git\FiapGames_MS'

$repos = @(
    'FiapGame.AuthService',
    'FiapGame.PaymentService',
    'FiapGames.Catalog',
    'FiapGames.Notification'
)

Write-Host "Bootstrap: validando workspace em $rootDir..."
if (-not (Test-Path $rootDir)) {
    throw "Workspace não encontrado em $rootDir. Crie a estrutura esperada antes de executar o bootstrap."
}

foreach ($repoName in $repos) {
    $repoPath = Join-Path $rootDir $repoName
    if (-not (Test-Path $repoPath)) {
        throw "Repositório ausente: $repoPath"
    }
}

Write-Host 'Bootstrap: subindo a aplicação com Docker Compose...'
Push-Location $scriptDir
try {
    docker compose up -d --build
} finally {
    Pop-Location
}

Write-Host 'Aplicação orquestrada iniciada com sucesso.'
