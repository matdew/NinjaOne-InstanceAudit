function New-NinjaFinding {
    <#
    .SYNOPSIS Creates a standardized finding object for the audit report.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$Category,
        [Parameter(Mandatory)] [ValidateSet('Info', 'Warning', 'Critical')] [string]$Severity,
        [Parameter(Mandatory)] [string]$Title,
        [string]$Detail = '',
        [int]$AffectedCount = 0,
        [string[]]$AffectedItems = @()
    )

    # Auto-derive AffectedCount from items if caller left it at default 0
    if ($AffectedCount -eq 0 -and $AffectedItems.Count -gt 0) {
        $AffectedCount = $AffectedItems.Count
    }

    return [PSCustomObject]@{
        Category      = $Category
        Severity      = $Severity
        Title         = $Title
        Detail        = $Detail
        AffectedCount = $AffectedCount
        AffectedItems = $AffectedItems
    }
}
