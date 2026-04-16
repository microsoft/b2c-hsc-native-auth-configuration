# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
.SYNOPSIS
    Authenticate via device code flow for Graph API access.

.DESCRIPTION
    Automates Step 1 of the HSC setup: authenticates the user interactively via
    device code flow using delegated permissions. No app registration or client
    secret is created — the signed-in user's admin permissions are used directly.

    Required role: Global Administrator or Application Administrator.

.PARAMETER TenantId
    Your Azure AD B2C tenant ID (GUID).

.EXAMPLE
    .\1-admin-setup.ps1 -TenantId "your-tenant-id"
#>

param(
    [Parameter(Mandatory=$true)][string]$TenantId
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\common\graph-helpers.ps1"

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  ADMIN SETUP - Device Code Flow" -ForegroundColor Cyan
Write-Host "============================================`n" -ForegroundColor Cyan

# -- Step 1: Authenticate via Device Code Flow --
Write-Host "[Step 1/2] Authenticating via device code flow..." -ForegroundColor Yellow
Write-Host "  You need Global Administrator or Application Administrator role.`n" -ForegroundColor Gray

$tokenResult = Get-DelegatedToken -TenantId $TenantId

Write-Host "`u{2713} Authenticated successfully`n" -ForegroundColor Green

# -- Step 2: Validate access --
Write-Host "[Step 2/2] Validating tenant access..." -ForegroundColor Yellow
$headers = @{ "Authorization" = "Bearer $($tokenResult.access_token)"; "Content-Type" = "application/json" }

try {
    $org = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/organization" -Method GET -Headers $headers
    $tenantName = $org.value[0].displayName
    $verifiedDomains = $org.value[0].verifiedDomains | ForEach-Object { $_.name }
    Write-Host "`u{2713} Tenant: $tenantName" -ForegroundColor Green
    Write-Host "  Domains: $($verifiedDomains -join ', ')" -ForegroundColor Gray
} catch {
    Write-Error "Failed to validate tenant access. Ensure you have the required admin role."
    exit 1
}

# -- Set environment variables --
$env:HSC_TENANT_ID     = $TenantId
$env:HSC_ACCESS_TOKEN  = $tokenResult.access_token
$env:HSC_REFRESH_TOKEN = $tokenResult.refresh_token

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  ADMIN SETUP COMPLETE" -ForegroundColor Cyan
Write-Host "============================================`n" -ForegroundColor Cyan

Write-Host "Environment variables set for this session:" -ForegroundColor Green
Write-Host "  HSC_TENANT_ID, HSC_ACCESS_TOKEN, HSC_REFRESH_TOKEN" -ForegroundColor Gray
Write-Host "  Subsequent scripts will use these automatically -- no need to pass them as parameters." -ForegroundColor Gray
Write-Host ""
Write-Host "Next step -- run preflight checks:" -ForegroundColor Cyan
Write-Host "  .\2-hsc-setup\1-hsc-preflight-check.ps1" -ForegroundColor White
Write-Host ""
