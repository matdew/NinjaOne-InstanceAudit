@{
    RootModule        = 'NinjaOne-InstanceAudit.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'a10265e1-19dd-45d9-991a-9103ba6aeefc'
    Author            = 'Matthew Dewart'
    Description       = 'Audits a NinjaOne RMM instance and generates a self-contained HTML report.'
    PowerShellVersion = '5.1'
    RequiredModules   = @('NinjaOne')
    # FunctionsToExport = '*' is intentional: Invoke-*Check functions must be discoverable via
    # Get-Command -Module 'NinjaOne-InstanceAudit' for the auto-registration pattern in Orchestrator.ps1.
    # The sole public entry point is Invoke-NinjaOneAudit.
    FunctionsToExport = '*'
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags = @('NinjaOne', 'RMM', 'Audit')
        }
    }
}
