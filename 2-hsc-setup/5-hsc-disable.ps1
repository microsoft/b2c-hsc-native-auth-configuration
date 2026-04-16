# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
.SYNOPSIS
    Disable HSC (High Scale Compatibility) mode.

.PARAMETER TenantId
    Your Azure AD B2C tenant ID (GUID).

.PARAMETER AccessToken
    Delegated access token (from 1-admin-setup.ps1).

.PARAMETER RefreshToken
    Refresh token for silent renewal.

.EXAMPLE
    .\5-hsc-disable.ps1
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

Write-Host "Disabling HSC mode..." -ForegroundColor Yellow
try {
    Invoke-RestMethod -Uri $hscEndpoint -Method DELETE -Headers $headers
    Write-Host "HSC mode disabled successfully!" -ForegroundColor Green
} catch {
    Format-HscError -ErrorRecord $_ -Operation "disable HSC mode"
    exit 1
}
