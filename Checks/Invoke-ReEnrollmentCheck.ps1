function Invoke-ReEnrollmentCheck {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [hashtable]$AuthContext
    )

    Write-Verbose 'Running check: ReEnrollment'

    $reEnrollDays   = 30
    $reEnrollCutoff = [DateTimeOffset]::UtcNow.AddDays(-$reEnrollDays).ToUnixTimeSeconds()

    $orgList = Get-NinjaOneOrganisations
    $orgMap  = @{}
    foreach ($org in $orgList) {
        $orgMap[[int]$org.id] = $org.name
    }

    $allDevices = Get-NinjaOneDevices

    $deviceMap = @{}
    foreach ($dev in $allDevices) {
        $orgName = if ($orgMap.ContainsKey([int]$dev.organizationId)) { $orgMap[[int]$dev.organizationId] } else { 'Unknown Org' }
        $devName = if ($dev.displayName) { $dev.displayName } else { $dev.systemName }
        $deviceMap[[int]$dev.id] = "$devName ($orgName)"
    }

    $reEnrollAll = [System.Collections.Generic.List[object]]::new()
    $cursor      = $null
    do {
        $path = "/api/v2/activities?class=DEVICE&activityType=NODE_RE_ENROLLED&newerThan=$reEnrollCutoff&pageSize=1000"
        if ($cursor) { $path += "&before=$cursor" }

        $page = Invoke-NinjaOneRequest -Method GET -Path $path

        if ($null -eq $page) { break }

        if ($page.activities -and $page.activities.Count -gt 0) {
            $reEnrollAll.AddRange([object[]]@($page.activities))
            $cursor = $page.pageDetails.lastCursorId
            if (-not $cursor) { break }
        } else {
            break
        }
    } while ($cursor)

    # Devices re-enrolled more than once in the window
    $reEnrollGroups = @($reEnrollAll |
        Group-Object -Property sourceNodeId |
        Where-Object { $_.Count -gt 1 })

    if ($reEnrollGroups.Count -gt 0) {
        $reEnrollItems = $reEnrollGroups | ForEach-Object {
            $devId = [int]$_.Group[0].sourceNodeId
            $label = if ($deviceMap.ContainsKey($devId)) { $deviceMap[$devId] } else { "Device ID $devId" }
            "$label - re-enrolled $($_.Count) time(s) in $reEnrollDays days"
        }

        return @(
            New-NinjaFinding `
                -Category      'DeviceHygiene' `
                -Severity      'Warning' `
                -Title         "Devices re-enrolling repeatedly ($reEnrollDays-day window)" `
                -Detail        "$($reEnrollGroups.Count) device(s) have re-enrolled more than once in the past $reEnrollDays days (activity: NODE_RE_ENROLLED). This may indicate agent instability, imaging issues, or device replacement without decommission." `
                -AffectedCount $reEnrollGroups.Count `
                -AffectedItems @($reEnrollItems)
        )
    }

    return @(
        New-NinjaFinding `
            -Category 'DeviceHygiene' `
            -Severity 'Info' `
            -Title    'No repeated re-enrollments found' `
            -Detail   "No devices have re-enrolled more than once in the past $reEnrollDays days."
    )
}
