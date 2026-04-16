# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
.SYNOPSIS
    Register a Native Auth app and optionally create + link a user flow.

.DESCRIPTION
    Creates an app registration with native authentication enabled,
    creates a service principal, and optionally creates a user flow
    and links it to the app.

.PARAMETER TenantId
    Your Azure AD B2C tenant ID (GUID).

.PARAMETER AccessToken
    Delegated access token (from 1-admin-setup.ps1).

.PARAMETER RefreshToken
    Refresh token for silent renewal.

.PARAMETER AppName
    Display name for the new Native Auth app registration.

.PARAMETER CreateFlow
    If specified, also creates a user flow and links it to the app.

.PARAMETER FlowName
    Display name for the user flow (default: "Native Auth Flow").

.EXAMPLE
    .\native-auth-register-app.ps1 -AppName "MyNativeApp"

.EXAMPLE
    .\native-auth-register-app.ps1 -AppName "MyNativeApp" -CreateFlow
#>

param(
    [string]$TenantId     = $env:HSC_TENANT_ID,
    [string]$AccessToken  = $env:HSC_ACCESS_TOKEN,
    [string]$RefreshToken = $env:HSC_REFRESH_TOKEN,
    [Parameter(Mandatory=$true)][string]$AppName,
    [switch]$CreateFlow,
    [string]$FlowName = "Native Auth Flow"
)

if (-not $TenantId -or -not $AccessToken -or -not $RefreshToken) {
    Write-Host "ERROR: TenantId, AccessToken, and RefreshToken are required." -ForegroundColor Red
    Write-Host "  Run 1-admin-setup.ps1 first (sets env vars automatically)." -ForegroundColor Yellow
    exit 1
}

$ErrorActionPreference = "Stop"

# Import shared helpers
. "$PSScriptRoot\..\common\graph-helpers.ps1"

# Get headers with auto-refresh
$headers = Get-GraphHeaders -TenantId $TenantId -AccessToken $AccessToken -RefreshToken $RefreshToken

# Step 1: Find or create the app registration
Write-Host "`nChecking for existing app: $AppName" -ForegroundColor Yellow
$appId = $null
$appObjectId = $null
try {
    $existingApp = Invoke-RestMethod `
        -Uri "https://graph.microsoft.com/v1.0/applications?`$filter=displayName eq '$AppName'&`$select=id,appId,displayName,nativeAuthenticationApisEnabled,isFallbackPublicClient" `
        -Method GET -Headers $headers
    if ($existingApp.value.Count -gt 0) {
        $app = $existingApp.value[0]
        $appId = $app.appId
        $appObjectId = $app.id
        Write-Host "App already exists:" -ForegroundColor Green
        Write-Host "  Display Name: $($app.displayName)" -ForegroundColor Gray
        Write-Host "  Application (client) ID: $appId" -ForegroundColor Gray
        Write-Host "  Object ID: $appObjectId" -ForegroundColor Gray
        Write-Host "  Native Auth: $($app.nativeAuthenticationApisEnabled)" -ForegroundColor Gray
        Write-Host "  Public Client: $($app.isFallbackPublicClient)" -ForegroundColor Gray
    }
} catch {
    Write-Host "  Could not search for existing app, will attempt to create." -ForegroundColor DarkYellow
}

if (-not $appId) {
    Write-Host "Creating app registration: $AppName" -ForegroundColor Yellow
    $appBody = @{
        displayName = $AppName
        signInAudience = "AzureADMyOrg"
        isFallbackPublicClient = $true
        nativeAuthenticationApisEnabled = "all"
        publicClient = @{
            redirectUris = @()
        }
        requiredResourceAccess = @(
            @{
                resourceAppId = "00000003-0000-0000-c000-000000000000"
                resourceAccess = @(
                    @{ id = "37f7f235-527c-4136-accd-4a02d197296e"; type = "Scope" }
                    @{ id = "7427e0e9-2fba-42fe-b0c0-848c9e6a8182"; type = "Scope" }
                )
            }
        )
    } | ConvertTo-Json -Depth 10

    try {
        $app = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/applications" -Method POST -Headers $headers -Body $appBody
        $appId = $app.appId
        $appObjectId = $app.id
        Write-Host "App created:" -ForegroundColor Green
        Write-Host "  Display Name: $($app.displayName)" -ForegroundColor Gray
        Write-Host "  Application (client) ID: $appId" -ForegroundColor Gray
        Write-Host "  Object ID: $appObjectId" -ForegroundColor Gray
        Write-Host "  Native Auth: $($app.nativeAuthenticationApisEnabled)" -ForegroundColor Gray
        Write-Host "  Public Client: $($app.isFallbackPublicClient)" -ForegroundColor Gray
    } catch {
        Write-Error "Failed to create app: $_"
        exit 1
    }
}

