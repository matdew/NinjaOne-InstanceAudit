function Invoke-UnusedPoliciesCheck {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [hashtable]$AuthContext
    )

    Write-Verbose 'Running check: UnusedPolicies'

    $policies = Invoke-NinjaInternalApi -AuthContext $AuthContext -Endpoint 'policy/list?nodeClassGroup=RMM'

    if ($null -eq $policies) {
        return @(
            New-NinjaFinding `
                -Category 'PolicyHealth' `
                -Severity 'Info' `
                -Title    'Unused Policies check skipped - internal API not configured' `
                -Detail   'This check requires ShardBaseUrl and SessionKey. Call Add-NinjaSessionKey before running Invoke-NinjaOneAudit to enable it.'
        )
    }

    $policies = @($policies)

    if ($policies.Count -eq 0) {
        return @(
            New-NinjaFinding `
                -Category 'PolicyHealth' `
                -Severity 'Info' `
                -Title    'No policies found' `
                -Detail   'No RMM policies were returned. This may indicate a permissions issue or an empty instance.'
        )
    }

    $unusedPolicies = @($policies | Where-Object {
        $_.clientCount -eq 0 -and (-not $_.devices -or $_.devices.Count -eq 0)
    })

    if ($unusedPolicies.Count -gt 0) {
        $unusedItems = @($unusedPolicies | ForEach-Object { $_.name })

        return @(
            New-NinjaFinding `
                -Category      'PolicyHealth' `
                -Severity      'Warning' `
                -Title         'Unused policies' `
                -Detail        "$($unusedPolicies.Count) policy/policies exist but are not assigned to any organisation or device. These add clutter to the policy list and may confuse administrators." `
                -AffectedCount $unusedPolicies.Count `
                -AffectedItems $unusedItems
        )
    }

    return @(
        New-NinjaFinding `
            -Category 'PolicyHealth' `
            -Severity 'Info' `
            -Title    'No unused policies found' `
            -Detail   "All $($policies.Count) RMM policies are assigned to at least one organisation or device."
    )
}
