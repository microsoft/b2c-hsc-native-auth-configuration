# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
.SYNOPSIS
    Native Authentication Sign-up Flow
    
.DESCRIPTION
    Complete passwordless sign-up flow for Microsoft Entra External ID Native Authentication.
    Uses Email OTP for identity verification.
    
.PARAMETER TenantName
    Your B2C/External ID tenant subdomain (e.g., "contosob2c")
    
.PARAMETER ClientId
    Application (client) ID with native authentication enabled
    
.PARAMETER Email
    Email address for the new user
    
.PARAMETER DisplayName
    Optional display name for the user
    
.EXAMPLE
    .\native-auth-signup.ps1 -TenantName "contosob2c" -ClientId "12345..." -Email "user@example.com"
    
.NOTES
    Requirements:
    - PowerShell 5.1 or later (PowerShell 7+ recommended)
    - Application must have native authentication enabled
    - User flow must be configured and linked to the application
#>

param(
    [string]$TenantName = $env:HSC_TENANT_NAME,
    [string]$ClientId   = $env:HSC_NATIVE_APP_ID,

    [Parameter(Mandatory=$true)]
    [string]$Email,

    [string]$DisplayName = ""
)

if (-not $TenantName -or -not $ClientId) {
    Write-Host "ERROR: TenantName and ClientId are required." -ForegroundColor Red
    Write-Host "  Pass them as parameters or run register-app first (sets env vars automatically)." -ForegroundColor Yellow
    exit 1
}

# Import shared helpers
. "$PSScriptRoot\..\common\graph-helpers.ps1"

# Base URL for native authentication endpoints
$BaseUrl = "https://$TenantName.ciamlogin.com/$TenantName.onmicrosoft.com"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Native Authentication - Sign-up Flow" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Mode: Passwordless (Email OTP)" -ForegroundColor Magenta
Write-Host ""

try {
    # Step 1: Start Sign-up
    Write-Host "[Step 1/4] Starting sign-up flow..." -ForegroundColor Yellow
    
    $startBody = @{
        client_id = $ClientId
        username = $Email
        challenge_type = "oob redirect"
    }
    
    if ($DisplayName) {
        $attributes = @{
            displayName = $DisplayName
        } | ConvertTo-Json -Compress
        $startBody.attributes = $attributes
    }
    
    $startResponse = Invoke-RestMethod -Method Post `
        -Uri "$BaseUrl/signup/v1.0/start" `
        -ContentType "application/x-www-form-urlencoded" `
        -Body $startBody
    
    $continuationToken = $startResponse.continuation_token
    
    if (-not $continuationToken) {
        throw "Failed to get continuation token from start response"
    }
    
    Write-Host "✓ Sign-up initiated successfully" -ForegroundColor Green
    Write-Host "  Continuation token received`n" -ForegroundColor Gray
    
    # Step 2: Request OTP Challenge
    Write-Host "[Step 2/4] Requesting OTP..." -ForegroundColor Yellow
    
    $challengeBody = @{
        client_id = $ClientId
        continuation_token = $continuationToken
        challenge_type = "oob"
    }
    
    $challengeResponse = Invoke-RestMethod -Method Post `
        -Uri "$BaseUrl/signup/v1.0/challenge" `
        -ContentType "application/x-www-form-urlencoded" `
        -Body $challengeBody
    
    $continuationToken = $challengeResponse.continuation_token
    
    if ($challengeResponse.challenge_target_label) {
        Write-Host "✓ OTP sent to: $($challengeResponse.challenge_target_label)" -ForegroundColor Green
    } else {
        Write-Host "✓ OTP sent successfully" -ForegroundColor Green
    }
    
    # Step 3: Submit OTP Code
    Write-Host "`nPlease check your email for the OTP code." -ForegroundColor Cyan
    $otpCode = Read-Host "Enter the OTP code received"
    
    Write-Host "`n[Step 3/4] Submitting OTP..." -ForegroundColor Yellow
    
    $continueBody = @{
        client_id = $ClientId
        continuation_token = $continuationToken
        oob = $otpCode
        grant_type = "oob"
    }
    
    $continueResponse = Invoke-RestMethod -Method Post `
        -Uri "$BaseUrl/signup/v1.0/continue" `
        -ContentType "application/x-www-form-urlencoded" `
        -Body $continueBody
    
    $continuationToken = $continueResponse.continuation_token
    
    Write-Host "✓ OTP verified successfully" -ForegroundColor Green
    Write-Host "  User account created`n" -ForegroundColor Gray
    
    # Step 4: Get Tokens
    Write-Host "[Step 4/4] Requesting access tokens..." -ForegroundColor Yellow
    
    $tokenBody = @{
        client_id = $ClientId
        continuation_token = $continuationToken
        grant_type = "continuation_token"
        scope = "openid profile offline_access"
    }
    
    $tokenResponse = Invoke-RestMethod -Method Post `
        -Uri "$BaseUrl/oauth2/v2.0/token" `
        -ContentType "application/x-www-form-urlencoded" `
        -Body $tokenBody
    
    Write-Host "✓ Tokens received successfully!`n" -ForegroundColor Green
    
    # Display results
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Sign-up Completed Successfully!" -ForegroundColor Green
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    Show-TokenResult -TokenResponse $tokenResponse
    
    # Decode and display ID token claims
    if ($tokenResponse.id_token) {
        Decode-IdToken -IdToken $tokenResponse.id_token | Out-Null
    }
    
    # Return tokens as object for scripting scenarios
    return @{
        AccessToken = $tokenResponse.access_token
        RefreshToken = $tokenResponse.refresh_token
        IdToken = $tokenResponse.id_token
        ExpiresIn = $tokenResponse.expires_in
        TokenType = $tokenResponse.token_type
    }
    
} catch {
    Format-NativeAuthError -ErrorRecord $_ -Operation "Sign-up"
    throw
}
