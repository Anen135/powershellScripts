<#
.SYNOPSIS
    Removes the specified application from Windows startup.

.DESCRIPTION
    The script removes an entry from the registry key HKCU:\Software\Microsoft\Windows\CurrentVersion\Run,
    preventing the application from automatically starting when the user logs in.

.PARAMETER AppName
    The name of the startup entry (registry key) to be removed.

.NOTES
    Version: 2.0
    Author: Anen
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$AppName
)

begin {
    Write-Verbose "Initializing parameters..."
    $RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
}

process {
    try {
        Write-Verbose "Checking for entry '$AppName' in $RegPath..."
        $Exists = Get-ItemProperty -Path $RegPath -ErrorAction SilentlyContinue | Select-Object -Property $AppName

        if ($null -ne $Exists.$AppName) {
            Write-Verbose "Entry found. Removing..."
            Remove-ItemProperty -Path $RegPath -Name $AppName -ErrorAction Stop

            Write-Output "Entry '$AppName' removed from startup."

            Write-Verbose "Verifying result..."
            $Check = Get-ItemProperty -Path $RegPath -ErrorAction SilentlyContinue | Select-Object -Property $AppName
            if ($null -eq $Check.$AppName) {
                Write-Output "Confirmed: entry '$AppName' is absent from startup."
            }
            else {
                Write-Warning "Entry '$AppName' still exists after removal attempt."
            }
        }
        else {
            Write-Output "Entry '$AppName' not found in startup."
        }
    }
    catch {
        Write-Error "Error removing entry: $($_.Exception.Message)"
    }
}

end {
    Write-Verbose "Script execution completed."
}