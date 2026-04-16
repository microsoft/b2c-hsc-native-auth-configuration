# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
.SYNOPSIS
    Check HSC mode and Email OTP status.

.PARAMETER TenantId
    Your Azure AD B2C tenant ID (GUID).

.PARAMETER AccessToken
    Delegated access token (from 1-admin-setup.ps1).

.PARAMETER RefreshToken
    Refresh token for silent renewal.

.EXAMPLE
    .\4-hsc-check-status.ps1
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

# HSC Mode
Write-Host "Checking HSC mode status..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri $hscEndpoint -Method GET -Headers $headers
    Write-Host "  HSC Mode: $($response.externalIdHybridMode)" -ForegroundColor Cyan
} catch {
    $sc = $null
    try { $sc = [int]$_.Exception.Response.StatusCode } catch {}
    if ($sc -eq 404) {
        Write-Host "  HSC Mode: NOT enabled" -ForegroundColor Yellow
    } else {
        Format-HscError -ErrorRecord $_ -Operation "check HSC mode"
    }
}

# Email OTP
Write-Host "`nChecking Email OTP status..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri $emailOtpEndpoint -Method GET -Headers $headers
    Write-Host "  State: $($response.state)" -ForegroundColor Cyan
    Write-Host "  Allow External ID Email OTP: $($response.allowExternalIdToUseEmailOtp)" -ForegroundColor Cyan
} catch {
    Format-HscError -ErrorRecord $_ -Operation "check Email OTP status"
}
