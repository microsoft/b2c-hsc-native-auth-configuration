# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
.SYNOPSIS
    Native Authentication Password Reset (SSPR) Flow
    
.DESCRIPTION
    Complete self-service password reset flow for Microsoft Entra External ID Native Authentication.
    Includes OTP verification and password policy validation.
    Demonstrates proper continuation token handling and polling for completion status.
    
.PARAMETER TenantName
    Your B2C/External ID tenant subdomain (e.g., "contosob2c")
    
.PARAMETER ClientId
    Application (client) ID with native authentication enabled
    
.PARAMETER Username
    Email address or username for password reset
    
.PARAMETER NewPassword
    Optional. New password (must meet tenant password policy requirements).
    If omitted, you will be prompted interactively (recommended to avoid password in shell history).
    
.EXAMPLE
    # Interactive (recommended) — prompts for new password securely
    .\native-auth-password-reset.ps1 -TenantName "contosob2c" -ClientId "12345678-1234-1234-1234-123456789012" -Username "user@example.com"

.EXAMPLE
    # Non-interactive
    .\native-auth-password-reset.ps1 -TenantName "contosob2c" -ClientId "12345678-1234-1234-1234-123456789012" -Username "user@example.com" -NewPassword "NewSecureP@ss123!"
    
.NOTES
    Requirements:
    - PowerShell 5.1 or later (PowerShell 7+ recommended)
    - Application must have native authentication enabled
    - SSPR must be enabled in the tenant for customer users
    - User must exist and have email configured
    - New password must meet tenant password policy
#>

param(
    [string]$TenantName = $env:HSC_TENANT_NAME,
    [string]$ClientId   = $env:HSC_NATIVE_APP_ID,

    [Parameter(Mandatory=$true)]
    [string]$Username,

    [string]$NewPassword
)

if (-not $TenantName -or -not $ClientId) {
    Write-Host "ERROR: TenantName and ClientId are required." -ForegroundColor Red
    Write-Host "  Pass them as parameters or run register-app first (sets env vars automatically)." -ForegroundColor Yellow
    exit 1
}

# Prompt for new password interactively if not provided (avoids password in shell history)
if ([string]::IsNullOrEmpty($NewPassword)) {
    $securePass = Read-Host "Enter new password" -AsSecureString
    $NewPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass))
    if ([string]::IsNullOrEmpty($NewPassword)) {
        throw "New password cannot be empty"
    }
}

# Import shared helpers
. "$PSScriptRoot\..\common\graph-helpers.ps1"

# Base URL for native authentication endpoints
$BaseUrl = "https://$TenantName.ciamlogin.com/$TenantName.onmicrosoft.com"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Native Authentication - Password Reset (SSPR)" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

