@{
    RootModule = 'WinRM.Manager.psm1'
    ModuleVersion = '1.1.0'
    GUID = '258da962-d479-4836-95de-28f3a941c05d'
    Author = 'Anen'
    Description = 'Persistent inventory, grouping, filtering and audit helpers for WinRM TUI.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-WinRMDefaultStorePath',
        'Initialize-WinRMStore',
        'Get-WinRMManagerConfig',
        'Save-WinRMManagerConfig',
        'Get-WinRMInventory',
        'Save-WinRMInventory',
        'Merge-WinRMDiscoveryResult',
        'Select-WinRMPreferredEndpoint',
        'ConvertTo-WinRMDiscoveryPattern',
        'Test-WinRMBlacklist',
        'Find-WinRMInventory',
        'Set-WinRMHostGroups',
        'Set-WinRMHostTags',
        'Add-WinRMBlacklistEntry',
        'Write-WinRMAuditEvent',
        'Get-WinRMAuditEvent',
        'Import-WinRMInventoryCsv',
        'Export-WinRMInventoryCsv'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{ PSData = @{ Tags = @('WinRM', 'TUI', 'Inventory', 'Administration') } }
}
