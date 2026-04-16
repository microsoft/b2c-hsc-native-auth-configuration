# Step 1: Admin Setup

Authenticates the admin user for all Graph API operations in subsequent steps.

## How It Works

Uses the **device code flow** so you don't need any pre-existing client ID or secret. You authenticate interactively in a browser, and the script stores a delegated access token (with auto-refresh) for the session.

No app registration is created — the signed-in user's admin permissions are used directly.

## Usage

```powershell
.\1-admin-setup.ps1 -TenantId "<TENANT_ID>"
```

## Output

Sets environment variables for the session:
- `HSC_TENANT_ID`
- `HSC_ACCESS_TOKEN`
- `HSC_REFRESH_TOKEN`

## Required Role

Global Administrator or Application Administrator on the B2C tenant.
