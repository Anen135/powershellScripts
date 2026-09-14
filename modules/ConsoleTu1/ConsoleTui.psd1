@{
    RootModule = 'ConsoleTui.psm1'
    ModuleVersion = '1.0.0'
    GUID = '4a295aa3-e98c-48a4-92a2-187c0e661145'
    Author = 'Windows Restore Manager'
    Description = 'Reusable differential-rendering console TUI helpers for PowerShell.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Initialize-ConsoleTui',
        'Restore-ConsoleTui',
        'Get-ConsoleTuiWidth',
        'Get-ConsoleTuiHeight',
        'Format-ConsoleTuiText',
        'Format-ConsoleTuiColumns',
        'Start-ConsoleTuiFrame',
        'Write-ConsoleTuiLine',
        'Complete-ConsoleTuiFrame',
        'Clear-ConsoleTuiSurface',
        'Read-ConsoleTuiPrompt',
        'Confirm-ConsoleTui',
        'Show-ConsoleTuiMessage',
        'Get-ConsoleTuiKey',
        'Clear-ConsoleTuiInputBacklog',
        'Invoke-ConsoleTuiProcess'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('Console', 'TUI', 'PowerShell')
            LicenseUri = 'https://www.gnu.org/licenses/gpl-3.0.html'
            ProjectUri = 'https://github.com/Anen135/WindowsRestoreManager'
        }
    }
}
