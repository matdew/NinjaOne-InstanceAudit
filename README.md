# NinjaOne-InstanceAudit

A PowerShell module that audits a NinjaOne RMM instance and generates a self-contained HTML report. It runs a suite of configurable checks across device hygiene, policy health, backup coverage, and more, then produces a single `.html` file you can open in any browser — no server required.

## Prerequisites

- PowerShell 5.1 or later (or PowerShell 7+)
- [NinjaOne PowerShell module](https://www.powershellgallery.com/packages/NinjaOne) — install once:

```powershell
Install-Module NinjaOne -Scope CurrentUser -Force
```

- A NinjaOne API client (Client ID + Client Secret) with scopes: `monitoring`

## Import

```powershell
Import-Module .\NinjaOne-InstanceAudit.psd1
```

## Quick Start

```powershell
Connect-NinjaOne -Instance us -ClientId "YOUR_CLIENT_ID" -ClientSecret "YOUR_SECRET" `
    -Scopes @('monitoring') -UseClientAuth

Invoke-NinjaOneAudit
```

The report is written to the current directory as `NinjaOne-Audit-<timestamp>.html`.

## Full Usage

```powershell
# Connect first (required before Invoke-NinjaOneAudit)
Connect-NinjaOne -Instance us -ClientId "YOUR_CLIENT_ID" -ClientSecret "YOUR_SECRET" `
    -Scopes @('monitoring') -UseClientAuth

# Optional: enable internal API checks (prompts for browser session key)
Add-NinjaSessionKey

# Run all checks, save report to a specific path
Invoke-NinjaOneAudit -ExportPath "C:\Reports"

# Run only specific checks
Invoke-NinjaOneAudit -Checks "StaleDevices","UnusedPolicies"
```

### Parameters — `Invoke-NinjaOneAudit`

| Parameter | Default | Description |
|---|---|---|
| `-ExportPath` | Current directory | Directory to save the HTML report |
| `-Checks` | All checks | Names of specific checks to run (e.g. `"StaleDevices"`) |

### Parameters — `Add-NinjaSessionKey`

| Parameter | Default | Description |
|---|---|---|
| `-Instance` | Auto-detected from `Connect-NinjaOne` | Instance identifier to override auto-detection (e.g. `us`, `eu`, `us2`) |
| `-SessionKey` | Prompted interactively | Browser session cookie as a `SecureString` |

## Implemented Checks

| Category | Check | What it finds |
|---|---|---|
| Device Hygiene | StaleDevices | Devices with no check-in for more than 60 days |
| Device Hygiene | PendingApproval | Devices waiting for manual approval |
| Device Hygiene | ReEnrollment | Devices that re-enrolled more than once in the past 30 days |
| Policy Health | UnusedPolicies | Policies with no organizations or devices assigned |
| Policy Health | ExcessiveRootPolicies | Too many policies at the root level |
| Backup Hygiene | BackupCoverage | Devices with backup jobs that do not cover all drives (requires `Add-NinjaSessionKey`) |

## Roadmap

**Policy Health**
- [ ] Overridden policy conditions

**Alerting Quality**
- [ ] Conditions firing silently (notificationAction = NONE)
- [ ] Disabled conditions
- [ ] Uncategorized conditions (severity = NONE)
- [ ] Conditions with no notification channels

**Administration**
- [ ] Technician accounts without MFA
- [ ] Technician accounts with no role assigned
- [ ] Unused technician and end-user roles
- [ ] Empty or disorganized custom field tabs
- [ ] Disabled scheduled tasks

**Script Library**
- [ ] Scripts with no description

**Custom Fields**
- [ ] Org custom fields that may be missing values


## Adding a New Check

The module auto-discovers checks — no catalog registration needed.

1. Create `Checks/<Name>.ps1` with a function named `Invoke-<Name>Check`
2. Use the signature `param([hashtable]$AuthContext)` and return `@( New-NinjaFinding ... )` — always an array
3. Re-import the module: `Import-Module .\NinjaOne-InstanceAudit.psd1 -Force`
4. The check is now included in all future audit runs automatically

Errors thrown inside a check are caught by the orchestrator and surfaced as Critical findings — do not swallow exceptions inside checks.

## Authentication Notes

### OAuth2 (required for all checks)

The NinjaOne module handles OAuth2 after `Connect-NinjaOne` is called. All built-in `Get-NinjaOne*` cmdlets and `Invoke-NinjaOneRequest` work automatically within checks.

### Internal API session key (optional, needed for some checks)

Some NinjaOne data is only available through internal web endpoints not covered by the public API. Call `Add-NinjaSessionKey` before `Invoke-NinjaOneAudit` to enable these checks.

The session key is a browser cookie obtained from an active NinjaOne web UI session. It expires when the browser session ends. Checks that require it will skip gracefully (returning no findings) when the session key is absent.

```powershell
# Interactive prompt (recommended)
Add-NinjaSessionKey

# Or pass as SecureString
$key = ConvertTo-SecureString "your-session-key-here" -AsPlainText -Force
Add-NinjaSessionKey -SessionKey $key
```
