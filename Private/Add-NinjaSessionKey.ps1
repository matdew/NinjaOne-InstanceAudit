# Module-level state for internal API credentials.
# Set by Add-NinjaSessionKey; consumed by Invoke-NinjaOneAudit via $authContext.
$script:NinjaAuditShardBaseUrl       = $null
$script:NinjaAuditSessionKey         = $null
$script:NinjaAuditTenantCapabilities = $null

function Add-NinjaSessionKey {
    <#
    .SYNOPSIS
    Registers the browser SessionKey needed for NinjaOne internal API access.
    Call this once per session before Invoke-NinjaOneAudit if you want internal-API-backed
    audit checks to run (e.g. policy and backup checks).

    .DESCRIPTION
    Calls /ws/webapp/sessionproperties with the provided session cookie to automatically
    derive the shard base URL (serverCallPrefix) and fetch tenant feature flags (divisionConfig).
    These are stored in module scope and injected into AuthContext by Invoke-NinjaOneAudit.

    The NinjaOne instance URL is resolved in this order:
      1. -Instance parameter (e.g. 'us', 'eu', 'us2') - explicit override
      2. Auto-detected from the connected NinjaOne module (Connect-NinjaOne must have been called)

    .PARAMETER Instance
    NinjaOne instance identifier. Same values accepted by Connect-NinjaOne:
    'us', 'eu', 'oc', 'ca', 'us2', 'app'. If omitted, the instance URL is
    auto-detected from the active NinjaOne module connection.

    .PARAMETER SessionKey
    Browser session cookie as a SecureString. If omitted, you will be prompted interactively.

    .EXAMPLE
    # Typical usage - Connect-NinjaOne must be called first
    Connect-NinjaOne -Instance us -ClientId 'abc' -ClientSecret 'secret' -Scopes @('monitoring','management','control') -UseClientAuth
    Add-NinjaSessionKey
    Invoke-NinjaOneAudit

    .EXAMPLE
    # Explicit instance override
    Add-NinjaSessionKey -Instance us2
    #>
    [CmdletBinding()]
    param (
        [string]$Instance,

        [System.Security.SecureString]$SessionKey
    )

    # Resolve instance URL
    $instanceUrl  = $null
    $ninjaModule  = Get-Module -Name NinjaOne

    if ($Instance) {
        $instanceMap = & $ninjaModule { $Script:NRAPIInstances }
        if (-not $instanceMap.ContainsKey($Instance)) {
            $valid = $instanceMap.Keys -join ', '
            throw "Unknown -Instance '$Instance'. Valid values: $valid"
        }
        $instanceUrl = $instanceMap[$Instance]
    } else {
        if ($ninjaModule) {
            $instanceUrl = & $ninjaModule { $Script:NRAPIConnectionInformation.URL }
        }
    }

    if (-not $instanceUrl) {
        throw "Could not determine NinjaOne instance URL. Either call Connect-NinjaOne first, or provide -Instance (e.g. 'us', 'eu', 'us2')."
    }

    if (-not $SessionKey) {
        Write-Information ''
        Write-Information 'Finding your NinjaOne session key:'
        Write-Information '  1. Open NinjaOne in your browser and log in'
        Write-Information '  2. Open DevTools: press F12 (or right-click anywhere and choose Inspect)'
        Write-Information '  3. Chrome / Edge: Application tab -> Cookies -> your NinjaOne domain'
        Write-Information '     Firefox:       Storage tab  -> Cookies -> your NinjaOne domain'
        Write-Information "  4. Copy the Value of the cookie named 'sessionKey'"
        Write-Information '  Note: The session key expires when your browser session ends.'
        Write-Information ''
        $SessionKey = Read-Host -AsSecureString -Prompt 'Paste sessionKey cookie value'
    }

    # Call sessionproperties to derive ShardBaseUrl and TenantCapabilities
    $plainKey = [System.Net.NetworkCredential]::new('', $SessionKey).Password
    try {
        $instanceHost = ([System.Uri]$instanceUrl).Host
        $uri          = $instanceUrl.TrimEnd('/') + '/ws/webapp/sessionproperties'

        $webSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        $webSession.UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36 Edg/145.0.0.0'
        $webSession.Cookies.Add((New-Object System.Net.Cookie('sessionKey', $plainKey, '/', $instanceHost)))

        Write-Verbose "Fetching session properties from $uri"

        $response = Invoke-WebRequest `
            -UseBasicParsing `
            -Uri        $uri `
            -Method     GET `
            -WebSession $webSession `
            -Headers    @{
                'accept'          = '*/*'
                'accept-language' = 'en-US,en;q=0.9'
                'referer'         = "https://$instanceHost/"
            } `
            -ErrorAction Stop

        $props = $response.Content | ConvertFrom-Json

        if (-not $props.serverCallPrefix) {
            throw "sessionproperties response did not include 'serverCallPrefix'. The session key may be invalid or expired."
        }

        $script:NinjaAuditShardBaseUrl = $instanceUrl.TrimEnd('/') + '/' + $props.serverCallPrefix.TrimStart('/')
        $script:NinjaAuditSessionKey   = $SessionKey

        $caps = @{}
        foreach ($cap in $props.divisionConfig) {
            $caps[$cap.name] = [bool]$cap.enabled
        }
        $script:NinjaAuditTenantCapabilities = $caps

        Write-Verbose "Shard base URL: $($script:NinjaAuditShardBaseUrl)"
        Write-Verbose "Tenant capabilities loaded: $($caps.Count) features"

    } catch {
        $statusCode = $null
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode.value__
        }
        if ($statusCode -eq 401 -or $statusCode -eq 403) {
            throw "sessionproperties returned HTTP $statusCode - the session key is invalid or expired. Retrieve a fresh key from your browser cookies."
        }
        throw
    } finally {
        $plainKey = $null
    }

    Write-Information "NinjaOne session key registered. Shard: $($script:NinjaAuditShardBaseUrl)"
}
