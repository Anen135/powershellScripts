<#
.SYNOPSIS
    Cleans the user PATH environment variable from non-existent paths.

.DESCRIPTION
    Creates a backup of PATH, removes only non-existent directories,
    updates the value in the registry, and reports the list of removed paths.
    If no changes are made — exits without updating PATH.

.NOTES
    Version: 2.0
    Author: Anen
#>

[CmdletBinding()]
param()

begin {
    $regPath   = "HKCU:\Environment"
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = Join-Path $env:USERPROFILE "Desktop\user-path-backup-$timestamp.txt"

    Write-Verbose "Registry path: $regPath"
    Write-Verbose "Backup path: $backupPath"
}

process {
    try {
        if (-not (Test-Path $regPath)) {
            throw "Registry key $regPath does not exist."
        }

        $oldPath = (Get-ItemProperty -Path $regPath -Name Path -ErrorAction Stop).Path
        if ([string]::IsNullOrWhiteSpace($oldPath)) {
            Write-Warning "PATH variable is missing or empty."
            return
        }

        $pathList    = $oldPath -split ';'
        $validPaths  = @()
        $invalidPaths = @()

        foreach ($path in $pathList) {
            if ([string]::IsNullOrWhiteSpace($path)) { continue }

            $trimmed = $path.Trim().TrimEnd('\')

            if (Test-Path $trimmed) {
                $validPaths += $trimmed
            } else {
                $invalidPaths += $path
            }
        }

        if ($invalidPaths.Count -eq 0) {
            Write-Output "All paths in PATH exist. No changes required."
            return
        }

        # First compute the new PATH
        $newPath = $validPaths -join ';'

        # Then create backup object (now $newPath exists)
        $backupObject = [PSCustomObject]@{
            Timestamp     = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            OriginalPath  = $oldPath
            OriginalPaths = $pathList
            ValidPaths    = $validPaths
            InvalidPaths  = $invalidPaths
            NewPath       = $newPath
            RemovedCount  = $invalidPaths.Count
        }

        # Save JSON backup
        $backupPath = Join-Path $env:USERPROFILE "Desktop\user-path-backup-$timestamp.json"
        $backupObject | ConvertTo-Json -Depth 10 | Out-File -FilePath $backupPath -Encoding UTF8 -Force

        Write-Output "Backup saved to JSON: $backupPath"
        Write-Output "Removed non-existent paths: $($invalidPaths.Count)"

        # Update registry
        Set-ItemProperty -Path $regPath -Name Path -Value $newPath -ErrorAction Stop
        Write-Output "PATH variable successfully updated."
    }
    catch {
        Write-Error "Error updating PATH: $($_.Exception.Message)"
        exit 1
    }
}

end {
    Write-Verbose "Script execution completed."
}