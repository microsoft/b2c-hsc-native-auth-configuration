# Step 5: Native Auth Flows

Test native authentication sign-up, sign-in, and password reset flows.

## Scripts

| Script | Description |
|--------|-------------|
| `1-native-auth-signup.ps1` | Sign up a new user (passwordless or with password) |
| `2-native-auth-signin.ps1` | Sign in an existing user (OTP or password) |
| `3-native-auth-password-reset.ps1` | Self-service password reset (SSPR) |

## Sign-up

```powershell
# Passwordless (Email OTP only)
.\1-native-auth-signup.ps1 -Username "user@example.com"

# With password
.\1-native-auth-signup.ps1 -Username "user@example.com" -Password "SecurePass123!"
```

## Sign-in

```powershell
# OTP
.\2-native-auth-signin.ps1 -Username "user@example.com" -UseOTP

# Password
.\2-native-auth-signin.ps1 -Username "user@example.com" -Password "SecurePass123!"
```

## Password Reset

```powershell
# Interactive (recommended — prompts for password securely)
.\3-native-auth-password-reset.ps1 -Username "user@example.com"
```

> **Note:** If env vars aren't set, pass `-TenantName` and `-ClientId` explicitly.
>
> SSPR must be enabled in the tenant. Verify in the Entra admin center under **Authentication methods** > **Password reset**.

## Parameters

| Parameter | Used By | Description |
|-----------|---------|-------------|
| `TenantName` | All | Auto from `HSC_TENANT_NAME` env var, or pass explicitly |
| `ClientId` | All | Auto from `HSC_NATIVE_APP_ID` env var, or pass explicitly |
| `Username` | All | User email address |
| `Password` | signup, signin | Password (omit for passwordless) |
| `UseOTP` | signin | Use OTP instead of password |
| `DisplayName` | signup | Optional display name for new user |
| `NewPassword` | password-reset | New password (prompts interactively if omitted) |
