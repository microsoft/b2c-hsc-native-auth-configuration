# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
.SYNOPSIS
    Create a Native Auth user flow and link it to an application.

.DESCRIPTION
    Creates a sign-up/sign-in user flow with email OTP and password,
    then links it to the specified application.

.PARAMETER TenantId
    Your Azure AD B2C tenant ID (GUID).

.PARAMETER AccessToken
    Delegated access token (from 1-admin-setup.ps1).

.PARAMETER RefreshToken
    Refresh token for silent renewal.

.PARAMETER AppId
    Native Auth application (client) ID to link the flow to.

.PARAMETER FlowName
    Display name for the user flow (default: "Native Auth Flow").

.EXAMPLE
    .\native-auth-create-flow.ps1 -AppId "native-app-id"
#>

param(
    [string]$TenantId     = $env:HSC_TENANT_ID,
    [string]$AccessToken  = $env:HSC_ACCESS_TOKEN,
    [string]$RefreshToken = $env:HSC_REFRESH_TOKEN,
    [string]$AppId        = $env:HSC_NATIVE_APP_ID,
    [string]$FlowName     = "Native Auth Flow"
)

if (-not $TenantId -or -not $AccessToken -or -not $RefreshToken -or -not $AppId) {
    Write-Host "ERROR: TenantId, AccessToken, RefreshToken, and AppId are required." -ForegroundColor Red
    Write-Host "  Run the previous scripts first (sets env vars automatically)." -ForegroundColor Yellow
    exit 1
}

$ErrorActionPreference = "Stop"

# Import shared helpers
. "$PSScriptRoot\..\common\graph-helpers.ps1"

# Note: Flow creation requires /beta (externalUsersSelfServiceSignUpEventsFlow is beta-only).
# Flow linking uses /v1.0 (includeApplications endpoint is GA).
$graphUrl = "https://graph.microsoft.com/beta"

# Get headers with auto-refresh
$headers = Get-GraphHeaders -TenantId $TenantId -AccessToken $AccessToken -RefreshToken $RefreshToken

# Step 1: Find or create the user flow
Write-Host "`nChecking for existing user flow: $FlowName" -ForegroundColor Yellow
$flowId = $null
try {
    $existingFlows = Invoke-RestMethod `
        -Uri "$graphUrl/identity/authenticationEventsFlows?`$select=id,displayName" `
        -Method GET -Headers $headers
    $match = $existingFlows.value | Where-Object { $_.displayName -eq $FlowName }
    if ($match) {
        $flowId = $match[0].id
        Write-Host "Flow already exists (ID: $flowId)" -ForegroundColor Green
    }
} catch {
    Write-Host "  Could not search for existing flows, will attempt to create." -ForegroundColor DarkYellow
}

if (-not $flowId) {
    Write-Host "Creating user flow: $FlowName" -ForegroundColor Yellow
    $flowBody = @{
    "@odata.type" = "#microsoft.graph.externalUsersSelfServiceSignUpEventsFlow"
    displayName = $FlowName
    onAuthenticationMethodLoadStart = @{
        "@odata.type" = "#microsoft.graph.onAuthenticationMethodLoadStartExternalUsersSelfServiceSignUp"
        identityProviders = @(
            @{ id = "EmailOtpSignup-OAUTH" }
            @{ id = "EmailPassword-OAUTH" }
        )
    }
    onInteractiveAuthFlowStart = @{
        "@odata.type" = "#microsoft.graph.onInteractiveAuthFlowStartExternalUsersSelfServiceSignUp"
        isSignUpAllowed = $true
    }
    onAttributeCollection = @{
        "@odata.type" = "#microsoft.graph.onAttributeCollectionExternalUsersSelfServiceSignUp"
        attributes = @(
            @{ id = "email" }
            @{ id = "displayName" }
        )
        attributeCollectionPage = @{
            views = @(@{
                inputs = @(
                    @{ attribute = "email"; label = "Email"; required = $true }
                    @{ attribute = "displayName"; label = "Display Name"; required = $true }
                )
            })
        }
    }
} | ConvertTo-Json -Depth 10

try {
    $flow = Invoke-RestMethod -Uri "$graphUrl/identity/authenticationEventsFlows" -Method POST -Headers $headers -Body $flowBody
    $flowId = $flow.id
    Write-Host "Created flow with ID: $flowId" -ForegroundColor Green
} catch {
    $errBody = $null
    try { $errBody = $_.ErrorDetails.Message | ConvertFrom-Json } catch {}
    if ($errBody.error.message -match "displayName is in use by AuthenticationEventsFlow with id '([^']+)'") {
        $flowId = $Matches[1]
        Write-Host "Flow already exists (ID: $flowId)" -ForegroundColor Green
    } else {
        Write-Error "Failed to create flow: $_"
        exit 1
    }
}
}

# Step 2: Check if already linked, then link the flow to the application (v1.0 — this endpoint is GA)
Write-Host "`nChecking if flow is linked to application: $AppId" -ForegroundColor Yellow
$alreadyLinked = $false
try {
    $linkedApps = Invoke-RestMethod `
        -Uri "https://graph.microsoft.com/beta/identity/authenticationEventsFlows/$flowId/conditions/applications/includeApplications" `
        -Method GET -Headers $headers
    $alreadyLinked = ($linkedApps.value | Where-Object { $_.appId -eq $AppId }).Count -gt 0
} catch {
    # If we can't check, try linking anyway
}

if ($alreadyLinked) {
    Write-Host "Flow is already linked to application" -ForegroundColor Green
} else {
    Write-Host "Linking flow to application..." -ForegroundColor Yellow
    $linkBody = @{
        "@odata.type" = "#microsoft.graph.authenticationConditionApplication"
        appId = $AppId
    } | ConvertTo-Json

    try {
        Invoke-RestMethod -Uri "https://graph.microsoft.com/beta/identity/authenticationEventsFlows/$flowId/conditions/applications/includeApplications" -Method POST -Headers $headers -Body $linkBody | Out-Null
        Write-Host "Successfully linked flow to application" -ForegroundColor Green
    } catch {
        $errBody = $null
        try { $errBody = $_.ErrorDetails.Message | ConvertFrom-Json } catch {}
        if ($errBody.error.message -match 'already exists') {
            Write-Host "Flow is already linked to application" -ForegroundColor Green
        } else {
            Write-Error "Failed to link flow: $_"
            exit 1
        }
    }
}

Write-Host "`nDone! User flow created and linked to your app." -ForegroundColor Green
Write-Host "Flow ID: $flowId" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next step — validate the setup:" -ForegroundColor Cyan
Write-Host "  .\3-native-auth-setup\3-native-auth-validate.ps1" -ForegroundColor White
Write-Host ""
