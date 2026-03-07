function Invoke-NinjaOneAudit {
    <#
    .SYNOPSIS
    Runs the NinjaOne instance audit and generates a self-contained HTML report.

    .DESCRIPTION
    Runs all registered audit checks (or a subset via -Checks) against the already-connected
    NinjaOne session and produces a single-file HTML report. Call Connect-NinjaOne before
    invoking this function. Optionally call Add-NinjaSessionKey first to enable internal-API
    backed audit checks.
    Returns the collected findings array for pipeline use.

    .PARAMETER BaseUrl
    NinjaOne instance base URL. Default: https://app.ninjarmm.com

    .PARAMETER ExportPath
    (Optional) Directory to save the HTML report. Defaults to the current working directory.

    .PARAMETER Checks
    (Optional) Array of check names to run. Runs all registered checks if omitted.

    .OUTPUTS
    PSCustomObject[]. Array of finding objects (Category, Severity, Title, Detail, AffectedCount, AffectedItems).

    .EXAMPLE
    Connect-NinjaOne -Instance us -ClientId 'abc123' -ClientSecret 'secret' -Scopes @('monitoring','management','control') -UseClientAuth
    Invoke-NinjaOneAudit

    .EXAMPLE
    Connect-NinjaOne -Instance us -ClientId 'abc123' -ClientSecret 'secret' -Scopes @('monitoring','management','control') -UseClientAuth
    Add-NinjaSessionKey -ShardBaseUrl 'https://us2.ninjarmm.com/swb/s3'
    Invoke-NinjaOneAudit
    #>
    [CmdletBinding()]
    param (
        [string]$BaseUrl = 'https://app.ninjarmm.com',

        [string]$ExportPath,

        [string[]]$Checks
    )

    $savedEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'
    $InformationPreference = 'Continue'

    try {
        $authContext = @{
            BaseUrl            = $BaseUrl
            ShardBaseUrl       = $script:NinjaAuditShardBaseUrl
            SessionKey         = $script:NinjaAuditSessionKey
            TenantCapabilities = $script:NinjaAuditTenantCapabilities
        }

        Write-Information "`nNinjaOne Instance Health Audit"
        Write-Information "Instance: $BaseUrl"
        Write-Information ('-' * 50)

        if (-not $script:NinjaAuditShardBaseUrl) {
            Write-Information ''
            Write-Information 'NOTE: Internal API credentials not configured.'
            Write-Information '      Policy and other internal-API-backed checks will be skipped.'
            Write-Information '      To enable, call Add-NinjaSessionKey before Invoke-NinjaOneAudit:'
            Write-Information '        Add-NinjaSessionKey'
            Write-Information '      The instance URL is auto-detected from your Connect-NinjaOne session.'
            Write-Information '      Override with -Instance (e.g. us, eu, us2) if needed.'
            Write-Information ''
        }

        # Step 1: Run checks
        Write-Information "`n[1/2] Running audit checks..."
        $catalog = Get-NinjaCheckCatalog
        $allFindings = Invoke-NinjaAuditOrchestrator `
            -AuthContext $authContext `
            -Catalog     $catalog `
            -Checks      $Checks

        Write-Information "      $($allFindings.Count) finding(s) collected."

        # Step 2: Generate report
        Write-Information "`n[2/2] Generating HTML report..."
        $reportPath = New-NinjaHealthReport `
            -Findings   $allFindings `
            -BaseUrl    $BaseUrl `
            -ExportPath $ExportPath

        Write-Information "      Report saved: $reportPath"
        Write-Information "`nAudit complete.`n"

        return $allFindings
    } finally {
        $ErrorActionPreference = $savedEAP
    }
}
