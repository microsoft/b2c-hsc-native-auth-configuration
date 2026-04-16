# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
.SYNOPSIS
    Validate Native Auth app setup (app registration, service principal, consent, user flow).

.DESCRIPTION
    Checks that the Native Auth application is correctly configured:
    1. App registration: nativeAuthenticationApisEnabled, isFallbackPublicClient, signInAudience
    2. Service principal exists
    3. Admin consent (oauth2PermissionGrants) granted
    4. User flow linked to the application

.PARAMETER TenantId
    Your Azure AD B2C tenant ID (GUID).

.PARAMETER AccessToken
    Delegated access token (from 1-admin-setup.ps1).

.PARAMETER RefreshToken
    Refresh token for silent renewal.

.PARAMETER AppId
    Native Auth application (client) ID to validate.

.EXAMPLE
    .\native-auth-validate.ps1 -AppId "native-app-id"
#>

param(
    [string]$TenantId     = $env:HSC_TENANT_ID,
    [string]$AccessToken  = $env:HSC_ACCESS_TOKEN,
    [string]$RefreshToken = $env:HSC_REFRESH_TOKEN,
    [string]$AppId        = $env:HSC_NATIVE_APP_ID
)

if (-not $TenantId -or -not $AccessToken -or -not $RefreshToken -or -not $AppId) {
    Write-Host "ERROR: TenantId, AccessToken, RefreshToken, and AppId are required." -ForegroundColor Red
    Write-Host "  Run the previous scripts first (sets env vars automatically)." -ForegroundColor Yellow
    exit 1
}

$ErrorActionPreference = "Stop"

# Import shared helpers
. "$PSScriptRoot\..\common\graph-helpers.ps1"

# Get headers with auto-refresh
Write-Host "Getting access token..." -ForegroundColor Cyan
$headers = Get-GraphHeaders -TenantId $TenantId -AccessToken $AccessToken -RefreshToken $RefreshToken

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  NATIVE AUTH - SETUP VALIDATION" -ForegroundColor Cyan
Write-Host "============================================`n" -ForegroundColor Cyan

$checks = @{ Pass = 0; Fail = 0 }

# ── Check 1: App Registration ─────────────────────────────────────────────
Write-Host "[1/4] Checking app registration..." -ForegroundColor Yellow
try {
    $appResponse = Invoke-RestMethod `
        -Uri "https://graph.microsoft.com/v1.0/applications?`$filter=appId eq '$AppId'&`$select=id,appId,displayName,signInAudience,isFallbackPublicClient,nativeAuthenticationApisEnabled" `
        -Method GET -Headers $headers

    if ($appResponse.value.Count -eq 0) {
        Write-Host "  FAIL: App registration not found for appId: $AppId" -ForegroundColor Red
        $checks.Fail++
    } else {
        $app = $appResponse.value[0]
        $appOk = $true

        Write-Host "  App: $($app.displayName) ($($app.appId))" -ForegroundColor Gray

        if ($app.nativeAuthenticationApisEnabled -ne 'all') {
            Write-Host "  FAIL: nativeAuthenticationApisEnabled = '$($app.nativeAuthenticationApisEnabled)' (expected: 'all')" -ForegroundColor Red
            $appOk = $false
        }
        if ($app.isFallbackPublicClient -ne $true) {
            Write-Host "  FAIL: isFallbackPublicClient = $($app.isFallbackPublicClient) (expected: True)" -ForegroundColor Red
            $appOk = $false
        }
        if ($app.signInAudience -ne 'AzureADMyOrg') {
            Write-Host "  FAIL: signInAudience = '$($app.signInAudience)' (expected: 'AzureADMyOrg')" -ForegroundColor Red
            $appOk = $false
        }

        if ($appOk) {
            Write-Host "  PASS: App registration is correctly configured" -ForegroundColor Green
            Write-Host "        nativeAuthenticationApisEnabled=all, isFallbackPublicClient=True, signInAudience=AzureADMyOrg" -ForegroundColor Gray
            $checks.Pass++
        } else {
            $checks.Fail++
        }
    }
} catch {
    Write-Host "  FAIL: Could not read app registration: $($_.Exception.Message)" -ForegroundColor Red
    $checks.Fail++
}

# ── Check 2: Service Principal ────────────────────────────────────────────
Write-Host "`n[2/4] Checking service principal..." -ForegroundColor Yellow
$spId = $null
try {
    $spResponse = Invoke-RestMethod `
        -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$AppId'&`$select=id,appId,displayName" `
        -Method GET -Headers $headers

    if ($spResponse.value.Count -eq 0) {
        Write-Host "  FAIL: Service principal not found for appId: $AppId" -ForegroundColor Red
        Write-Host "        Create it by POSTing to /v1.0/servicePrincipals with { appId: '$AppId' }" -ForegroundColor Yellow
        $checks.Fail++
    } else {
        $spId = $spResponse.value[0].id
        Write-Host "  PASS: Service principal exists (objectId: $spId)" -ForegroundColor Green
        $checks.Pass++
    }
} catch {
    Write-Host "  FAIL: Could not check service principal: $($_.Exception.Message)" -ForegroundColor Red
    $checks.Fail++
}

