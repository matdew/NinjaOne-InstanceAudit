function Invoke-NinjaInternalApi {
    <#
    .SYNOPSIS
        Makes authenticated calls to NinjaOne's internal /swb/<shard>/ API.
        Requires ShardBaseUrl and SessionKey to be present in AuthContext.
        Returns $null with a warning if either is missing.
    .PARAMETER AuthContext
        Hashtable built by Invoke-NinjaOneAudit. Must contain ShardBaseUrl and SessionKey.
    .PARAMETER Endpoint
        Endpoint path relative to ShardBaseUrl. E.g. 'scripting/categories'.
    .PARAMETER Method
        HTTP method. Default: GET.
    .PARAMETER Body
        Optional request body (string). Used for POST requests.
    .PARAMETER ContentType
        Content-Type header for the request body. Default: application/json.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [hashtable]$AuthContext,
        [Parameter(Mandatory)] [string]$Endpoint,
        [string]$Method      = 'GET',
        [string]$Body        = $null,
        [string]$ContentType = 'application/json'
    )

    if (-not $AuthContext.ShardBaseUrl -or -not $AuthContext.SessionKey) {
        Write-Warning "Skipping internal API call to '$Endpoint' - ShardBaseUrl or SessionKey not provided."
        return $null
    }

    $plainKey = [System.Net.NetworkCredential]::new('', $AuthContext.SessionKey).Password

    try {
        $hostname = ([System.Uri]$AuthContext.ShardBaseUrl).Host
        $uri      = $AuthContext.ShardBaseUrl.TrimEnd('/') + '/' + $Endpoint.TrimStart('/')

        $webSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        $webSession.UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36 Edg/145.0.0.0'
        $webSession.Cookies.Add((New-Object System.Net.Cookie('sessionKey', $plainKey, '/', $hostname)))

        Write-Verbose "Internal API $Method $uri"

        $iwrParams = @{
            UseBasicParsing = $true
            Uri             = $uri
            Method          = $Method
            WebSession      = $webSession
            Headers         = @{
                'accept'          = '*/*'
                'accept-language' = 'en-US,en;q=0.9'
                'referer'         = "https://$hostname/"
            }
            ErrorAction     = 'Stop'
        }
        if ($Body) {
            $iwrParams['Body']        = $Body
            $iwrParams['ContentType'] = $ContentType
        }
        $response = Invoke-WebRequest @iwrParams

        return $response.Content | ConvertFrom-Json

    } catch {
        $statusCode = $null
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode.value__
        }
        if ($statusCode -eq 401 -or $statusCode -eq 403) {
            Write-Warning "Internal API returned HTTP $statusCode on '$Endpoint' - SessionKey may be expired or invalid."
            return $null
        }
        throw
    } finally {
        # Removes the reference - does not zero memory (.NET strings are GC'd, not pinned)
        $plainKey = $null
    }
}
