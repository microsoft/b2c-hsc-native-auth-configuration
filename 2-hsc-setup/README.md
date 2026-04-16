# Step 2: HSC Setup

Preflight checks and HSC (High Scale Compatibility) mode management.

## Scripts

| # | Script | Description |
|---|--------|-------------|
| 1 | `1-hsc-preflight-check.ps1` | Run 4 checks to validate B2C tenant readiness |
| 2 | `2-hsc-enable.ps1` | Enable HSC mode |
| 3 | `3-hsc-enable-email-otp.ps1` | Enable Email OTP (required for native auth with email) |
| 4 | `4-hsc-check-status.ps1` | Check HSC mode and Email OTP status |
| 5 | `5-hsc-disable.ps1` | Disable HSC mode |

## Usage

After running `1-admin-setup.ps1`, env vars are set automatically — just run:

```powershell
.\1-hsc-preflight-check.ps1          # Preflight checks
.\1-hsc-preflight-check.ps1 -AutoFix # Auto-fix empty custom attribute descriptions
.\2-hsc-enable.ps1                   # Enable HSC mode
.\3-hsc-enable-email-otp.ps1         # Enable Email OTP
.\4-hsc-check-status.ps1             # Check status (optional)
```

Or pass TenantId explicitly:
```powershell
.\1-hsc-preflight-check.ps1 -TenantId "<TENANT_ID>"
```

## Preflight Checks

1. **Tenant type** — Confirms B2C tenant
2. **Graph API permissions** — Tests access to HSC endpoint
3. **Custom attributes** — Detects empty descriptions (cause `AADB2C99089`)
4. **Subscription** — Verifies Azure subscription linkage

> **Important:** After enabling HSC mode, wait **up to 1 hour** for propagation before proceeding to Step 3.
