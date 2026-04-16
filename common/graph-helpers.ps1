# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

<#
.SYNOPSIS
    Shared helper functions for Graph API operations and token handling.

.DESCRIPTION
    Dot-source this file from any script that needs Graph API authentication,
    pagination, JWT decoding, or API error formatting.

    Uses delegated auth (device code flow + refresh token) — no app registration
    or client secret needed. The signed-in user's permissions are used for all
    Graph API calls.

.EXAMPLE
    . "$PSScriptRoot\..\common\graph-helpers.ps1"
#>

# Well-known public client ID for Microsoft Graph CLI (device code flow)
$script:GraphPublicClientId = "14d82eec-204b-4c2f-b7e8-296a70dab67e"

# All delegated scopes needed across every script in this repo
$script:GraphDelegatedScopes = @(
    "https://graph.microsoft.com/Policy.ReadWrite.AuthenticationFlows"
    "https://graph.microsoft.com/Policy.ReadWrite.AuthenticationMethod"
    "https://graph.microsoft.com/Application.ReadWrite.All"
    "https://graph.microsoft.com/EventListener.ReadWrite.All"
    "https://graph.microsoft.com/IdentityUserFlow.ReadWrite.All"
    "https://graph.microsoft.com/DelegatedPermissionGrant.ReadWrite.All"
    "https://graph.microsoft.com/Directory.ReadWrite.All"
    "https://graph.microsoft.com/User.Read.All"
    "offline_access"
    "openid"
) -join " "

function Get-DelegatedToken {
    <#
    .SYNOPSIS
        Authenticate via device code flow and return access + refresh tokens.
    #>
    param(
        [Parameter(Mandatory)][string]$TenantId
    )

    $deviceCodeUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/devicecode"
    $deviceCodeBody = @{
        client_id = $script:GraphPublicClientId
        scope     = $script:GraphDelegatedScopes
    }

    try {
        $deviceCodeResponse = Invoke-RestMethod -Uri $deviceCodeUrl -Method POST -Body $deviceCodeBody -ContentType "application/x-www-form-urlencoded"
    } catch {
        Write-Error "Failed to initiate device code flow: $_"
        exit 1
    }

    Write-Host "  $($deviceCodeResponse.message)" -ForegroundColor Cyan
    Write-Host ""

    $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $pollBody = @{
        client_id   = $script:GraphPublicClientId
        grant_type  = "urn:ietf:params:oauth:grant-type:device_code"
        device_code = $deviceCodeResponse.device_code
    }

    $token = $null
    $maxWait = $deviceCodeResponse.expires_in
    $interval = $deviceCodeResponse.interval
    if (-not $interval -or $interval -lt 1) { $interval = 5 }
    $elapsed = 0

    while (-not $token -and $elapsed -lt $maxWait) {
        Start-Sleep -Seconds $interval
        $elapsed += $interval

        try {
            $tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method POST -Body $pollBody -ContentType "application/x-www-form-urlencoded"
            $token = $tokenResponse
        } catch {
            $errorBody = $null
            if ($_.ErrorDetails.Message) {
                try { $errorBody = $_.ErrorDetails.Message | ConvertFrom-Json } catch {}
            }

            if ($errorBody.error -eq "authorization_pending") {
                continue
            } elseif ($errorBody.error -eq "slow_down") {
                $interval += 5
                continue
            } elseif ($errorBody.error -eq "authorization_declined") {
                Write-Error "User declined the authorization request."
                exit 1
            } elseif ($errorBody.error -eq "expired_token") {
                Write-Error "Device code expired. Please run the script again."
                exit 1
            } else {
                Write-Error "Token polling failed: $($errorBody.error_description ?? $_.Exception.Message)"
                exit 1
            }
        }
    }

    if (-not $token) {
        Write-Error "Timed out waiting for device code authentication."
        exit 1
    }

    return @{
        access_token  = $token.access_token
        refresh_token = $token.refresh_token
        expires_on    = (Get-Date).AddSeconds($token.expires_in)
    }
}

function Refresh-GraphToken {
    <#
    .SYNOPSIS
        Silently refresh an access token using a refresh token.
    #>
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$RefreshToken
    )

    $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $body = @{
        client_id     = $script:GraphPublicClientId
        grant_type    = "refresh_token"
        refresh_token = $RefreshToken
        scope         = $script:GraphDelegatedScopes
    }

    try {
        $response = Invoke-RestMethod -Uri $tokenUrl -Method POST -Body $body -ContentType "application/x-www-form-urlencoded"
        return @{
            access_token  = $response.access_token
            refresh_token = $response.refresh_token
            expires_on    = (Get-Date).AddSeconds($response.expires_in)
        }
    } catch {
        Write-Error "Failed to refresh token. Please re-run 1-admin-setup.ps1 to re-authenticate."
        exit 1
    }
}

