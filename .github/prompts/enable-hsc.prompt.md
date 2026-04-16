---
description: "Enable HSC mode on a B2C tenant (Steps 1-2: admin setup + preflight + enable)"
mode: agent
---

Enable HSC (High Scale Compatibility) mode on the user's Azure AD B2C tenant.

## Instructions

1. Ask the user for their **Tenant ID** if not already known.
2. Check if env vars are set (`$env:HSC_TENANT_ID`, `$env:HSC_ACCESS_TOKEN`, `$env:HSC_REFRESH_TOKEN`).
3. If env vars are NOT set, run admin setup first:
   ```
   .\1-admin-setup\1-admin-setup.ps1 -TenantId "<TENANT_ID>"
   ```
   This requires interactive device code auth — tell the user to open the URL and enter the code.
4. Run preflight checks:
   ```
   .\2-hsc-setup\1-hsc-preflight-check.ps1
   ```
   If any checks FAIL, help the user fix them. Use `-AutoFix` for custom attribute issues.
5. Enable HSC mode:
   ```
   .\2-hsc-setup\2-hsc-enable.ps1
   ```
6. Enable Email OTP:
   ```
   .\2-hsc-setup\3-hsc-enable-email-otp.ps1
   ```
7. Tell the user: "HSC mode enabled. Wait up to 1 hour for propagation before configuring native auth."
