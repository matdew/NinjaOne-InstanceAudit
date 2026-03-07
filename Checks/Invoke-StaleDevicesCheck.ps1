function Invoke-StaleDevicesCheck {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [hashtable]$AuthContext
    )

    Write-Verbose 'Running check: StaleDevices'

    $staleDays    = 60
    $nowSec       = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $thresholdSec = $nowSec - ($staleDays * 86400)

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

    # Exclude devices with null/zero lastContact (never checked in - likely pending)
    $staleDevices = @($allDevices | Where-Object {
        $_.lastContact -and $_.lastContact -gt 0 -and $_.lastContact -lt $thresholdSec
    })

    if ($staleDevices.Count -gt 0) {
        $staleItems = $staleDevices | ForEach-Object {
            $label    = if ($deviceMap.ContainsKey([int]$_.id)) { $deviceMap[[int]$_.id] } else { "Device ID $($_.id)" }
            $daysSeen = [Math]::Floor(($nowSec - $_.lastContact) / 86400)
            "$label - last seen $daysSeen days ago"
        }

        return @(
            New-NinjaFinding `
                -Category      'DeviceHygiene' `
                -Severity      'Warning' `
                -Title         "Stale devices: no check-in for $staleDays+ days" `
                -Detail        "$($staleDevices.Count) device(s) have not contacted NinjaOne in over $staleDays days. These may be offline, decommissioned, or have a broken agent." `
                -AffectedCount $staleDevices.Count `
                -AffectedItems @($staleItems)
        )
    }

    return @(
        New-NinjaFinding `
            -Category 'DeviceHygiene' `
            -Severity 'Info' `
            -Title    'No stale devices found' `
            -Detail   "All devices have checked in within the past $staleDays days."
    )
}
