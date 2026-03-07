function Invoke-PendingApprovalCheck {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [hashtable]$AuthContext
    )

    Write-Verbose 'Running check: PendingApproval'

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

    $pendingDevices = @(Get-NinjaOneDevices -deviceFilter 'status=PENDING')

    if ($pendingDevices.Count -gt 0) {
        $pendingItems = $pendingDevices | ForEach-Object {
            if ($deviceMap.ContainsKey([int]$_.id)) { $deviceMap[[int]$_.id] } else { "Device ID $($_.id)" }
        }

        return @(
            New-NinjaFinding `
                -Category      'DeviceHygiene' `
                -Severity      'Warning' `
                -Title         'Devices pending approval' `
                -Detail        "$($pendingDevices.Count) device(s) are installed but not yet approved. Review and approve or reject each device." `
                -AffectedCount $pendingDevices.Count `
                -AffectedItems @($pendingItems)
        )
    }

    return @(
        New-NinjaFinding `
            -Category 'DeviceHygiene' `
            -Severity 'Info' `
            -Title    'No devices pending approval' `
            -Detail   'All devices have been reviewed - none are awaiting approval.'
    )
}
