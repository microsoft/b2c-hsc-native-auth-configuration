---
description: "Configure Native Authentication app and user flow (Steps 3-4)"
mode: agent
---

Set up a Native Authentication app registration and user flow on the user's B2C tenant.

## Prerequisites
- HSC mode must already be enabled (run the `enable-hsc` prompt first)
- Env vars `HSC_TENANT_ID`, `HSC_ACCESS_TOKEN`, `HSC_REFRESH_TOKEN` must be set

## Instructions

1. Verify env vars are set. If not, tell the user to run `1-admin-setup.ps1` first.
2. Register the native auth app with user flow:
   ```
   .\3-native-auth-setup\1-native-auth-register-app.ps1 -AppName "NativeAuthApp" -CreateFlow
   ```
3. Validate the setup:
   ```
   .\3-native-auth-setup\3-native-auth-validate.ps1
   ```
4. If all 4 checks pass, tell the user they can now test sign-up:
   ```
   .\4-native-auth-flows\1-native-auth-signup.ps1 -Username "user@example.com"
   ```
5. If any check fails, read the error and consult `.github/copilot-instructions.md` for fixes.