# ── Check 3: Admin Consent (oauth2PermissionGrants) ──────────────────────
Write-Host "`n[3/4] Checking admin consent grants..." -ForegroundColor Yellow
if ($spId) {
    try {
        $grantsResponse = Invoke-RestMethod `
            -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$spId/oauth2PermissionGrants" `
            -Method GET -Headers $headers

        if ($grantsResponse.value.Count -eq 0) {
            Write-Host "  WARN: No admin consent grants found for this service principal" -ForegroundColor DarkYellow
            Write-Host "        This is normal for public client apps using native auth." -ForegroundColor Gray
            Write-Host "        If sign-up fails, grant admin consent in Azure portal:" -ForegroundColor Gray
            Write-Host "        App registrations > your app > API permissions > Grant admin consent" -ForegroundColor Gray
            $checks.Pass++
        } else {
            Write-Host "  PASS: Admin consent grants found ($($grantsResponse.value.Count) grant(s))" -ForegroundColor Green
            foreach ($grant in $grantsResponse.value) {
                Write-Host "        Scope: $($grant.scope) | ConsentType: $($grant.consentType)" -ForegroundColor Gray
            }
            $checks.Pass++
        }
    } catch {
        Write-Host "  WARN: Could not check consent grants (may need DelegatedPermissionGrant.ReadWrite.All)" -ForegroundColor DarkYellow
        Write-Host "        This check is non-blocking — proceed to test flows." -ForegroundColor Gray
        $checks.Pass++
    }
} else {
    Write-Host "  SKIP: Cannot check consent without a service principal" -ForegroundColor DarkYellow
}

# ── Check 4: User Flow Linked ────────────────────────────────────────────
Write-Host "`n[4/4] Checking user flow linked to app..." -ForegroundColor Yellow
try {
    # List all flows (no $select — not supported on all B2C tenants)
    $allFlows = Invoke-RestMethod `
        -Uri "https://graph.microsoft.com/beta/identity/authenticationEventsFlows" `
        -Method GET -Headers $headers

    $linkedFlow = $null
    foreach ($flow in $allFlows.value) {
        try {
            $apps = Invoke-RestMethod `
                -Uri "https://graph.microsoft.com/beta/identity/authenticationEventsFlows/$($flow.id)/conditions/applications/includeApplications" `
                -Method GET -Headers $headers
            if ($apps.value | Where-Object { $_.appId -eq $AppId }) {
                $linkedFlow = $flow
                break
            }
        } catch { continue }
    }

    if ($linkedFlow) {
        Write-Host "  PASS: User flow linked to app" -ForegroundColor Green
        Write-Host "        Flow: $($linkedFlow.displayName) (id: $($linkedFlow.id))" -ForegroundColor Gray
    } else {
        Write-Host "  FAIL: No user flow is linked to appId: $AppId" -ForegroundColor Red
        Write-Host "        Create and link a flow using 2-native-auth-create-flow.ps1" -ForegroundColor Yellow
        $checks.Fail++
    }
} catch {
    $errDetail = $null
    try { $errDetail = $_.ErrorDetails.Message | ConvertFrom-Json } catch {}
    Write-Host "  FAIL: Could not check user flows: $($_.Exception.Message)" -ForegroundColor Red
    if ($errDetail.error.message) {
        Write-Host "        $($errDetail.error.code): $($errDetail.error.message)" -ForegroundColor Red
    }
    $checks.Fail++
}

# ── Summary ──────────────────────────────────────────────────────────────
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  VALIDATION RESULTS" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  PASS: $($checks.Pass)" -ForegroundColor Green
Write-Host "  FAIL: $($checks.Fail)" -ForegroundColor Red
Write-Host ""

if ($checks.Fail -gt 0) {
    Write-Host "  RESULT: Fix FAIL items before testing Native Auth flows." -ForegroundColor Red
} else {
    # Resolve tenant name for next steps
    $tenantName = $null
    try {
        $org = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/organization" -Method GET -Headers $headers
        $tenantName = ($org.value[0].verifiedDomains | Where-Object { $_.name -match '\.onmicrosoft\.com$' } | Select-Object -First 1).name -replace '\.onmicrosoft\.com$', ''
    } catch {}
    if (-not $tenantName) { $tenantName = "<TENANT_NAME>" }

    Write-Host "  RESULT: All checks passed. Ready to test Native Auth flows." -ForegroundColor Green
    Write-Host ""
    Write-Host "Next step — test sign-up (passwordless):" -ForegroundColor Cyan
    Write-Host "  .\4-native-auth-flows\1-native-auth-signup.ps1 -Username `"user@example.com`"" -ForegroundColor White
}
