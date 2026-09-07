$ErrorActionPreference = 'Stop'

$rootDir = Resolve-Path (Join-Path $PSScriptRoot '..')
$repos = @(
    'FiapGame.AuthService',
    'FiapGame.PaymentService',
    'FiapGames.Catalog'
)

Write-Host "Bootstrap: validating workspace at $rootDir..."
foreach ($repoName in $repos) {
    $repoPath = Join-Path $rootDir $repoName
    if (-not (Test-Path $repoPath)) {
        throw "Repository not found: $repoPath"
    }
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Command 'docker' not found in PATH."
}

Push-Location $PSScriptRoot
try {
    docker compose config --quiet
    docker compose up -d --build
}
finally {
    Pop-Location
}

Write-Host 'Local API environment started successfully.'
