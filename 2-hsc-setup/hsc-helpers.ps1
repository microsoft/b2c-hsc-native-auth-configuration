# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

# Shared helpers for HSC setup scripts

$script:hscEndpoint = "https://graph.microsoft.com/beta/policies/authenticationFlowsPolicy/externalIdHybridModeConfiguration"
$script:emailOtpEndpoint = "https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/email"

function Get-HscHeaders {
    param(
        [string]$TenantId     = $env:HSC_TENANT_ID,
        [string]$AccessToken  = $env:HSC_ACCESS_TOKEN,
        [string]$RefreshToken = $env:HSC_REFRESH_TOKEN
    )
    Write-Host "Getting access token..." -ForegroundColor Cyan
    return Get-GraphHeaders -TenantId $TenantId -AccessToken $AccessToken -RefreshToken $RefreshToken
}

function Format-HscError {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord, [string]$Operation)

    $msg = $ErrorRecord.Exception.Message
    $statusCode = $null
    $errorCode = $null
    $errorMessage = $null

    if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
        try {
            $errorJson = $ErrorRecord.ErrorDetails.Message | ConvertFrom-Json
            $errorCode = $errorJson.error.code
            $errorMessage = $errorJson.error.message
        } catch {}
    }

    try { $statusCode = [int]$ErrorRecord.Exception.Response.StatusCode } catch {}

    Write-Host "`nFailed to $Operation" -ForegroundColor Red
    if ($errorCode) { Write-Host "  Error code: $errorCode" -ForegroundColor Red }
    if ($errorMessage) { Write-Host "  Message: $errorMessage" -ForegroundColor Red }

    if ($statusCode -eq 403 -or $errorCode -eq 'Authorization_RequestDenied') {
        Write-Host "`n  FIX: Verify the app has Policy.ReadWrite.AuthenticationFlows permission" -ForegroundColor Yellow
        Write-Host "       and admin consent has been granted." -ForegroundColor Yellow
    }
    elseif ($errorCode -eq 'AccessDenied_NonB2CTenantNotAllowed' -or ($errorMessage -and $errorMessage -match 'is not an Azure AD B2C directory')) {
        Write-Host "`n  FIX: The HSC API must be called against a B2C tenant. Verify your TenantId." -ForegroundColor Yellow
    }
    elseif ($errorCode -eq 'HybridUpgradeNotAllowed' -or ($errorMessage -and $errorMessage -match 'Hybrid Upgrade is not allowed')) {
        Write-Host "`n  FIX: The parent workforce tenant doesn't have the EnableHybridUpgradeApi flag." -ForegroundColor Yellow
        Write-Host "       Contact Microsoft Support and request allowlisting." -ForegroundColor Yellow
    }
    elseif ($errorCode -eq 'AADB2C99089' -or ($errorMessage -and $errorMessage -match 'Failed to sync custom attributes')) {
        Write-Host "`n  FIX: Some B2C custom attributes have empty descriptions." -ForegroundColor Yellow
        Write-Host "       Run .\2-hsc-setup\1-hsc-preflight-check.ps1 to find and fix them." -ForegroundColor Yellow
    }
    elseif ($errorCode -eq 'NoResourceProviderDataFound' -or ($errorMessage -and $errorMessage -match 'not linked to a valid subscription')) {
        Write-Host "`n  FIX: The B2C tenant is not linked to an Azure subscription." -ForegroundColor Yellow
        Write-Host "       Link it via Azure portal: Azure AD B2C > Overview > Subscription." -ForegroundColor Yellow
    }
    elseif ($errorCode -eq 'AccessDenied_NonHybridTenantNotAllowed' -or ($errorMessage -and $errorMessage -match 'Hybrid mode enabled')) {
        Write-Host "`n  FIX: Cannot disable HSC on a tenant that isn't in hybrid mode." -ForegroundColor Yellow
    }
    else {
        Write-Host "`n  Run .\2-hsc-setup\1-hsc-preflight-check.ps1 to diagnose common issues." -ForegroundColor Yellow
    }
}
