# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
.SYNOPSIS
    Run preflight checks to validate B2C tenant readiness for HSC mode.

.PARAMETER TenantId
    Your Azure AD B2C tenant ID (GUID).

.PARAMETER AccessToken
    Delegated access token (from 1-admin-setup.ps1).

.PARAMETER RefreshToken
    Refresh token for silent renewal.

.PARAMETER AutoFix
    Automatically fix empty custom attribute descriptions without prompting.

.EXAMPLE
    .\1-hsc-preflight-check.ps1

.EXAMPLE
    .\1-hsc-preflight-check.ps1 -AutoFix
#>

param(
    [string]$TenantId     = $env:HSC_TENANT_ID,
    [string]$AccessToken  = $env:HSC_ACCESS_TOKEN,
    [string]$RefreshToken = $env:HSC_REFRESH_TOKEN,
    [switch]$AutoFix
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

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  HSC MODE - PREFLIGHT CHECK" -ForegroundColor Cyan
Write-Host "============================================`n" -ForegroundColor Cyan

$checks = @{ Pass = 0; Warn = 0; Fail = 0 }

# ── Check 1: Tenant Type ──────────────────────────────────────────
Write-Host "[1/4] Checking tenant type..." -ForegroundColor Yellow
try {
    $org = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/organization" -Method GET -Headers $headers
    $tenantType = $org.value[0].tenantType
    $verifiedDomains = $org.value[0].verifiedDomains | ForEach-Object { $_.name }
    $isB2C = ($verifiedDomains | Where-Object { $_ -match '\.onmicrosoft\.com$' -and $_ -match 'b2c' }).Count -gt 0

    if ($isB2C -or $tenantType -eq 'AAD B2C') {
        Write-Host "  PASS: Tenant appears to be Azure AD B2C" -ForegroundColor Green
        Write-Host "        Domains: $($verifiedDomains -join ', ')" -ForegroundColor Gray
        $checks.Pass++
    } else {
        Write-Host "  WARN: Could not confirm this is a B2C tenant (type: $tenantType)" -ForegroundColor DarkYellow
        Write-Host "        Domains: $($verifiedDomains -join ', ')" -ForegroundColor Gray
        Write-Host "        HSC API only works on B2C tenants." -ForegroundColor DarkYellow
        $checks.Warn++
    }
} catch {
    Write-Host "  FAIL: Could not read organization info" -ForegroundColor Red
    Write-Host "        Ensure the app has Organization.Read.All or Directory.Read.All permission." -ForegroundColor Red
    $checks.Fail++
}

# ── Check 2: Graph API Permissions ────────────────────────────────
Write-Host "`n[2/4] Checking Graph API permissions..." -ForegroundColor Yellow
try {
    Invoke-RestMethod -Uri $hscEndpoint -Method GET -Headers $headers | Out-Null
    Write-Host "  PASS: Can read HSC endpoint (Policy.ReadWrite.AuthenticationFlows granted)" -ForegroundColor Green
    $checks.Pass++
} catch {
    $sc = $null
    try { $sc = [int]$_.Exception.Response.StatusCode } catch {}
    if ($sc -eq 403) {
        Write-Host "  FAIL: 403 Forbidden - missing Policy.ReadWrite.AuthenticationFlows permission" -ForegroundColor Red
        Write-Host "        Grant this permission and admin consent in the Azure portal." -ForegroundColor Red
        $checks.Fail++
    } elseif ($sc -eq 400) {
        Write-Host "  PASS: Permission OK (endpoint returned 400 - may indicate tenant issue)" -ForegroundColor Green
        $checks.Pass++
    } else {
        Write-Host "  WARN: Unexpected response (HTTP $sc)" -ForegroundColor DarkYellow
        $checks.Warn++
    }
}

# ── Check 3: Custom Attributes ────────────────────────────────────
Write-Host "`n[3/4] Checking custom attributes for empty descriptions..." -ForegroundColor Yellow
try {
    $attrs = Get-AllGraphPages -Uri "https://graph.microsoft.com/v1.0/identity/userFlowAttributes" -Headers $headers
    $customAttrs = $attrs | Where-Object { $_.userFlowAttributeType -eq 'custom' }
    $emptyDesc = $customAttrs | Where-Object { [string]::IsNullOrWhiteSpace($_.description) }

    if ($customAttrs.Count -eq 0) {
        Write-Host "  PASS: No custom attributes found. No action needed." -ForegroundColor Green
        $checks.Pass++
    } elseif ($emptyDesc.Count -eq 0) {
        Write-Host "  PASS: All $($customAttrs.Count) custom attribute(s) have descriptions." -ForegroundColor Green
        $checks.Pass++
    } else {
        Write-Host "  FAIL: $($emptyDesc.Count) custom attribute(s) have empty descriptions." -ForegroundColor Red
        Write-Host "        This will cause error AADB2C99089 when enabling HSC mode." -ForegroundColor Red
        Write-Host "        Attributes to fix:" -ForegroundColor Red
        foreach ($a in $emptyDesc) {
            Write-Host "          - $($a.displayName) (id: $($a.id))" -ForegroundColor Red
        }

        if ($AutoFix) {
            Write-Host ""
            Write-Host "        AutoFix: Patching empty descriptions..." -ForegroundColor Cyan
            $fixedCount = 0
            $failedCount = 0
            foreach ($a in $emptyDesc) {
                $desc = "Custom attribute: $($a.displayName)"
                $patchBody = @{ description = $desc } | ConvertTo-Json
                try {
                    Invoke-RestMethod `
                        -Uri "https://graph.microsoft.com/v1.0/identity/userFlowAttributes/$($a.id)" `
                        -Method PATCH -Headers $headers -Body $patchBody | Out-Null
                    Write-Host "          ✓ Fixed: $($a.displayName) → '$desc'" -ForegroundColor Green
                    $fixedCount++
                } catch {
                    Write-Host "          ✗ Failed: $($a.displayName) - $($_.Exception.Message)" -ForegroundColor Red
                    $failedCount++
                }
            }
            Write-Host ""
            if ($failedCount -eq 0) {
                Write-Host "  FIXED: All $fixedCount attribute(s) patched successfully." -ForegroundColor Green
                $checks.Pass++
            } else {
                Write-Host "  PARTIAL: $fixedCount fixed, $failedCount failed. Fix remaining manually." -ForegroundColor DarkYellow
                $checks.Fail++
            }
        } else {
            Write-Host ""
            $fix = Read-Host "        Would you like to auto-fix these now? (Y/N)"
            if ($fix -eq 'Y' -or $fix -eq 'y') {
                Write-Host ""
                $fixedCount = 0
                $failedCount = 0
                foreach ($a in $emptyDesc) {
                    $desc = "Custom attribute: $($a.displayName)"
                    $patchBody = @{ description = $desc } | ConvertTo-Json
                    try {
                        Invoke-RestMethod `
                            -Uri "https://graph.microsoft.com/v1.0/identity/userFlowAttributes/$($a.id)" `
                            -Method PATCH -Headers $headers -Body $patchBody | Out-Null
                        Write-Host "          ✓ Fixed: $($a.displayName) → '$desc'" -ForegroundColor Green
                        $fixedCount++
                    } catch {
                        Write-Host "          ✗ Failed: $($a.displayName) - $($_.Exception.Message)" -ForegroundColor Red
                        $failedCount++
                    }
                }
                Write-Host ""
                if ($failedCount -eq 0) {
                    Write-Host "  FIXED: All $fixedCount attribute(s) patched successfully." -ForegroundColor Green
                    $checks.Pass++
                } else {
                    Write-Host "  PARTIAL: $fixedCount fixed, $failedCount failed. Fix remaining manually." -ForegroundColor DarkYellow
                    $checks.Fail++
                }
            } else {
                Write-Host ""
                Write-Host "        Fix manually with Graph API:" -ForegroundColor Yellow
                Write-Host "        PATCH https://graph.microsoft.com/v1.0/identity/userFlowAttributes/{id}" -ForegroundColor Yellow
                Write-Host '        Body: { "description": "your description" }' -ForegroundColor Yellow
                Write-Host ""
                Write-Host "        Or re-run with -AutoFix to skip this prompt." -ForegroundColor Yellow
                $checks.Fail++
            }
        }
    }
} catch {
    Write-Host "  WARN: Could not read custom attributes (might need IdentityUserFlow.Read.All)" -ForegroundColor DarkYellow
    $checks.Warn++
}

# ── Check 4: Subscription Linked ─────────────────────────────────
Write-Host "`n[4/4] Checking Azure subscription linkage..." -ForegroundColor Yellow
try {
    $orgInfo = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/organization" -Method GET -Headers $headers
    $assignedPlans = $orgInfo.value[0].assignedPlans
    $activePlans = $assignedPlans | Where-Object { $_.capabilityStatus -eq 'Enabled' }

    if ($activePlans.Count -gt 0) {
        Write-Host "  PASS: Tenant has $($activePlans.Count) active plan(s) linked." -ForegroundColor Green
        $checks.Pass++
    } else {
        Write-Host "  WARN: No active plans found. Verify the B2C tenant is linked to an Azure subscription." -ForegroundColor DarkYellow
        Write-Host "        Error NoResourceProviderDataFound will occur if not linked." -ForegroundColor DarkYellow
        Write-Host "        Link via Azure portal: Azure AD B2C > Overview > Subscription." -ForegroundColor DarkYellow
        $checks.Warn++
    }
} catch {
    Write-Host "  WARN: Could not verify subscription linkage." -ForegroundColor DarkYellow
    Write-Host "        Ensure the B2C tenant is linked to a valid Azure subscription." -ForegroundColor DarkYellow
    $checks.Warn++
}

# ── Summary ──────────────────────────────────────────────────────
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  PREFLIGHT RESULTS" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  PASS: $($checks.Pass)" -ForegroundColor Green
Write-Host "  WARN: $($checks.Warn)" -ForegroundColor DarkYellow
Write-Host "  FAIL: $($checks.Fail)" -ForegroundColor Red
Write-Host ""

if ($checks.Fail -gt 0) {
    Write-Host "  RESULT: Fix FAIL items before enabling HSC mode." -ForegroundColor Red
} elseif ($checks.Warn -gt 0) {
    Write-Host "  RESULT: Review WARN items. You may proceed but check the warnings." -ForegroundColor DarkYellow
    Write-Host ""
    Write-Host "Next step — enable HSC mode:" -ForegroundColor Cyan
    Write-Host "  .\2-hsc-setup\2-hsc-enable.ps1" -ForegroundColor White
} else {
    Write-Host "  RESULT: All checks passed. Ready to enable HSC mode." -ForegroundColor Green
    Write-Host ""
    Write-Host "Next step — enable HSC mode:" -ForegroundColor Cyan
    Write-Host "  .\2-hsc-setup\2-hsc-enable.ps1" -ForegroundColor White
}
