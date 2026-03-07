#Requires -Version 5.1
#Requires -Modules NinjaOne

# Load infrastructure
Get-ChildItem -Path $PSScriptRoot\Private\*.ps1 -ErrorAction Stop |
    ForEach-Object { . $_.FullName }

# Load audit checks (auto-discovery: functions named Invoke-*Check are registered automatically)
Get-ChildItem -Path $PSScriptRoot\Checks\*.ps1 -ErrorAction Stop |
    ForEach-Object { . $_.FullName }
