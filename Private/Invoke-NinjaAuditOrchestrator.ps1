function Invoke-NinjaAuditOrchestrator {
    <#
    .SYNOPSIS
        Iterates the check catalog, invokes each selected check,
        and collects all findings into a single array.
        Check errors are caught and converted to Critical findings so the
        report always completes even if individual checks fail.
    #>
    param (
        [Parameter(Mandatory)] [hashtable]$AuthContext,
        [Parameter(Mandatory)] [System.Collections.Specialized.OrderedDictionary]$Catalog,
        [string[]]$Checks
    )

    # Use List to avoid O(n^2) array allocation from += in loop
    $allFindings = [System.Collections.Generic.List[object]]::new()

    foreach ($entry in $Catalog.GetEnumerator()) {
        $checkName = $entry.Key

        # Skip if a Checks filter was provided and this check isn't in it
        if ($Checks -and $checkName -notin $Checks) {
            Write-Verbose "Skipping check: $checkName (not in -Checks filter)"
            continue
        }

        Write-Information "  Running check: $checkName" -InformationAction Continue

        try {
            $results = & $entry.Value -AuthContext $AuthContext
            if ($null -ne $results) {
                $allFindings.AddRange([object[]]@($results))
            }
        } catch {
            Write-Warning "Check '$checkName' failed: $($_.Exception.Message)"

            # Emit a Critical finding so the failure is visible in the report
            $allFindings.Add((New-NinjaFinding `
                -Category      $checkName `
                -Severity      'Critical' `
                -Title         "Check Execution Error: $checkName" `
                -Detail        $_.Exception.Message `
                -AffectedCount 0 `
                -AffectedItems @()))
        }
    }

    return $allFindings.ToArray()
}
