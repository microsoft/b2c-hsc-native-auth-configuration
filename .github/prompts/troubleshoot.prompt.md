---
description: "Troubleshoot common HSC and Native Auth errors"
mode: agent
---

Help the user diagnose and fix errors with HSC mode or Native Authentication.

## Instructions

1. Ask the user to describe the error or paste the error message.
2. Match against known errors:

| Error | Cause | Fix |
|-------|-------|-----|
| `Authorization_RequestDenied` | Missing Graph API permissions | Re-run `.\1-admin-setup\1-admin-setup.ps1` |
| `AADB2C99089` | Custom attributes have empty descriptions | Run `.\2-hsc-setup\1-hsc-preflight-check.ps1 -AutoFix` |
| `HybridUpgradeNotAllowed` | Tenant not allow-listed for HSC | Contact Microsoft Support with parent tenant ID |
| `NoResourceProviderDataFound` | No Azure subscription linked | Link subscription in Azure portal → B2C Settings |
| `user_not_found` | User doesn't exist for sign-in | Sign up first with `1-native-auth-signup.ps1` |
| `consent_required` on signup | Admin consent not granted | Re-run `.\3-native-auth-setup\1-native-auth-register-app.ps1` |

3. If the error doesn't match, help the user:
   - Check HSC status: `.\2-hsc-setup\4-hsc-check-status.ps1`
   - Validate setup: `.\3-native-auth-setup\3-native-auth-validate.ps1`
   - Verify env vars are set: `$env:HSC_TENANT_ID`, `$env:HSC_ACCESS_TOKEN`, etc.

4. Key limitations to mention if relevant:
   - Passkeys are NOT supported
   - Native auth supports local accounts only (no social/federated IdPs)
   - Phone MFA (SMS/voice) is NOT supported in HSC mode
   - After enabling HSC, wait up to 1 hour for propagation