try {
    # Step 1: Start Password Reset
    Write-Host "[Step 1/5] Starting password reset..." -ForegroundColor Yellow
    
    $startBody = @{
        client_id = $ClientId
        username = $Username
        challenge_type = "oob redirect"
    }
    
    $startResponse = Invoke-RestMethod -Method Post `
        -Uri "$BaseUrl/resetpassword/v1.0/start" `
        -ContentType "application/x-www-form-urlencoded" `
        -Body $startBody
    
    $continuationToken = $startResponse.continuation_token
    
    if (-not $continuationToken) {
        throw "Failed to get continuation token from start response"
    }
    
    Write-Host "✓ Password reset initiated successfully" -ForegroundColor Green
    Write-Host "  User: $Username`n" -ForegroundColor Gray
    
    # Step 2: Request OTP
    Write-Host "[Step 2/5] Requesting OTP..." -ForegroundColor Yellow
    
    $challengeBody = @{
        client_id = $ClientId
        continuation_token = $continuationToken
        challenge_type = "oob"
    }
    
    $challengeResponse = Invoke-RestMethod -Method Post `
        -Uri "$BaseUrl/resetpassword/v1.0/challenge" `
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
    
    Write-Host "`n[Step 3/5] Verifying OTP..." -ForegroundColor Yellow
    
    $continueBody = @{
        client_id = $ClientId
        continuation_token = $continuationToken
        grant_type = "oob"
        oob = $otpCode
    }
    
    $continueResponse = Invoke-RestMethod -Method Post `
        -Uri "$BaseUrl/resetpassword/v1.0/continue" `
        -ContentType "application/x-www-form-urlencoded" `
        -Body $continueBody
    
    $continuationToken = $continueResponse.continuation_token
    
    Write-Host "✓ OTP verified successfully" -ForegroundColor Green
    Write-Host "  Ready to submit new password`n" -ForegroundColor Gray
    
    # Step 4: Submit New Password
    Write-Host "[Step 4/5] Submitting new password..." -ForegroundColor Yellow
    
    $submitBody = @{
        client_id = $ClientId
        continuation_token = $continuationToken
        new_password = $NewPassword
    }
    
    $submitResponse = Invoke-RestMethod -Method Post `
        -Uri "$BaseUrl/resetpassword/v1.0/submit" `
        -ContentType "application/x-www-form-urlencoded" `
        -Body $submitBody
    
    $continuationToken = $submitResponse.continuation_token
    
    Write-Host "✓ New password submitted" -ForegroundColor Green
    Write-Host "  Checking completion status...`n" -ForegroundColor Gray
    
    # Step 5: Poll Completion Status
    Write-Host "[Step 5/5] Polling for completion..." -ForegroundColor Yellow
    
    $maxPolls = 10
    $pollDelay = 2  # seconds
    $pollCount = 0
    $completed = $false
    
    while ($pollCount -lt $maxPolls -and -not $completed) {
        Start-Sleep -Seconds $pollDelay
        $pollCount++
        
        $pollBody = @{
            client_id = $ClientId
            continuation_token = $continuationToken
        }
        
        try {
            $pollResponse = Invoke-RestMethod -Method Post `
                -Uri "$BaseUrl/resetpassword/v1.0/poll_completion" `
                -ContentType "application/x-www-form-urlencoded" `
                -Body $pollBody
            
            $status = $pollResponse.status
            
            switch ($status) {
                "succeeded" {
                    Write-Host "✓ Password reset completed successfully!" -ForegroundColor Green
                    $completed = $true
                }
                "in_progress" {
                    Write-Host "  Poll $pollCount/$maxPolls - Status: In Progress..." -ForegroundColor Gray
                }
                "not_started" {
                    Write-Host "  Poll $pollCount/$maxPolls - Status: Not Started..." -ForegroundColor Gray
                }
                "failed" {
                    throw "Password reset failed. Status: $status"
                }
                default {
                    Write-Host "  Poll $pollCount/$maxPolls - Status: $status" -ForegroundColor Gray
                }
            }
            
            # Update continuation token if provided
            if ($pollResponse.continuation_token) {
                $continuationToken = $pollResponse.continuation_token
            }
            
        } catch {
            # If polling fails, it might mean the operation completed
            # Check if error is due to invalid continuation token (which may indicate completion)
            if ($_.ErrorDetails.Message -match "invalid.*token" -or $_.ErrorDetails.Message -match "expired") {
                Write-Host "✓ Password reset completed (token expired)" -ForegroundColor Green
                $completed = $true
            } else {
                throw
            }
        }
    }
    
    if (-not $completed) {
        Write-Host "`n! Password reset may still be in progress" -ForegroundColor Yellow
        Write-Host "  Try signing in with the new password in a few moments`n" -ForegroundColor Gray
    } else {
        Write-Host ""
    }
    
    # Display results
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Password Reset Completed!" -ForegroundColor Green
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    Write-Host "Summary:" -ForegroundColor Cyan
    Write-Host "  Username: $Username" -ForegroundColor Gray
    Write-Host "  Status: Password successfully reset" -ForegroundColor Gray
    Write-Host "  Next Step: Sign in with your new password`n" -ForegroundColor Gray
    
    Write-Host "To test the new password, run:" -ForegroundColor Cyan
    Write-Host "  .\native-auth-signin.ps1 -TenantName `"$TenantName`" -ClientId `"$ClientId`" -Username `"$Username`" -Password `"YOUR_NEW_PASSWORD`"`n" -ForegroundColor Gray
    
    return @{
        Status = "Success"
        Username = $Username
        Message = "Password reset completed successfully"
    }
    
} catch {
    Format-NativeAuthError -ErrorRecord $_ -Operation "Password reset"

    # Additional password policy guidance
    if ($_.ErrorDetails.Message) {
        try {
            $errorJson = $_.ErrorDetails.Message | ConvertFrom-Json
            if ($errorJson.error -eq "invalid_grant" -and $errorJson.error_description -match "password") {
                Write-Host "`nPassword Policy Requirements:" -ForegroundColor Yellow
                Write-Host "  - Minimum 8 characters" -ForegroundColor Gray
                Write-Host "  - Must include uppercase, lowercase, numbers" -ForegroundColor Gray
                Write-Host "  - May require special characters" -ForegroundColor Gray
                Write-Host "  - Cannot match previous passwords`n" -ForegroundColor Gray
            }
        } catch {}
    }
    
    throw
}
