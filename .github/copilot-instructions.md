# HSC Mode & Native Authentication — Copilot Context

This repo automates enabling **HSC (High Scale Compatibility) mode** on Azure AD B2C tenants and configuring **Native Authentication APIs**.

## Repo Structure

- `run-all.ps1` — One-shot: runs all steps end-to-end
- `1-admin-setup/1-admin-setup.ps1` — Device code flow → sets delegated token env vars
- `2-hsc-setup/1-hsc-preflight-check.ps1` — 4 preflight checks (tenant type, permissions, custom attrs, subscription)
- `2-hsc-setup/2-hsc-enable.ps1` — Enable HSC mode
- `2-hsc-setup/3-hsc-enable-email-otp.ps1` — Enable Email OTP
- `2-hsc-setup/4-hsc-check-status.ps1` — Check HSC + Email OTP status
- `2-hsc-setup/5-hsc-disable.ps1` — Disable HSC mode
- `3-native-auth-setup/1-native-auth-register-app.ps1` — Register native auth app + SP + flow
- `3-native-auth-setup/2-native-auth-create-flow.ps1` — Create user flow separately
- `3-native-auth-setup/3-native-auth-validate.ps1` — Validate full setup (4 checks)
- `4-native-auth-flows/1-native-auth-signup.ps1` — Sign-up (passwordless or with password)
- `4-native-auth-flows/2-native-auth-signin.ps1` — Sign-in (OTP or password)
- `4-native-auth-flows/3-native-auth-password-reset.ps1` — SSPR password reset

## Environment Variables

Scripts propagate credentials automatically via env vars — no need to repeat params after Step 1:

| Env Variable | Set By | Used By |
|-------------|--------|---------|
| `HSC_TENANT_ID` | `1-admin-setup.ps1` | Steps 2-4 |
| `HSC_ACCESS_TOKEN` | `1-admin-setup.ps1` | Steps 2-3 (auto-refreshed) |
| `HSC_REFRESH_TOKEN` | `1-admin-setup.ps1` | Steps 2-3 (for token renewal) |
| `HSC_NATIVE_APP_ID` | `1-native-auth-register-app.ps1` | Steps 4-5 |
| `HSC_TENANT_NAME` | `1-native-auth-register-app.ps1` | Step 5 |

## Execution Order

1. `.\1-admin-setup\1-admin-setup.ps1 -TenantId "<TENANT_ID>"`
2. `.\2-hsc-setup\1-hsc-preflight-check.ps1`
3. `.\2-hsc-setup\2-hsc-enable.ps1`
4. `.\2-hsc-setup\3-hsc-enable-email-otp.ps1`
5. `.\3-native-auth-setup\1-native-auth-register-app.ps1 -AppName "NativeAuthApp" -CreateFlow`
6. `.\3-native-auth-setup\3-native-auth-validate.ps1`
7. `.\4-native-auth-flows\1-native-auth-signup.ps1 -Username "user@example.com"`

Or one-shot: `.\run-all.ps1 -TenantId "<TENANT_ID>"`

## Key Technical Details

- Graph API beta is required for `authenticationEventsFlows` (v1.0 not supported on B2C)
- `$filter` and `$select` don't work on beta authenticationEventsFlows — list all + filter in memory
- SP creation after app registration has replication lag — scripts use retry with backoff
- Admin consent is granted via `oauth2PermissionGrants` POST (SP-scoped endpoint)
- After enabling HSC mode, wait up to 1 hour for propagation

## When Running Scripts

- Always run from the **repo root directory**
- If env vars aren't set, the user needs to run `1-admin-setup.ps1` first
- Tokens auto-refresh when near expiry — no manual re-auth needed within a session
- The `-AutoFix` flag on preflight check fixes empty custom attribute descriptions automatically
- The user needs **Global Administrator** or **Application Administrator** role
- **`1-admin-setup.ps1` uses device code flow** — it prints a URL and a code, then blocks waiting for the user to authenticate in a browser. Always run it in **async mode** (or with a long timeout) so the user has time to complete the browser login. After launching, read the terminal output to extract the URL and device code, then present them directly in the chat message so the user can click/copy without switching to the terminal. Wait for the script to finish before proceeding to step 2.

## Common Errors

| Error | Fix |
|-------|-----|
| `Authorization_RequestDenied` | Re-run Step 1 or grant permissions manually |
| `AADB2C99089` | Run `1-hsc-preflight-check.ps1 -AutoFix` |
| `HybridUpgradeNotAllowed` | Tenant not allow-listed — contact Microsoft Support |
| `consent_required` on signup | Admin consent not granted — re-run `1-native-auth-register-app.ps1` |
