# Steps 3-4: Native Auth Setup

Create the native auth app registration, user flow, and validate the configuration.

## Scripts

| Script | Purpose |
|--------|---------|
| `1-native-auth-register-app.ps1` | Create app registration + service principal (+ optional user flow) |
| `2-native-auth-create-flow.ps1` | Create user flow and link to app (if not using `-CreateFlow`) |
| `3-native-auth-validate.ps1` | Validate the complete setup (4 checks) |

## Usage

After running `1-admin-setup.ps1`, env vars are set automatically.

### All-in-one (recommended)

```powershell
.\1-native-auth-register-app.ps1 -AppName "NativeAuthApp" -CreateFlow
```

### Separate steps

```powershell
.\1-native-auth-register-app.ps1 -AppName "NativeAuthApp"  # Create app only
.\2-native-auth-create-flow.ps1                             # Create flow and link
```

### Validate

```powershell
.\3-native-auth-validate.ps1
```

Or pass parameters explicitly:
```powershell
.\1-native-auth-register-app.ps1 -TenantId "<TENANT_ID>" -AppName "NativeAuthApp" -CreateFlow
```

**Validation checks:**
1. App registration config (nativeAuthenticationApisEnabled, isFallbackPublicClient, signInAudience)
2. Service principal exists
3. Admin consent grants
4. User flow linked to app

## Output

Sets env vars `HSC_NATIVE_APP_ID` and `HSC_TENANT_NAME` — used automatically by flow scripts.
