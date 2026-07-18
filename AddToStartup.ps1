<#
.SYNOPSIS
    Adds the specified application to Windows startup.

.DESCRIPTION
    The script registers the application path in the registry key HKCU:\Software\Microsoft\Windows\CurrentVersion\Run
    for automatic launch when the user logs in.

.PARAMETER AppName
    The name of the startup entry (registry key).

.PARAMETER AppPath
    Full path to the application executable file.

.NOTES
    Version: 2.0
    Author: Anen
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$AppName,

    [Parameter(Mandatory = $true)]
    [ValidateScript({Test-Path $_})]
    [string]$AppPath
)

begin {
    Write-Verbose "Initializing parameters..."
    $RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $CmdValue = "cmd /c `"$AppPath`""
}

process {
    try {
        Write-Verbose "Adding registry entry: $RegPath"
        Set-ItemProperty -Path $RegPath -Name $AppName -Value $CmdValue -ErrorAction Stop

        Write-Output "Entry '$AppName' successfully added to startup."

        Write-Verbose "Verifying result..."
        $Check = Get-ItemProperty -Path $RegPath -ErrorAction Stop | Select-Object -Property $AppName

        if ($Check.$AppName -eq $CmdValue) {
            Write-Output "Verification completed successfully:"
            Write-Output "Name: $AppName"
            Write-Output "Value: $($Check.$AppName)"
        }
        else {
            Write-Warning "Entry '$AppName' does not match the expected value."
        }
    }
    catch {
        Write-Error "Error adding entry to startup: $($_.Exception.Message)"
    }
}

end {
    Write-Verbose "Script execution completed."
}