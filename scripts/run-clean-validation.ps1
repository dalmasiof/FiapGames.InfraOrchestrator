[CmdletBinding()]
param([switch]$Clean)

$ErrorActionPreference = 'Stop'
$repoDir = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoDir

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Command 'docker' not found in PATH."
}

if ($Clean) {
    Write-Host 'Removing the local Compose environment and volumes...'
    docker compose down -v --remove-orphans
}

Write-Host 'Validating Docker Compose configuration...'
docker compose config --quiet

Write-Host 'Starting the local API environment...'
docker compose up -d --build
docker compose ps
docker compose logs --tail=200
