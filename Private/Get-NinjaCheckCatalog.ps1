function Get-NinjaCheckCatalog {
    <#
    .SYNOPSIS
    Builds an ordered catalog of all loaded Invoke-*Check audit functions.
    Adding a new audit check requires only dropping a .ps1 file in the Checks\ folder
    and re-importing the module - no catalog edit needed.
    #>
    $catalog = [ordered]@{}
    # Scope to this module to avoid accidentally registering third-party Invoke-*Check functions
    Get-Command -Name 'Invoke-*Check' -CommandType Function -Module 'NinjaOne-InstanceAudit' |
        Sort-Object Name |
        ForEach-Object {
            $fn        = $_.Name
            $checkName = $fn -replace '^Invoke-' -replace 'Check$'
            # Capture command reference in closure - avoids string-based scriptblock construction
            $cmdRef = Get-Command -Name $fn -Module 'NinjaOne-InstanceAudit'
            $catalog[$checkName] = { param($AuthContext) & $cmdRef -AuthContext $AuthContext }.GetNewClosure()
        }
    return $catalog
}
