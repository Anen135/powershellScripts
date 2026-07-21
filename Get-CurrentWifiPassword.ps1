<#
.SYNOPSIS
    Gets the SSID and password of the current Wi-Fi network.

.DESCRIPTION
    Uses netsh to determine the active Wi-Fi connection,
    then outputs the network name (SSID) and its password if available.

.NOTES
    Version: 2.3
    Author: Anen
#>

[CmdletBinding()]
param()

begin {
    # CRITICALLY IMPORTANT: Set code page 866 for correct reading of netsh output
    [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(866)
    $OutputEncoding = [System.Text.Encoding]::GetEncoding(866)

    # Check for administrator privileges
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal   = New-Object Security.Principal.WindowsPrincipal($currentUser)
    $isAdmin     = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-Warning "Some data (Wi-Fi password) may not be available without administrator rights."
    }
}

process {
    try {
        # Get current connection SSID
        $wifiName = (netsh wlan show interfaces) -match '^\s*SSID\s*:\s*(.+)$' |
                    ForEach-Object { ($_ -split ':', 2)[1].Trim() }

        if (-not $wifiName) {
            Write-Warning "Active Wi-Fi connection not found."
            return
        }

        Write-Output "Current Wi-Fi network: $wifiName"

        # Get profile with password (output comes in CP866)
        $profileInfo = netsh wlan show profile name="$wifiName" key=clear

        # Search for password: process each line separately
        $password = $null
        foreach ($line in $profileInfo) {
            if ($line -match '(?:Содержимое ключа|Key Content)\s*:\s*(.+)') {
                $password = $matches[1].Trim()
                break
            }
        }

        if ($password) {
            Write-Output "Password: $password"
        }
        else {
            Write-Output "Password not found or network is not secured."
        }
    }
    catch {
        Write-Error "Error getting Wi-Fi information: $($_.Exception.Message)"
    }
}

end {
    Write-Verbose "Script completed."
}