<#
.SYNOPSIS
    Unix-like touch command — creates empty files or updates timestamps on existing ones.

.DESCRIPTION
    Creates new empty files if they do not exist, or updates the
    LastWriteTime and LastAccessTime on existing files to the current
    date/time (or a custom reference time).

    Supports writing content to files on creation or overriding existing
    file content via the -Content and -Override parameters.

.PARAMETER Path
    One or more file paths to touch. Accepts multiple values.

.PARAMETER ReferenceTime
    Custom timestamp to apply. Default: current date and time.

.PARAMETER Content
    Optional string content to write into the file. If the file does not
    exist, it is created with this content. If the file exists, the
    -Override switch must be used to replace its content.

.PARAMETER Override
    When combined with -Content, overwrites the content of an existing
    file. Has no effect when used without -Content.

.EXAMPLE
    touch newfile.txt

    Create an empty file named newfile.txt.

.EXAMPLE
    touch file1.txt, file2.txt

    Create or update timestamps on multiple files at once.

.EXAMPLE
    touch -Path "log.txt" -ReferenceTime (Get-Date "2024-01-01")

    Set the timestamps of log.txt to January 1, 2024.

.EXAMPLE
    touch -Path "readme.md" -Content "# My Project"

    Create readme.md with the specified markdown content.

.EXAMPLE
    touch -Path "config.ps1" -Content '$setting = "enabled"' -Override

    Overwrite the content of an existing config.ps1 file.

.NOTES
    Version: 1.1 - Added Content & Override Parameters
    Author: Anen
#>

function touch {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string[]]$Path,

        [datetime]$ReferenceTime = (Get-Date),

        [string]$Content = "",

        [switch]$Override
    )

    try {
        foreach ($p in $Path) {

            if (Test-Path $p) {

                if ($Override -and $PSBoundParameters.ContainsKey('Content')) {
                    Set-Content -Path $p -Value $Content -NoNewline
                }

                $item = Get-Item $p
                $item.LastWriteTime = $ReferenceTime
                $item.LastAccessTime = $ReferenceTime
            }
            else {

                $parent = Split-Path $p -Parent
                if ($parent -and -not (Test-Path $parent)) {
                    New-Item -Path $parent -ItemType Directory -Force | Out-Null
                }

                if ($PSBoundParameters.ContainsKey('Content')) {
                    Set-Content -Path $p -Value $Content -NoNewline
                }
                else {
                    New-Item -Path $p -ItemType File -Force | Out-Null
                }

                $item = Get-Item $p
                $item.LastWriteTime = $ReferenceTime
                $item.LastAccessTime = $ReferenceTime
            }
        }
    }
    catch {
        Write-Error "An error occurred while processing the path '$p': $_"
    }
}