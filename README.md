# HSC Mode & Native Authentication for Azure AD B2C

This repository is the companion to the official Microsoft documentation for enabling **High Scale Compatibility (HSC) mode** on Azure AD B2C tenants. It provides automated scripts to configure, validate, and test every step of the enablement of High Scale Compatibility mode in Azure AD B2C and showcasw how to configure and test Native Authentication APIs.

> **Official documentation:** [Enable External ID High Scale Compatibility mode](https://learn.microsoft.com/en-us/entra/external-id/customers/enable-external-id-high-scale-compatibility-mode)

## What This Repo Does

| Step | What happens |
|------|-------------|
| 1 | **Set up admin credentials** — Authenticate and create an app with the necessary permissions |
| 2 | **Enable HSC mode** — Validate tenant readiness, enable High Scale Compatibility, and turn on Email OTP |
| 3 | **Configure Native Authentication** — Register your app, create a user flow, and link them together |
| 4 | **Validate** — Verify everything is correctly configured before going live |
| 5 | **Test the flows** — Sign up new users, sign in, and reset passwords using Native Auth APIs |

## Prerequisites

- Azure AD B2C tenant (allow-listed for HSC mode)
- **Global Administrator** or **Application Administrator** role
- PowerShell 5.1+ (PowerShell 7+ recommended)

## Quick Start

### Option A: One-Shot (run everything at once)

```powershell
.\run-all.ps1 -TenantId "<TENANT_ID>"

# Or include a sign-up test at the end
.\run-all.ps1 -TenantId "<TENANT_ID>" -TestUsername "user@example.com"
```

### Option B: Step by Step

Each script sets **environment variables** automatically, so subsequent scripts don't need repeated parameters.

#### Step 1: Authenticate

```powershell
.\1-admin-setup\1-admin-setup.ps1 -TenantId "<TENANT_ID>"
```

This sets `HSC_TENANT_ID`, `HSC_ACCESS_TOKEN`, and `HSC_REFRESH_TOKEN` for the session.

#### Step 2: Preflight Checks & Enable HSC Mode

```powershell
.\2-hsc-setup\1-hsc-preflight-check.ps1      # Preflight checks — fix any FAIL items before proceeding
.\2-hsc-setup\2-hsc-enable.ps1           # Enable HSC mode
.\2-hsc-setup\3-hsc-enable-email-otp.ps1     # Enable Email OTP (required for Native Auth with email)
```

> **Important:** After enabling HSC mode, allow up to 1 hour for changes to propagate.

#### Step 3: Create Native Auth App & User Flow

```powershell
.\3-native-auth-setup\1-native-auth-register-app.ps1 -AppName "NativeAuthApp" -CreateFlow
```

This sets `HSC_NATIVE_APP_ID` and `HSC_TENANT_NAME` for the session.

#### Step 4: Validate Setup

```powershell
.\3-native-auth-setup\3-native-auth-validate.ps1
```

#### Step 5: Test Native Auth Flows

```powershell
# Sign up (passwordless)
.\4-native-auth-flows\1-native-auth-signup.ps1 -Username "user@example.com"

# Sign in (OTP)
.\4-native-auth-flows\2-native-auth-signin.ps1 -Username "user@example.com" -UseOTP

# Sign in (password)
.\4-native-auth-flows\2-native-auth-signin.ps1 -Username "user@example.com" -Password "SecurePass123!"

# Password reset (interactive)
.\4-native-auth-flows\3-native-auth-password-reset.ps1 -Username "user@example.com"
```

> **Tip:** All parameters can still be passed explicitly if needed (e.g., `-TenantId`). The env vars are just a convenience.
>
> **Note:** SSPR must be enabled in the tenant for password reset. Verify in the Entra admin center under **Authentication methods** > **Password reset**.

## Repository Structure

```
run-all.ps1                     # One-shot: runs all steps end-to-end
│
common/                         # Shared PowerShell helpers
│   graph-helpers.ps1           # Get-GraphHeaders, Get-DelegatedToken, Refresh-GraphToken, etc.
│
1-admin-setup/                  # Step 1: Authenticate via device code flow
│   1-admin-setup.ps1
│   README.md
│
2-hsc-setup/                    # Step 2: Preflight + Enable HSC + Email OTP
│   1-hsc-preflight-check.ps1
│   2-hsc-enable.ps1
│   3-hsc-enable-email-otp.ps1
│   4-hsc-check-status.ps1
│   5-hsc-disable.ps1
│   hsc-helpers.ps1
│   README.md
│
3-native-auth-setup/            # Steps 3-4: App registration + user flow + validate
│   1-native-auth-register-app.ps1
│   2-native-auth-create-flow.ps1
│   3-native-auth-validate.ps1
│   README.md
│
4-native-auth-flows/            # Step 5: Sign-up, sign-in, password reset
│   1-native-auth-signup.ps1
│   2-native-auth-signin.ps1
│   3-native-auth-password-reset.ps1
│   README.md
│
.github/
│   copilot-instructions.md     # Auto-loaded context for GitHub Copilot
│   prompts/                    # Reusable Copilot Chat prompts
│       setup-all.prompt.md
│       enable-hsc.prompt.md
│       configure-native-auth.prompt.md
│       test-native-auth.prompt.md
│       troubleshoot.prompt.md
```

## GitHub Copilot Integration

This repo includes built-in GitHub Copilot support. When you open the repo in VS Code with GitHub Copilot:

- **Auto-loaded context:** `.github/copilot-instructions.md` is automatically loaded into every Copilot Chat conversation, giving Copilot full knowledge of the repo structure, scripts, env vars, and common errors.
- **Reusable prompts:** Open the prompt picker in Copilot Chat (click the 📎 icon or type `/`) and select a prompt:

| Prompt | What it does |
|--------|-------------|
| `setup-all` | Run the full end-to-end setup |
| `enable-hsc` | Enable HSC mode (Steps 1-2) |
| `configure-native-auth` | Register app + create flow (Steps 3-4) |
| `test-native-auth` | Test sign-up, sign-in, password reset |
| `troubleshoot` | Diagnose common errors |


## Resources

- [Native Authentication API Reference](https://learn.microsoft.com/entra/external-id/customers/reference-native-authentication-api)
- [Native Authentication Concept](https://learn.microsoft.com/entra/external-id/customers/concept-native-authentication)
- [External ID Documentation](https://learn.microsoft.com/entra/external-id/)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT License - see [LICENSE.txt](LICENSE.txt).

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft
trademarks or logos is subject to and must follow
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.

---

_This repository is intended as an example or learning tool._
