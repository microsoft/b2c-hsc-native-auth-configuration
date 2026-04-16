---
description: "Run the full HSC + Native Auth setup end-to-end on a B2C tenant"
mode: agent
---

Run all steps to enable HSC mode and configure Native Authentication on the user's B2C tenant.

## Instructions

1. Ask the user for their **Tenant ID** (GUID) if not already known.
2. Run the one-shot script from the repo root:
   ```
   .\run-all.ps1 -TenantId "<TENANT_ID>"
   ```
3. The script requires **interactive device code authentication** — tell the user to open the URL shown and enter the code.
4. Wait for each step to complete. If any step fails, check the error output and consult `.github/copilot-instructions.md` for common fixes.
5. After all steps pass, suggest testing sign-up:
   ```
   .\4-native-auth-flows\1-native-auth-signup.ps1 -Email "user@example.com"
   ```
