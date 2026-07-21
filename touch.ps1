<#
.SYNOPSIS
    Unix-like touch command — creates empty files or updates timestamps on existing ones.

.DESCRIPTION
    Creates new empty files if they do not exist, or updates the
    LastWriteTime and LastAccessTime on existing files to the current
    date/time (or a custom reference time).

.PARAMETER Path
    One or more file paths to touch. Accepts multiple values.

.PARAMETER ReferenceTime
    Custom timestamp to apply. Default: current date and time.

.EXAMPLE
    touch newfile.txt

.EXAMPLE
    touch file1.txt, file2.txt

.EXAMPLE
    touch -Path "log.txt" -ReferenceTime (Get-Date "2024-01-01")

.NOTES
    Version: 1.0
    Author: Anen
#>

function touch {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string[]]$Path,
        [datetime]$ReferenceTime = (Get-Date)
    )
    
    try {
        foreach ($p in $Path) {
            if (Test-Path $p) {
                $item = Get-Item $p
                $item.LastWriteTime = $ReferenceTime
                $item.LastAccessTime = $ReferenceTime
            } else {
                New-Item -Path $p -ItemType File -Force | Out-Null
            }
        }
    } catch {
        Write-Error "An error occurred while processing the path: $_"
    }
}