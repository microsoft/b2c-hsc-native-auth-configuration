# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
.SYNOPSIS
    Native Authentication Sign-in Flow
    
.DESCRIPTION
    Complete sign-in flow for Microsoft Entra External ID Native Authentication.
    Supports password and OTP-based authentication.
    Demonstrates proper continuation token handling.
    
.PARAMETER TenantName
    Your B2C/External ID tenant subdomain (e.g., "contosob2c")
    
.PARAMETER ClientId
    Application (client) ID with native authentication enabled
    
.PARAMETER Username
    Email address or username for authentication
    
.PARAMETER Password
    User password for authentication
    
.PARAMETER UseOTP
    Use OTP instead of password for authentication
    
.EXAMPLE
    .\native-auth-signin.ps1 -TenantName "contosob2c" -ClientId "12345678-1234-1234-1234-123456789012" -Username "user@example.com" -Password "SecureP@ss123!"
    
.EXAMPLE
    .\native-auth-signin.ps1 -TenantName "contosob2c" -ClientId "12345678-1234-1234-1234-123456789012" -Username "user@example.com" -UseOTP
    
.NOTES
    Requirements:
    - PowerShell 5.1 or later (PowerShell 7+ recommended)
    - Application must have native authentication enabled
    - User must already be registered
    - User flow must be configured and linked to the application
#>

param(
    [string]$TenantName = $env:HSC_TENANT_NAME,
    [string]$ClientId   = $env:HSC_NATIVE_APP_ID,

    [Parameter(Mandatory=$true)]
    [string]$Username,

    [string]$Password,
    [switch]$UseOTP
)

if (-not $TenantName -or -not $ClientId) {
    Write-Host "ERROR: TenantName and ClientId are required." -ForegroundColor Red
    Write-Host "  Pass them as parameters or run register-app first (sets env vars automatically)." -ForegroundColor Yellow
    exit 1
}

# Validate parameters
if (-not $UseOTP -and -not $Password) {
    throw "Either -Password or -UseOTP must be specified"
}

# Import shared helpers
. "$PSScriptRoot\..\common\graph-helpers.ps1"

# Base URL for native authentication endpoints
$BaseUrl = "https://$TenantName.ciamlogin.com/$TenantName.onmicrosoft.com"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Native Authentication - Sign-in Flow" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

try {
    # Step 1: Initiate Sign-in
    Write-Host "[Step 1/3] Initiating sign-in..." -ForegroundColor Yellow
    
    $initiateBody = @{
        client_id = $ClientId
        username = $Username
        challenge_type = "oob password redirect"
    }
    
    $initiateResponse = Invoke-RestMethod -Method Post `
        -Uri "$BaseUrl/oauth2/v2.0/initiate" `
        -ContentType "application/x-www-form-urlencoded" `
        -Body $initiateBody
    
    $continuationToken = $initiateResponse.continuation_token
    
    if (-not $continuationToken) {
        throw "Failed to get continuation token from initiate response"
    }
    
    Write-Host "✓ Sign-in initiated successfully" -ForegroundColor Green
    Write-Host "  User found: $Username`n" -ForegroundColor Gray
    
    # Step 2: Challenge (Password or OTP)
    if ($UseOTP) {
        Write-Host "[Step 2/3] Requesting OTP..." -ForegroundColor Yellow
        
        $challengeBody = @{
            client_id = $ClientId
            continuation_token = $continuationToken
            challenge_type = "oob redirect"
        }
        
        $challengeResponse = Invoke-RestMethod -Method Post `
            -Uri "$BaseUrl/oauth2/v2.0/challenge" `
            -ContentType "application/x-www-form-urlencoded" `
            -Body $challengeBody
        
        $continuationToken = $challengeResponse.continuation_token
        
        if ($challengeResponse.challenge_target_label) {
            Write-Host "✓ OTP sent to: $($challengeResponse.challenge_target_label)" -ForegroundColor Green
        } else {
            Write-Host "✓ OTP sent successfully" -ForegroundColor Green
        }
        
        # Prompt for OTP
        Write-Host "`nPlease check your email for the OTP code." -ForegroundColor Cyan
        $otpCode = Read-Host "Enter the OTP code received"
        
        # For OTP sign-in, submit OTP at token endpoint with grant_type=oob
        Write-Host "`n[Step 3/3] Submitting OTP and requesting tokens..." -ForegroundColor Yellow
        
        $tokenBody = @{
            client_id = $ClientId
            continuation_token = $continuationToken
            grant_type = "oob"
            oob = $otpCode
            scope = "openid profile offline_access"
        }
        
    } else {
        # Password flow: /challenge only requests the challenge type.
        # The actual password is submitted at /token with grant_type=password.
        Write-Host "[Step 2/3] Requesting password challenge..." -ForegroundColor Yellow
        
        $challengeBody = @{
            client_id = $ClientId
            continuation_token = $continuationToken
            challenge_type = "password redirect"
        }
        
        $challengeResponse = Invoke-RestMethod -Method Post `
            -Uri "$BaseUrl/oauth2/v2.0/challenge" `
            -ContentType "application/x-www-form-urlencoded" `
            -Body $challengeBody
        
        $continuationToken = $challengeResponse.continuation_token
        
        Write-Host "✓ Password challenge accepted`n" -ForegroundColor Green
        
        # Step 3: Submit password at /token endpoint
        Write-Host "[Step 3/3] Submitting password and requesting tokens..." -ForegroundColor Yellow
        
        $tokenBody = @{
            client_id = $ClientId
            continuation_token = $continuationToken
            grant_type = "password"
            password = $Password
            scope = "openid profile offline_access"
        }
    }
    
    $tokenResponse = Invoke-RestMethod -Method Post `
        -Uri "$BaseUrl/oauth2/v2.0/token" `
        -ContentType "application/x-www-form-urlencoded" `
        -Body $tokenBody
    
    Write-Host "✓ Tokens received successfully!`n" -ForegroundColor Green
    
    # Display results
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Sign-in Completed Successfully!" -ForegroundColor Green
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    Show-TokenResult -TokenResponse $tokenResponse
    
    # Decode and display ID token claims
    if ($tokenResponse.id_token) {
        Decode-IdToken -IdToken $tokenResponse.id_token | Out-Null
    }
    
    Write-Host "Next Steps:" -ForegroundColor Cyan
    Write-Host "  - Use access_token to call protected APIs" -ForegroundColor Gray
    Write-Host "  - Use refresh_token to get new tokens when expired" -ForegroundColor Gray
    Write-Host "  - Tokens can be inspected at https://jwt.ms`n" -ForegroundColor Gray
    
    # Return tokens as object for scripting scenarios
    return @{
        AccessToken = $tokenResponse.access_token
        RefreshToken = $tokenResponse.refresh_token
        IdToken = $tokenResponse.id_token
        ExpiresIn = $tokenResponse.expires_in
        TokenType = $tokenResponse.token_type
    }
    
} catch {
    Format-NativeAuthError -ErrorRecord $_ -Operation "Sign-in"
    throw
}
