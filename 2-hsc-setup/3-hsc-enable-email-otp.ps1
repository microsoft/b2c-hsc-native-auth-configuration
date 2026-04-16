# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
.SYNOPSIS
    Enable Email OTP authentication method (required for Native Auth with email).

.PARAMETER TenantId
    Your Azure AD B2C tenant ID (GUID).

.PARAMETER AccessToken
    Delegated access token (from 1-admin-setup.ps1).

.PARAMETER RefreshToken
    Refresh token for silent renewal.

.EXAMPLE
    .\3-hsc-enable-email-otp.ps1
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

Write-Host "Enabling Email OTP authentication method..." -ForegroundColor Yellow
$emailOtpBody = @{
    "@odata.type" = "#microsoft.graph.emailAuthenticationMethodConfiguration"
    allowExternalIdToUseEmailOtp = "enabled"
    state = "enabled"
} | ConvertTo-Json

try {
    Invoke-RestMethod -Uri $emailOtpEndpoint -Method PATCH -Headers $headers -Body $emailOtpBody
    Write-Host "Email OTP enabled successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next step — create a Native Auth app and user flow:" -ForegroundColor Cyan
    Write-Host "  .\3-native-auth-setup\1-native-auth-register-app.ps1 -AppName `"NativeAuthApp`" -CreateFlow" -ForegroundColor White
} catch {
    Format-HscError -ErrorRecord $_ -Operation "enable Email OTP"
    exit 1
}
