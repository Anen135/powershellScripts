<#
.SYNOPSIS
    Gets the SSID and password of the current Wi-Fi network.

.DESCRIPTION
    Uses netsh to determine the active Wi-Fi connection,
    then outputs the network name (SSID) and its password if available.

.NOTES
    Version: 2.4
    Author: Anen
#>

[CmdletBinding()]
param()

begin {
    # Check for administrator privileges
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal   = New-Object Security.Principal.WindowsPrincipal($currentUser)
    $isAdmin     = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-Warning "Some data (Wi-Fi password) may not be available without administrator rights."
    }

    # Runs netsh with forced UTF-8 output (chcp 65001) redirected to a temp file,
    # then reads that file back as UTF-8.
    # Capturing netsh output directly through the pipeline mis-decodes Cyrillic on
    # Russian (CP866) systems, so the regex never matched. File-based capture fixes it.
    function Invoke-NetshUtf8 {
        param([string]$Arguments)
        $tmp = Join-Path $env:TEMP ("netsh_" + [guid]::NewGuid().ToString('N') + ".txt")
        try {
            & cmd.exe /d /c "chcp 65001>nul & netsh $Arguments> `"$tmp`" 2>nul"
            if (Test-Path -LiteralPath $tmp) {
                Get-Content -LiteralPath $tmp -Encoding UTF8
            }
        }
        finally {
            if (Test-Path -LiteralPath $tmp) {
                Remove-Item -LiteralPath $tmp -Force
            }
        }
    }
}

process {
    try {
        # Get current connection SSID
        $wifiName = Invoke-NetshUtf8 'wlan show interfaces' |
                    Where-Object { $_ -match '^\s*SSID\s*:\s*(.+)$' } |
                    ForEach-Object { ($_ -split ':', 2)[1].Trim() } |
                    Select-Object -First 1

        if (-not $wifiName) {
            Write-Warning "Active Wi-Fi connection not found."
            return
        }

        Write-Output "Current Wi-Fi network: $wifiName"

        # Get profile with password. With UTF-8 output the label is English "Key Content".
        $profileInfo = Invoke-NetshUtf8 "wlan show profile name=`"$wifiName`" key=clear"

        # Search for password: process each line separately
        $password = $null
        foreach ($line in $profileInfo) {
            if ($line -match '(?:Key Content|Содержимое ключа)\s*:\s*(.+)') {
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