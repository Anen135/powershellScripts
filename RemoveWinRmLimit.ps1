#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Disables the Windows restriction on remote logon by local accounts with
    blank passwords.

.DESCRIPTION
    Sets the registry value 'LimitBlankPasswordUse' to 0 under
    HKLM:\SYSTEM\CurrentControlSet\Control\Lsa. This allows local accounts
    with blank passwords to be used for remote logon (for example, via WinRM).

    Requires Administrator privileges.

.EXAMPLE
    .\RemoveWinRmLimit.ps1

    Disables the blank-password restriction on the local machine.

.EXAMPLE
    .\RemoveWinRmLimit.ps1 -Verbose

    Disables the blank-password restriction and displays detailed progress
    information.

.NOTES
    Version: 1.0
    Author: Anen
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

begin {
    Write-Verbose "Initializing parameters..."
}

process {
    try {
        $RegPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"

        Write-Verbose "Setting '$RegPath\LimitBlankPasswordUse' to 0"

        Set-ItemProperty `
            -Path $RegPath `
            -Name 'LimitBlankPasswordUse' `
            -Value 0 `
            -Type DWord `
            -ErrorAction Stop

        Write-Output "Blank-password restriction for local accounts disabled."
    }
    catch {
        Write-Error "Error disabling blank-password restriction: $($_.Exception.Message)"
        throw
    }
}

end {
    Write-Verbose "Script execution completed."
}