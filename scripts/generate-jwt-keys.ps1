#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutputDirectory = (Split-Path -Parent $PSScriptRoot),

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$PrivateKeyPath = Join-Path $OutputDirectory "jwt-private.pem"
$PublicKeyPath = Join-Path $OutputDirectory "jwt-public.pem"
$GitIgnorePath = Join-Path $ProjectRoot ".gitignore"

function Add-PemPatternToGitIgnore {
    $patterns = @("*.pem", "jwt-private.pem.pub")

    if (-not (Test-Path -LiteralPath $GitIgnorePath)) {
        [System.IO.File]::WriteAllText(
            $GitIgnorePath,
            "# Local cryptographic key material$([Environment]::NewLine)$($patterns -join [Environment]::NewLine)$([Environment]::NewLine)",
            [System.Text.UTF8Encoding]::new($false))
        return
    }

    $lines = [System.IO.File]::ReadAllLines($GitIgnorePath)
    $missingPatterns = @($patterns | Where-Object { $lines -notcontains $_ })
    if ($missingPatterns.Count -eq 0) {
        return
    }

    $separator = if ((Get-Item -LiteralPath $GitIgnorePath).Length -eq 0) {
        ""
    }
    else {
        [Environment]::NewLine
    }

    [System.IO.File]::AppendAllText(
        $GitIgnorePath,
        "$separator# Local cryptographic key material$([Environment]::NewLine)$($missingPatterns -join [Environment]::NewLine)$([Environment]::NewLine)",
        [System.Text.UTF8Encoding]::new($false))
}

Add-PemPatternToGitIgnore

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
}

$existingKeyFiles = @($PrivateKeyPath, $PublicKeyPath) |
    Where-Object { Test-Path -LiteralPath $_ }

if ($existingKeyFiles.Count -gt 0 -and -not $Force) {
    $fileList = $existingKeyFiles -join ", "
    throw "Key file(s) already exist: $fileList. Use -Force to replace them."
}

$openssl = Get-Command "openssl" -ErrorAction SilentlyContinue
$sshKeygen = Get-Command "ssh-keygen" -ErrorAction SilentlyContinue

if ($null -ne $openssl) {
    & $openssl.Source genpkey `
        -algorithm RSA `
        -pkeyopt rsa_keygen_bits:2048 `
        -out $PrivateKeyPath

    if ($LASTEXITCODE -ne 0) {
        Remove-Item -LiteralPath $PrivateKeyPath -Force -ErrorAction SilentlyContinue
        throw "OpenSSL failed to generate the RSA private key."
    }

    & $openssl.Source pkey `
        -in $PrivateKeyPath `
        -pubout `
        -out $PublicKeyPath

    if ($LASTEXITCODE -ne 0) {
        Remove-Item -LiteralPath $PrivateKeyPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $PublicKeyPath -Force -ErrorAction SilentlyContinue
        throw "OpenSSL failed to export the RSA public key."
    }
}
elseif ($null -ne $sshKeygen) {
    $openSshPublicKeyPath = "$PrivateKeyPath.pub"

    & $sshKeygen.Source -q -t rsa -b 2048 -m PKCS8 `
        -f $PrivateKeyPath -N '""'

    if ($LASTEXITCODE -ne 0) {
        Remove-Item -LiteralPath $PrivateKeyPath, $openSshPublicKeyPath -Force -ErrorAction SilentlyContinue
        throw "OpenSSH failed to generate the RSA private key."
    }

    try {
        $publicKeyPem = & $sshKeygen.Source -e -m PKCS8 -f $openSshPublicKeyPath
        if ($LASTEXITCODE -ne 0) {
            throw "OpenSSH failed to export the RSA public key."
        }

        [System.IO.File]::WriteAllLines(
            $PublicKeyPath,
            $publicKeyPem,
            [System.Text.UTF8Encoding]::new($false))
    }
    catch {
        Remove-Item -LiteralPath $PrivateKeyPath, $PublicKeyPath -Force -ErrorAction SilentlyContinue
        throw
    }
    finally {
        Remove-Item -LiteralPath $openSshPublicKeyPath -Force -ErrorAction SilentlyContinue
    }
}
else {
    throw "Neither OpenSSL nor OpenSSH (ssh-keygen) was found in PATH. Install one and run this script again."
}

Write-Host "RSA 2048-bit key pair generated successfully." -ForegroundColor Green
Write-Host "Private key (PKCS#8): $PrivateKeyPath"
Write-Host "Public key:          $PublicKeyPath"
Write-Host ""
Write-Warning "Never commit either .pem file to Git. The project .gitignore contains '*.pem'."
Write-Host ""
Write-Host "Copy the private key to the clipboard with:" -ForegroundColor Yellow
Write-Host "  Get-Content -Raw `"$PrivateKeyPath`" | Set-Clipboard"
Write-Host ""
Write-Host "Then create a secret manually in Azure Key Vault with this exact name:" -ForegroundColor Yellow
Write-Host "  Jwt--PrivateKey"
