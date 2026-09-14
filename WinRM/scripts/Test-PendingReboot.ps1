$paths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
)
$pendingFileRename = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
[pscustomobject]@{
    ComputerName = $env:COMPUTERNAME
    PendingReboot = (@($paths | Where-Object { Test-Path $_ }).Count -gt 0 -or $null -ne $pendingFileRename)
    Reasons = @($paths | Where-Object { Test-Path $_ }) + $(if ($null -ne $pendingFileRename) { 'PendingFileRenameOperations' })
}
