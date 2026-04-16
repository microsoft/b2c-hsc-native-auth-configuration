# Step 5: Native Auth Flows

Test native authentication sign-up and sign-in flows using Email OTP.

## Scripts

| Script | Description |
|--------|-------------|
| `1-native-auth-signup.ps1` | Sign up a new user (Email OTP) |
| `2-native-auth-signin.ps1` | Sign in an existing user (Email OTP) |

## Sign-up

```powershell
.\1-native-auth-signup.ps1 -Email "user@example.com"
```

## Sign-in

```powershell
.\2-native-auth-signin.ps1 -Email "user@example.com"
```

> **Note:** If env vars aren't set, pass `-TenantName` and `-ClientId` explicitly.

## Parameters

| Parameter | Used By | Description |
|-----------|---------|-------------|
| `TenantName` | All | Auto from `HSC_TENANT_NAME` env var, or pass explicitly |
| `ClientId` | All | Auto from `HSC_NATIVE_APP_ID` env var, or pass explicitly |
| `Email` | All | User email address |
| `DisplayName` | signup | Optional display name for new user |
