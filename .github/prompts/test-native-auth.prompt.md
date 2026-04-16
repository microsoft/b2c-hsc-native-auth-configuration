---
description: "Test native auth flows: sign-up, sign-in, password reset"
mode: agent
---

Test Native Authentication flows against the user's configured B2C tenant.

## Prerequisites
- Native auth app must be registered and validated (run `configure-native-auth` prompt first)
- Env vars `HSC_TENANT_NAME` and `HSC_NATIVE_APP_ID` must be set

## Instructions

1. Ask the user which flow to test: **sign-up**, **sign-in**, or **password reset**.
2. Ask for the **email address** to use.

### Sign-up
```
.\4-native-auth-flows\1-native-auth-signup.ps1 -Username "<EMAIL>"
```
- This sends an OTP to the email. The user must enter it when prompted.
- For password-based sign-up, add `-Password "SecurePass123!"`.

### Sign-in
```
# OTP-based
.\4-native-auth-flows\2-native-auth-signin.ps1 -Username "<EMAIL>" -UseOTP

# Password-based
.\4-native-auth-flows\2-native-auth-signin.ps1 -Username "<EMAIL>" -Password "<PASSWORD>"
```

### Password Reset
```
.\4-native-auth-flows\3-native-auth-password-reset.ps1 -Username "<EMAIL>"
```
- Prompts for new password interactively (secure input).
- SSPR must be enabled in the tenant.

3. After any successful flow, show the user the decoded token claims if displayed.