# Step 2: Find or create service principal (retry with backoff for new apps)
Write-Host "`nChecking for existing service principal..." -ForegroundColor Yellow
$sp = $null
try {
    $existingSp = Invoke-RestMethod `
        -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$appId'&`$select=id,appId,displayName" `
        -Method GET -Headers $headers
    if ($existingSp.value.Count -gt 0) {
        $sp = $existingSp.value[0]
        Write-Host "Service principal already exists (ID: $($sp.id))" -ForegroundColor Green
    }
} catch {
    Write-Host "  Could not search for existing SP, will attempt to create." -ForegroundColor DarkYellow
}

if (-not $sp) {
    Write-Host "Creating service principal..." -ForegroundColor Yellow
    $spBody = @{ appId = $appId } | ConvertTo-Json

    $maxRetries = 5
    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        try {
            $sp = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/servicePrincipals" -Method POST -Headers $headers -Body $spBody
            Write-Host "Service principal created (ID: $($sp.id))" -ForegroundColor Green
            break
        } catch {
            $errBody = $null
            try { $errBody = $_.ErrorDetails.Message | ConvertFrom-Json } catch {}
            $isReplicationError = ($errBody.error.code -eq 'Request_BadRequest' -and $errBody.error.details.code -contains 'NoBackingApplicationObject')

            if ($isReplicationError -and $attempt -lt $maxRetries) {
                $wait = $attempt * 5
                Write-Host "  App not yet replicated. Retrying in ${wait}s... (attempt $attempt/$maxRetries)" -ForegroundColor DarkYellow
                Start-Sleep -Seconds $wait
            } else {
                Write-Error "Failed to create service principal: $_"
                exit 1
            }
        }
    }
}

# Step 2b: Grant admin consent for delegated permissions (openid, offline_access)
Write-Host "`nGranting admin consent for delegated permissions..." -ForegroundColor Yellow
$graphSpId = $null
try {
    $graphSp = Invoke-RestMethod `
        -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '00000003-0000-0000-c000-000000000000'&`$select=id" `
        -Method GET -Headers $headers
    $graphSpId = $graphSp.value[0].id
} catch {
    Write-Host "  WARN: Could not find Microsoft Graph service principal." -ForegroundColor DarkYellow
}

if ($graphSpId -and $sp) {
    # Check if grant already exists
    $existingGrant = $null
    try {
        $grants = Invoke-RestMethod `
            -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($sp.id)/oauth2PermissionGrants" `
            -Method GET -Headers $headers
        $existingGrant = $grants.value | Where-Object { $_.resourceId -eq $graphSpId -and $_.consentType -eq 'AllPrincipals' }
    } catch {}

    if ($existingGrant) {
        Write-Host "Admin consent already granted (scope: $($existingGrant.scope))" -ForegroundColor Green
    } else {
        $grantBody = @{
            clientId    = $sp.id
            consentType = "AllPrincipals"
            resourceId  = $graphSpId
            scope       = "openid offline_access"
        } | ConvertTo-Json

        try {
            Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants" -Method POST -Headers $headers -Body $grantBody | Out-Null
            Write-Host "Admin consent granted (openid offline_access)" -ForegroundColor Green
        } catch {
            Write-Host "  WARN: Could not grant admin consent: $($_.Exception.Message)" -ForegroundColor DarkYellow
            Write-Host "        Grant consent manually in Azure Portal: App registrations > $AppName > API permissions > Grant admin consent" -ForegroundColor DarkYellow
        }
    }
}

