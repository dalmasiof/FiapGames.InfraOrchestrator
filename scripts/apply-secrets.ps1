$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoDir = Resolve-Path (Join-Path $scriptDir '..')

function Import-DotEnv {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    if (-not (Test-Path $Path)) {
        return
    }

    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()

        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) {
            return
        }

        if ($line -notmatch '^(?<name>[A-Za-z_][A-Za-z0-9_]*)=(?<value>.*)$') {
            return
        }

        $name = $Matches['name']
        $value = $Matches['value'].Trim()

        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }

        [Environment]::SetEnvironmentVariable($name, $value)
    }
}

Import-DotEnv -Path (Join-Path $repoDir '.env')

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    throw 'kubectl not found in PATH.'
}

function Require-Env {
    param(
        [Parameter(Mandatory = $true)][string]$Name
    )

    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Environment variable '$Name' is required."
    }

    return $value
}

$jwtKey = Require-Env -Name 'JWT_KEY'
$sqlSaPassword = Require-Env -Name 'SQLSERVER_SA_PASSWORD'
$rabbitUser = Require-Env -Name 'RABBITMQ_USERNAME'
$rabbitPass = Require-Env -Name 'RABBITMQ_PASSWORD'
$rabbitDefaultPass = Require-Env -Name 'RABBITMQ_DEFAULT_PASS'

$authConnectionString = Require-Env -Name 'AUTH_CONNECTION_STRING'
$catalogConnectionString = Require-Env -Name 'CATALOG_CONNECTION_STRING'
$paymentConnectionString = Require-Env -Name 'PAYMENT_CONNECTION_STRING'
$notificationConnectionString = Require-Env -Name 'NOTIFICATION_CONNECTION_STRING'

function Apply-Secret {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][hashtable]$Literals
    )

    $args = @('create', 'secret', 'generic', $Name)
    foreach ($key in $Literals.Keys) {
        $args += "--from-literal=$key=$($Literals[$key])"
    }

    $args += @('--dry-run=client', '-o', 'yaml')

    $yaml = & kubectl @args
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to generate secret '$Name'."
    }

    $yaml | kubectl apply -f -
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to apply secret '$Name'."
    }
}

Write-Host 'Applying Kubernetes secrets from environment variables...'

Apply-Secret -Name 'sqlserver-secret' -Literals @{
    MSSQL_SA_PASSWORD = $sqlSaPassword
}

Apply-Secret -Name 'rabbitmq-secret' -Literals @{
    RABBITMQ_DEFAULT_PASS = $rabbitDefaultPass
}

Apply-Secret -Name 'auth-api-secret' -Literals @{
    ConnectionStrings__FIAPGamesConnection = $authConnectionString
    Jwt__Key = $jwtKey
    RabbitMq__UserName = $rabbitUser
    RabbitMq__Password = $rabbitPass
}

Apply-Secret -Name 'catalog-api-secret' -Literals @{
    ConnectionStrings__FIAPGamesConnection = $catalogConnectionString
    Jwt__Key = $jwtKey
    RabbitMq__UserName = $rabbitUser
    RabbitMq__Password = $rabbitPass
}

Apply-Secret -Name 'payment-api-secret' -Literals @{
    ConnectionStrings__FIAPGamesConnection = $paymentConnectionString
    Jwt__Key = $jwtKey
    RabbitMq__UserName = $rabbitUser
    RabbitMq__Password = $rabbitPass
}

Apply-Secret -Name 'notification-worker-secret' -Literals @{
    ConnectionStrings__DefaultConnection = $notificationConnectionString
    RabbitMq__UserName = $rabbitUser
    RabbitMq__Password = $rabbitPass
}

Write-Host 'Secrets applied successfully.'
