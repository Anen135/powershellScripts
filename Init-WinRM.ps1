#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Configures WinRM for PowerShell Remoting.

.DESCRIPTION
    Prepares a Windows machine for PowerShell Remoting:
      1. Disables the blank-password restriction for local accounts.
      2. Sets all active network profiles to Private.
      3. Enables PowerShell Remoting (WinRM) and configures the WinRM
         service to start automatically.

    Requires Administrator privileges.

.EXAMPLE
    .\Init-WinRM.ps1

    Configures WinRM on the local machine.

.EXAMPLE
    .\Init-WinRM.ps1 -Verbose

    Configures WinRM and displays detailed progress information.

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
        Write-Host "=== Configuring WinRM ===" -ForegroundColor Cyan

        # Step 1: Allow remote use of local accounts with blank passwords.
        Write-Host "[1/3] Disabling blank-password restriction..."
        Write-Verbose "Setting 'LimitBlankPasswordUse' to 0 in HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"

        Set-ItemProperty `
            -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" `
            -Name "LimitBlankPasswordUse" `
            -Value 0 `
            -Type DWord `
            -ErrorAction Stop

        # Step 2: Switch active network interfaces to the Private profile.
        Write-Host "[2/3] Setting network profile to Private..."
        Write-Verbose "Changing the network category of active interfaces to Private"

        Get-NetConnectionProfile |
            Where-Object { $_.IPv4Connectivity -ne 'Disconnected' } |
            Set-NetConnectionProfile -NetworkCategory Private

        # Step 3: Enable PowerShell Remoting / WinRM.
        Write-Host "[3/3] Enabling PowerShell Remoting..."
        Write-Verbose "Running Enable-PSRemoting -Force"

        Enable-PSRemoting -Force -ErrorAction Stop

        Write-Verbose "Setting the WinRM service startup type to Automatic"
        Set-Service -Name WinRM -StartupType Automatic -ErrorAction Stop

        Write-Verbose "Starting the WinRM service"
        Start-Service -Name WinRM -ErrorAction Stop

        Write-Host ""
        Write-Host "=== Done ===" -ForegroundColor Green
        Write-Host "Computer : $env:COMPUTERNAME"
        Write-Host "WinRM    : $((Get-Service WinRM).Status)"
        Write-Host ""

        Get-NetConnectionProfile |
            Select-Object Name, InterfaceAlias, NetworkCategory, IPv4Connectivity

        Write-Host ""
        Test-WSMan localhost
    }
    catch {
        Write-Error "Error configuring WinRM: $($_.Exception.Message)"
        throw
    }
}

end {
    Write-Verbose "Script execution completed."
}