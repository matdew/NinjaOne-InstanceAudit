function Invoke-BackupCoverageCheck {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [hashtable]$AuthContext
    )

    Write-Verbose 'Running check: BackupCoverage'

    # Requires internal API
    if (-not $AuthContext.ShardBaseUrl -or -not $AuthContext.SessionKey) {
        return @(
            New-NinjaFinding `
                -Category 'BackupHygiene' `
                -Severity 'Info' `
                -Title    'Backup Coverage check skipped - internal API not configured' `
                -Detail   'This check requires ShardBaseUrl and SessionKey. Call Add-NinjaSessionKey before running Invoke-NinjaOneAudit to enable it.'
        )
    }

    # Fetch backup-enabled devices via internal search API (single POST, much faster than iterating all devices)
    $searchBody   = '{"searchCriteria":[{"type":"ninja-backup-enabled","id":-1,"customFields":"{\"status\":\"enabled\"}"}]}'
    $searchResult = Invoke-NinjaInternalApi -AuthContext $AuthContext `
        -Endpoint 'search/runner?pageSize=1000&sortProperty=name&sortDirection=asc' `
        -Method POST -Body $searchBody

    if ($null -eq $searchResult) {
        return @(
            New-NinjaFinding `
                -Category 'BackupHygiene' `
                -Severity 'Info' `
                -Title    'Backup Coverage check skipped - internal API call failed' `
                -Detail   'The search/runner endpoint returned no response. Check ShardBaseUrl, SessionKey, and shard access.'
        )
    }

    $allDevices = if ($searchResult -and $searchResult.PSObject.Properties['results']) {
        @($searchResult.results)
    } elseif ($searchResult -is [System.Collections.IEnumerable]) {
        @($searchResult)
    } else { @() }

    if ($allDevices.Count -eq 0) {
        return @(
            New-NinjaFinding `
                -Category 'BackupHygiene' `
                -Severity 'Info' `
                -Title    'No backup-enabled devices found' `
                -Detail   'The search/runner query for backup-enabled devices returned no results. No backup coverage analysis to perform.'
        )
    }

    # Separate MacOS devices (not yet supported) from Windows devices
    $macClasses     = @('MAC_SERVER', 'MAC_WORKSTATION')
    $macDevices     = @($allDevices | Where-Object { $macClasses -contains $_.nodeClass })
    $windowsDevices = @($allDevices | Where-Object {
        $_.nodeClass -eq 'WINDOWS_WORKSTATION' -or $_.nodeClass -eq 'WINDOWS_SERVER'
    })

    $warningItems = [System.Collections.Generic.List[string]]::new()
    $infoItems    = [System.Collections.Generic.List[string]]::new()

    foreach ($dev in $windowsDevices) {
        $label = $dev.id.ToString()  # default; overwritten after node/<id> fetch
        try {
            # Get device display name and org from node/<id> - no separate org lookup needed
            $nodeData = Invoke-NinjaInternalApi -AuthContext $AuthContext -Endpoint "node/$($dev.id)"
            if ($null -eq $nodeData) { continue }

            $label = if ($nodeData.node -and $nodeData.node.displayName) {
                "$($nodeData.node.displayName) ($($nodeData.node.clientName))"
            } elseif ($dev.PSObject.Properties['displayName'] -and $dev.displayName) {
                $dev.displayName
            } else {
                $dev.id.ToString()
            }

            Write-Verbose "  Backup coverage: $label"

            $backupSection = $null
            if ($nodeData.node -and $nodeData.node.policyContent) {
                $backupSection = $nodeData.node.policyContent.backup
            }
            if ($null -eq $backupSection -or $null -eq $backupSection.backupPlans) { continue }

            # Extract enabled plans
            $enabledPlans = [System.Collections.Generic.List[object]]::new()
            foreach ($planEntry in $backupSection.backupPlans.PSObject.Properties) {
                $plan    = $planEntry.Value
                $enabled = if ($plan.type -eq 'arrowImage') { $plan.general.enabled } else { $plan.enabled }
                if ($enabled -eq $true) { $enabledPlans.Add($plan) }
            }
            if ($enabledPlans.Count -eq 0) { continue }  # no enabled backup plans - not in scope

            # Device has backup enabled - now fetch its volumes (per-device, only for backup devices)
            $volumeRows = @(Get-NinjaOneDeviceVolumes -deviceId $dev.id)
            $driveLetters = @(
                $volumeRows | Where-Object {
                    $_.letter -and
                    (-not $_.PSObject.Properties['driveType'] -or $_.driveType -ieq 'fixed')
                } | ForEach-Object {
                    ($_.letter -replace ':', '').ToUpper().Trim()
                } | Where-Object { $_ }
            )

            # Compute coverage
            $coveredDrives  = [System.Collections.Generic.HashSet[string]]::new()
            $excludedDrives = [System.Collections.Generic.HashSet[string]]::new()
            $arrowCoversAll = $false

            foreach ($plan in $enabledPlans) {
                switch ($plan.type) {
                    'arrowImage' {
                        $arrowCoversAll = $true
                        if ($plan.exclusions -and $plan.exclusions.volumesExclusions) {
                            foreach ($excl in $plan.exclusions.volumesExclusions) {
                                $letter = ($excl -replace ':', '').ToUpper().Trim()
                                if ($letter) { [void]$excludedDrives.Add($letter) }
                            }
                        }
                    }
                    'image' {
                        $imgType = if ($plan.image -and $plan.image.type) { $plan.image.type } else { '' }
                        if ($imgType -eq 'SYSTEM') {
                            [void]$coveredDrives.Add('C')
                        } elseif ($imgType -eq 'FULL') {
                            foreach ($d in $driveLetters) { [void]$coveredDrives.Add($d) }
                        }
                        if ($plan.image -and $plan.image.volumes) {
                            foreach ($vol in $plan.image.volumes) {
                                $letter = ($vol -replace ':', '').ToUpper().Trim()
                                if ($letter) { [void]$coveredDrives.Add($letter) }
                            }
                        }
                    }
                    'fileFolder' {
                        if ($plan.folders) {
                            if ($plan.folders.common -and @($plan.folders.common).Count -gt 0) {
                                [void]$coveredDrives.Add('C')
                            }
                            if ($plan.folders.paths) {
                                foreach ($p in $plan.folders.paths) {
                                    if ($p -match '^([A-Za-z]):') {
                                        [void]$coveredDrives.Add($matches[1].ToUpper())
                                    }
                                }
                            }
                        }
                    }
                }
            }

            # arrowImage covers all drives not in its exclusion list
            if ($arrowCoversAll) {
                foreach ($d in $driveLetters) {
                    if (-not $excludedDrives.Contains($d)) {
                        [void]$coveredDrives.Add($d)
                    }
                }
            }

            $uncoveredDrives = @($driveLetters | Where-Object { -not $coveredDrives.Contains($_) })
            if ($uncoveredDrives.Count -eq 0) { continue }

            $trulyMissing = @($uncoveredDrives | Where-Object { -not $excludedDrives.Contains($_) })
            $intentional  = @($uncoveredDrives | Where-Object { $excludedDrives.Contains($_) })

            if ($trulyMissing.Count -gt 0) {
                $warningItems.Add("$label - not covered: $($trulyMissing -join ', ')")
            }
            if ($intentional.Count -gt 0) {
                $infoItems.Add("$label - intentionally excluded: $($intentional -join ', ')")
            }

        } catch {
            Write-Warning "BackupCoverage: error processing device '$label': $($_.Exception.Message)"
        }
    }

    $findings = [System.Collections.Generic.List[object]]::new()

    if ($warningItems.Count -gt 0) {
        $findings.Add((New-NinjaFinding `
            -Category      'BackupHygiene' `
            -Severity      'Warning' `
            -Title         'Backup jobs do not cover all drives' `
            -Detail        "$($warningItems.Count) device(s) have fixed drives not covered by any enabled backup job. Review backup plan configurations to ensure all data drives are protected." `
            -AffectedCount $warningItems.Count `
            -AffectedItems @($warningItems)))
    }

    if ($infoItems.Count -gt 0) {
        $findings.Add((New-NinjaFinding `
            -Category      'BackupHygiene' `
            -Severity      'Info' `
            -Title         'Drives intentionally excluded from backup - verify these are correct' `
            -Detail        "$($infoItems.Count) device(s) have drives explicitly excluded from backup plans but not covered by any other job. Confirm these exclusions are intentional." `
            -AffectedCount $infoItems.Count `
            -AffectedItems @($infoItems)))
    }

    if ($macDevices.Count -gt 0) {
        $macNames = @($macDevices | ForEach-Object {
            if ($_.PSObject.Properties['displayName'] -and $_.displayName) { $_.displayName }
            elseif ($_.PSObject.Properties['systemName'] -and $_.systemName) { $_.systemName }
            else { $_.id.ToString() }
        })
        $findings.Add((New-NinjaFinding `
            -Category      'BackupHygiene' `
            -Severity      'Info' `
            -Title         'MacOS devices skipped - backup coverage check is Windows-only' `
            -Detail        "$($macDevices.Count) MacOS device(s) with backup enabled were found but skipped. MacOS backup (fileFolder only) requires different coverage logic not yet implemented." `
            -AffectedCount $macDevices.Count `
            -AffectedItems $macNames))
    }

    if ($warningItems.Count -eq 0 -and $infoItems.Count -eq 0) {
        $findings.Add((New-NinjaFinding `
            -Category 'BackupHygiene' `
            -Severity 'Info' `
            -Title    'All backed-up devices have full drive coverage' `
            -Detail   'All Windows devices with enabled backup plans have at least one job covering each fixed drive.'))
    }

    return $findings.ToArray()
}
