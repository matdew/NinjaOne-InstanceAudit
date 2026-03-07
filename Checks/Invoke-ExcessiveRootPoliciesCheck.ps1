function Invoke-ExcessiveRootPoliciesCheck {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [hashtable]$AuthContext
    )

    Write-Verbose 'Running check: ExcessiveRootPolicies'

    $policies = @(Get-NinjaOnePolicies)

    if ($policies.Count -eq 0) {
        return @(
            New-NinjaFinding `
                -Category 'PolicyHealth' `
                -Severity 'Info' `
                -Title    'No policies found' `
                -Detail   'No RMM policies were returned. This may indicate a permissions issue or an empty instance.'
        )
    }

    $rootThreshold = 5
    $rootPolicies  = @($policies | Where-Object { -not $_.parentPolicyId })
    $byNodeClass   = $rootPolicies | Group-Object -Property nodeClass

    $findings = @()
    foreach ($group in $byNodeClass) {
        if ($group.Count -gt $rootThreshold) {
            $findings += New-NinjaFinding `
                -Category      'PolicyHealth' `
                -Severity      'Warning' `
                -Title         "Excessive root-level policies: $($group.Name)" `
                -Detail        "$($group.Name) has $($group.Count) root-level policies (no parent policy). More than $rootThreshold suggests the policy inheritance hierarchy is not being used. Consider restructuring under a base policy to share common configuration." `
                -AffectedCount $group.Count `
                -AffectedItems @($group.Group | ForEach-Object { $_.name })
        }
    }

    if ($findings.Count -gt 0) {
        return $findings
    }

    return @(
        New-NinjaFinding `
            -Category 'PolicyHealth' `
            -Severity 'Info' `
            -Title    'No excessive root-level policies found' `
            -Detail   "No node class has more than $rootThreshold root-level policies."
    )
}