# Step 3 (optional): Find or create user flow and link to app
if ($CreateFlow) {
    # Check if a flow with this name already exists
    Write-Host "`nChecking for existing user flow: $FlowName" -ForegroundColor Yellow
    $flowId = $null
    try {
        $allFlows = Invoke-RestMethod `
            -Uri "https://graph.microsoft.com/beta/identity/authenticationEventsFlows?`$select=id,displayName" `
            -Method GET -Headers $headers
        $match = $allFlows.value | Where-Object { $_.displayName -eq $FlowName }
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
        $flow = Invoke-RestMethod -Uri "https://graph.microsoft.com/beta/identity/authenticationEventsFlows" -Method POST -Headers $headers -Body $flowBody
        $flowId = $flow.id
        Write-Host "Flow created (ID: $flowId)" -ForegroundColor Green
    } catch {
        # Handle "displayName already in use" as idempotent success
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

    # Check if flow is already linked to the app
    Write-Host "`nChecking if flow is linked to application..." -ForegroundColor Yellow
    $alreadyLinked = $false
    try {
        $linkedApps = Invoke-RestMethod `
            -Uri "https://graph.microsoft.com/beta/identity/authenticationEventsFlows/$flowId/conditions/applications/includeApplications" `
            -Method GET -Headers $headers
        $alreadyLinked = ($linkedApps.value | Where-Object { $_.appId -eq $appId }).Count -gt 0
    } catch {
        # If we can't check, try linking anyway
    }

    if ($alreadyLinked) {
        Write-Host "Flow is already linked to application" -ForegroundColor Green
    } else {
        Write-Host "Linking flow to application..." -ForegroundColor Yellow
        $linkBody = @{
            "@odata.type" = "#microsoft.graph.authenticationConditionApplication"
            appId = $appId
        } | ConvertTo-Json

        try {
            Invoke-RestMethod -Uri "https://graph.microsoft.com/beta/identity/authenticationEventsFlows/$flowId/conditions/applications/includeApplications" -Method POST -Headers $headers -Body $linkBody | Out-Null
            Write-Host "Flow linked to application" -ForegroundColor Green
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
}

# Resolve tenant name for next steps
$tenantName = $null
try {
    $org = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/organization" -Method GET -Headers $headers
    $tenantName = ($org.value[0].verifiedDomains | Where-Object { $_.name -match '\.onmicrosoft\.com$' } | Select-Object -First 1).name -replace '\.onmicrosoft\.com$', ''
} catch {}
if (-not $tenantName) { $tenantName = "<TENANT_NAME>" }

# Summary
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  SETUP COMPLETE" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Native Auth App:" -ForegroundColor White
Write-Host "  NATIVE_APP_ID: $appId" -ForegroundColor Cyan
Write-Host "  Object ID:     $appObjectId" -ForegroundColor Gray
if ($CreateFlow) {
    Write-Host "  Flow ID:       $flowId" -ForegroundColor Gray
}

# Set environment variables for subsequent scripts in this session
$env:HSC_NATIVE_APP_ID = $appId
$env:HSC_TENANT_NAME   = $tenantName

Write-Host ""
Write-Host "Environment variables set for this session:" -ForegroundColor Green
Write-Host "  HSC_NATIVE_APP_ID, HSC_TENANT_NAME" -ForegroundColor Gray
Write-Host "  Subsequent scripts will use these automatically — no need to pass them as parameters." -ForegroundColor Gray

if (-not $CreateFlow) {
    Write-Host ""
    Write-Host "Next step — create a user flow and link it to the app:" -ForegroundColor Cyan
    Write-Host "  .\3-native-auth-setup\2-native-auth-create-flow.ps1" -ForegroundColor White
} else {
    Write-Host ""
    Write-Host "Next step — validate the setup:" -ForegroundColor Cyan
    Write-Host "  .\3-native-auth-setup\3-native-auth-validate.ps1" -ForegroundColor White
    Write-Host ""
    Write-Host "Then test sign-up:" -ForegroundColor Cyan
    Write-Host "  .\4-native-auth-flows\1-native-auth-signup.ps1 -Username `"user@example.com`"" -ForegroundColor White
}
Write-Host ""