function Get-GraphHeaders {
    <#
    .SYNOPSIS
        Return Bearer auth headers, auto-refreshing the token if expired.
    .DESCRIPTION
        Reads HSC_ACCESS_TOKEN / HSC_REFRESH_TOKEN from env vars (or params),
        checks JWT expiry, refreshes if needed, and updates env vars.
    #>
    param(
        [string]$TenantId     = $env:HSC_TENANT_ID,
        [string]$AccessToken  = $env:HSC_ACCESS_TOKEN,
        [string]$RefreshToken = $env:HSC_REFRESH_TOKEN
    )

    if (-not $TenantId -or -not $AccessToken -or -not $RefreshToken) {
        Write-Host "ERROR: TenantId, AccessToken, and RefreshToken are required." -ForegroundColor Red
        Write-Host "  Run 1-admin-setup.ps1 first to authenticate." -ForegroundColor Yellow
        exit 1
    }

    # Decode JWT to check expiry
    $needsRefresh = $false
    try {
        $parts = $AccessToken.Split('.')
        $payload = $parts[1]
        while ($payload.Length % 4 -ne 0) { $payload += "=" }
        $json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($payload))
        $claims = $json | ConvertFrom-Json
        $exp = [DateTimeOffset]::FromUnixTimeSeconds($claims.exp).LocalDateTime
        # Refresh if less than 5 minutes remaining
        if ($exp -lt (Get-Date).AddMinutes(5)) {
            $needsRefresh = $true
        }
    } catch {
        $needsRefresh = $true
    }

    if ($needsRefresh) {
        Write-Host "Token expired or expiring soon, refreshing..." -ForegroundColor Yellow
        $refreshed = Refresh-GraphToken -TenantId $TenantId -RefreshToken $RefreshToken
        $AccessToken = $refreshed.access_token
        $env:HSC_ACCESS_TOKEN  = $refreshed.access_token
        $env:HSC_REFRESH_TOKEN = $refreshed.refresh_token
        Write-Host "Token refreshed." -ForegroundColor Green
    }

    return @{ "Authorization" = "Bearer $AccessToken"; "Content-Type" = "application/json" }
}

function Get-AllGraphPages {
    <#
    .SYNOPSIS
        Follow @odata.nextLink to retrieve all pages from a Graph API endpoint.
    #>
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][hashtable]$Headers
    )

    $results = @()
    $nextLink = $Uri
    while ($nextLink) {
        $response = Invoke-RestMethod -Uri $nextLink -Method GET -Headers $Headers
        if ($response.value) { $results += $response.value }
        $nextLink = $response.'@odata.nextLink'
    }
    return $results
}

function Decode-IdToken {
    <#
    .SYNOPSIS
        Decode a JWT id_token and display user claims.
    #>
    param(
        [Parameter(Mandatory)][string]$IdToken
    )

    try {
        $tokenParts = $IdToken.Split('.')
        $payload = $tokenParts[1]
        while ($payload.Length % 4 -ne 0) {
            $payload += "="
        }
        $payloadJson = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($payload))
        $claims = $payloadJson | ConvertFrom-Json

        Write-Host "User Claims:" -ForegroundColor Cyan
        $email = if ($claims.email) { $claims.email } elseif ($claims.emails) { $claims.emails[0] } else { "(not present)" }
        Write-Host "  Email: $email" -ForegroundColor Gray
        if ($claims.name) {
            Write-Host "  Name: $($claims.name)" -ForegroundColor Gray
        }
        Write-Host "  Subject (sub): $($claims.sub)" -ForegroundColor Gray
        if ($claims.oid) {
            Write-Host "  Object ID (oid): $($claims.oid)" -ForegroundColor Gray
        }

        return $claims
    } catch {
        # Silently ignore token decode errors
        return $null
    }
}

function Format-NativeAuthError {
    <#
    .SYNOPSIS
        Parse and display a Native Auth API error response.
    #>
    param(
        [Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord,
        [Parameter(Mandatory)][string]$Operation
    )

    Write-Host "`n✗ $Operation failed" -ForegroundColor Red
    Write-Host "Error: $($ErrorRecord.Exception.Message)" -ForegroundColor Red

    if ($ErrorRecord.ErrorDetails.Message) {
        try {
            $errorJson = $ErrorRecord.ErrorDetails.Message | ConvertFrom-Json
            if ($errorJson.error) {
                Write-Host "API Error: $($errorJson.error)" -ForegroundColor Red
            }
            if ($errorJson.error_description) {
                Write-Host "Description: $($errorJson.error_description)" -ForegroundColor Red
            }
            if ($errorJson.suberror) {
                Write-Host "Sub-error: $($errorJson.suberror)" -ForegroundColor Red
            }
        } catch {
            Write-Host "Raw error: $($ErrorRecord.ErrorDetails.Message)" -ForegroundColor Red
        }
    }
}

function Show-TokenResult {
    <#
    .SYNOPSIS
        Display token details from a Native Auth token response.
    #>
    param(
        [Parameter(Mandatory)]$TokenResponse
    )

    Write-Host "Token Details:" -ForegroundColor Cyan
    Write-Host "  Access Token: $($TokenResponse.access_token.Substring(0, 50))..." -ForegroundColor Gray
    Write-Host "  Token Type: $($TokenResponse.token_type)" -ForegroundColor Gray
    Write-Host "  Expires In: $($TokenResponse.expires_in) seconds" -ForegroundColor Gray

    if ($TokenResponse.refresh_token) {
        Write-Host "  Refresh Token: $($TokenResponse.refresh_token.Substring(0, 50))..." -ForegroundColor Gray
    }

    if ($TokenResponse.id_token) {
        Write-Host "  ID Token: $($TokenResponse.id_token.Substring(0, 50))...`n" -ForegroundColor Gray
    }
}
