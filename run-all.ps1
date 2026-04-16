# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
.SYNOPSIS
    One-shot script: runs the full HSC + Native Auth setup end-to-end.

.DESCRIPTION
    Executes all steps in order:
      1. Admin app setup (device code flow — interactive)
      2. Preflight checks
      3. Enable HSC mode
      4. Enable Email OTP
      5. Register Native Auth app + create user flow
      6. Validate setup
      7. (Optional) Test sign-up

    Environment variables are propagated automatically between steps.
    Stop on first failure (-ErrorAction is handled per script).

.PARAMETER TenantId
    Your Azure AD B2C tenant ID (GUID).

.PARAMETER NativeAuthAppName
    Display name for the Native Auth app (default: "NativeAuthApp").

.PARAMETER FlowName
    Display name for the user flow (default: "Native Auth Flow").

.PARAMETER TestUsername
    If provided, runs a passwordless sign-up test at the end.

.PARAMETER SkipAdminSetup
    Skip Step 1 if you already have env vars set (HSC_TENANT_ID, HSC_ACCESS_TOKEN, HSC_REFRESH_TOKEN).

.EXAMPLE
    .\run-all.ps1 -TenantId "your-tenant-id"

.EXAMPLE
    .\run-all.ps1 -TenantId "your-tenant-id" -TestUsername "user@example.com"

.EXAMPLE
    # Resume from step 2 (env vars already set)
    .\run-all.ps1 -SkipAdminSetup -TestUsername "user@example.com"
#>

param(
    [string]$TenantId           = $env:HSC_TENANT_ID,
    [string]$NativeAuthAppName  = "NativeAuthApp",
    [string]$FlowName           = "Native Auth Flow",
    [string]$TestUsername,
    [switch]$SkipAdminSetup
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$Number, [string]$Title) {
    Write-Host "`n╔══════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  STEP $Number — $Title" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════╝`n" -ForegroundColor Cyan
}

function Invoke-Step([string]$Label, [scriptblock]$Command) {
    $global:LASTEXITCODE = 0
    & $Command
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        Write-Host "$Label failed." -ForegroundColor Red
        exit 1
    }
}

# ── Step 1: Admin Setup ──────────────────────────────────────────────────
if (-not $SkipAdminSetup) {
    if (-not $TenantId) {
        Write-Host "ERROR: TenantId is required." -ForegroundColor Red
        Write-Host "  Pass -TenantId or set HSC_TENANT_ID env var." -ForegroundColor Yellow
        exit 1
    }
    Write-Step "1/6" "Admin App Setup"
    Invoke-Step "Step 1" { & "$PSScriptRoot\1-admin-setup\1-admin-setup.ps1" -TenantId $TenantId }
} else {
    Write-Host "`nSkipping admin setup (using existing env vars)..." -ForegroundColor DarkYellow
    if (-not $env:HSC_TENANT_ID -or -not $env:HSC_ACCESS_TOKEN -or -not $env:HSC_REFRESH_TOKEN) {
        Write-Host "ERROR: -SkipAdminSetup requires HSC_TENANT_ID, HSC_ACCESS_TOKEN, HSC_REFRESH_TOKEN env vars." -ForegroundColor Red
        exit 1
    }
}

# ── Step 2: Preflight Check ─────────────────────────────────────────────
Write-Step "2/6" "Preflight Check"
Invoke-Step "Step 2" { & "$PSScriptRoot\2-hsc-setup\1-hsc-preflight-check.ps1" -AutoFix }

# ── Step 3: Enable HSC Mode ─────────────────────────────────────────────
Write-Step "3/6" "Enable HSC Mode"
Invoke-Step "Step 3" { & "$PSScriptRoot\2-hsc-setup\2-hsc-enable.ps1" }

# ── Step 4: Enable Email OTP ────────────────────────────────────────────
Write-Step "4/6" "Enable Email OTP"
Invoke-Step "Step 4" { & "$PSScriptRoot\2-hsc-setup\3-hsc-enable-email-otp.ps1" }

# ── Step 5: Register Native Auth App + Flow ──────────────────────────────
Write-Step "5/6" "Register Native Auth App"
Invoke-Step "Step 5" { & "$PSScriptRoot\3-native-auth-setup\1-native-auth-register-app.ps1" -AppName $NativeAuthAppName -CreateFlow -FlowName $FlowName }

# ── Step 6: Validate Setup ──────────────────────────────────────────────
Write-Step "6/6" "Validate Setup"
Invoke-Step "Step 6" { & "$PSScriptRoot\3-native-auth-setup\3-native-auth-validate.ps1" }

# ── Optional: Test Sign-up ──────────────────────────────────────────────
if ($TestUsername) {
    Write-Host "`n╔══════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║  BONUS — Test Sign-up" -ForegroundColor Green
    Write-Host "╚══════════════════════════════════════════╝`n" -ForegroundColor Green
    & "$PSScriptRoot\4-native-auth-flows\1-native-auth-signup.ps1" -Username $TestUsername
}

Write-Host "`n============================================" -ForegroundColor Green
Write-Host "  ALL STEPS COMPLETED SUCCESSFULLY" -ForegroundColor Green
Write-Host "============================================`n" -ForegroundColor Green

Write-Host "Environment variables available in this session:" -ForegroundColor Cyan
Write-Host "  HSC_TENANT_ID     = $env:HSC_TENANT_ID" -ForegroundColor Gray
Write-Host "  HSC_TENANT_NAME   = $env:HSC_TENANT_NAME" -ForegroundColor Gray
Write-Host "  HSC_NATIVE_APP_ID = $env:HSC_NATIVE_APP_ID" -ForegroundColor Gray
Write-Host ""
Write-Host "You can now run any script without parameters:" -ForegroundColor White
Write-Host "  .\4-native-auth-flows\1-native-auth-signup.ps1 -Username `"user@example.com`"" -ForegroundColor White
Write-Host "  .\4-native-auth-flows\2-native-auth-signin.ps1 -Username `"user@example.com`" -UseOTP" -ForegroundColor White
Write-Host "  .\2-hsc-setup\4-hsc-check-status.ps1" -ForegroundColor White
Write-Host ""
