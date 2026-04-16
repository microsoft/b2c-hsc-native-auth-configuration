---
description: "Test native auth flows: sign-up and sign-in"
mode: agent
---

Test Native Authentication flows against the user's configured B2C tenant.

## Prerequisites
- Native auth app must be registered and validated (run `configure-native-auth` prompt first)
- Env vars `HSC_TENANT_NAME` and `HSC_NATIVE_APP_ID` must be set

## Instructions

1. Ask the user which flow to test: **sign-up** or **sign-in**.
2. Ask for the **email address** to use.

### Sign-up
```
.\4-native-auth-flows\1-native-auth-signup.ps1 -Email "<EMAIL>"
```
- This sends an OTP to the email. The user must enter it when prompted.

### Sign-in
```
.\4-native-auth-flows\2-native-auth-signin.ps1 -Email "<EMAIL>"
```

3. After any successful flow, show the user the decoded token claims if displayed.
