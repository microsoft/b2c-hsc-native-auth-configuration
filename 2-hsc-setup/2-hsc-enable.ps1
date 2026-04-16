# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
.SYNOPSIS
    Enable HSC (High Scale Compatibility) mode on a B2C tenant.

.PARAMETER TenantId
    Your Azure AD B2C tenant ID (GUID).

.PARAMETER AccessToken
    Delegated access token (from 1-admin-setup.ps1).

.PARAMETER RefreshToken
    Refresh token for silent renewal.

.EXAMPLE
    .\2-hsc-enable.ps1
#>

param(
    [string]$TenantId     = $env:HSC_TENANT_ID,
    [string]$AccessToken  = $env:HSC_ACCESS_TOKEN,
    [string]$RefreshToken = $env:HSC_REFRESH_TOKEN
)

if (-not $TenantId -or -not $AccessToken -or -not $RefreshToken) {
    Write-Host "ERROR: TenantId, AccessToken, and RefreshToken are required." -ForegroundColor Red
    Write-Host "  Run 1-admin-setup.ps1 first (sets env vars automatically)." -ForegroundColor Yellow
    exit 1
}

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\common\graph-helpers.ps1"
. "$PSScriptRoot\hsc-helpers.ps1"

$headers = Get-HscHeaders -TenantId $TenantId -AccessToken $AccessToken -RefreshToken $RefreshToken

# Check if already enabled
Write-Host "Checking current HSC mode status..." -ForegroundColor Yellow
$alreadyEnabled = $false
try {
    $current = Invoke-RestMethod -Uri $hscEndpoint -Method GET -Headers $headers
    if ($current.externalIdHybridMode -eq 'enabled') {
        $alreadyEnabled = $true
    }
} catch {
    # 404 means not enabled, anything else we'll try enabling anyway
}

if ($alreadyEnabled) {
    Write-Host "HSC mode is already enabled." -ForegroundColor Green
} else {
    Write-Host "Enabling HSC mode..." -ForegroundColor Yellow
    try {
        Invoke-RestMethod -Uri $hscEndpoint -Method POST -Headers $headers -Body "{}"
        Write-Host "HSC mode enabled successfully!" -ForegroundColor Green
        Write-Host ""
        Write-Host "IMPORTANT: Allow up to 1 hour for changes to propagate across all services." -ForegroundColor Yellow
        Write-Host "           A GET request immediately after may return stale data (cache behavior)." -ForegroundColor Yellow
        Write-Host "           The 201 Created response above is the authoritative confirmation." -ForegroundColor Yellow
    } catch {
        Format-HscError -ErrorRecord $_ -Operation "enable HSC mode"
        exit 1
    }
}

Write-Host ""
Write-Host "Next step — enable Email OTP:" -ForegroundColor Cyan
Write-Host "  .\2-hsc-setup\3-hsc-enable-email-otp.ps1" -ForegroundColor White
