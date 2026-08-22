<#
.SYNOPSIS
    Merges text files from a specified folder into a single file.

.DESCRIPTION
    The script reads text files from the specified folder,
    adds a delimiter with the filename/path before the content of each file,
    and writes everything to a single output file.

    Supports recursive directory scanning with -Recurse.

    Supports filtering:
    -Filter      : wildcard patterns (*.txt, *.cs, log_??.csv)
    -RegexFilter : regular expressions (^report_.*\.txt$)

.PARAMETER InputFolder
    Path to the folder containing files to merge.

.PARAMETER OutputFile
    Path to the output file where the result will be written.

.PARAMETER Filter
    Wildcard pattern for filtering filenames.
    Example: "*.txt", "*.cs", "log_??.csv"

.PARAMETER RegexFilter
    Regular expression for filtering filenames.
    Example: "^report_.*\.txt$", "^\d{4}-\d{2}-\d{2}_.*\.log$"

.PARAMETER Recurse
    Recursively searches all subdirectories inside InputFolder.

.EXAMPLE
    PS> .\Merge-Files.ps1 -InputFolder ".\merger" -OutputFile ".\main.txt"

.EXAMPLE
    PS> .\Merge-Files.ps1 -InputFolder ".\Project" -Recurse -OutputFile ".\main.txt"

.EXAMPLE
    PS> .\Merge-Files.ps1 -InputFolder ".\Project" -Recurse -Filter "*.cs" -OutputFile ".\AllScripts.txt"

.EXAMPLE
    PS> .\Merge-Files.ps1 -InputFolder ".\data" -Recurse -RegexFilter "^.*\.json$" -OutputFile ".\data.txt"

.NOTES
    Version: 3.0
    Author: Anen
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$InputFolder = ".\merger",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputFile = ".\main.txt",

    [Parameter(Mandatory = $false)]
    [string]$Filter,

    [Parameter(Mandatory = $false)]
    [string]$RegexFilter,

    [Parameter(Mandatory = $false)]
    [switch]$Recurse
)

begin {
    Write-Verbose "Initializing parameters..."

    try {
        if (-not (Test-Path $InputFolder -PathType Container)) {
            throw "Folder '$InputFolder' does not exist."
        }

        # Convert paths to absolute paths.
        $InputFolderFullPath = [System.IO.Path]::GetFullPath(
            (Resolve-Path $InputFolder).Path
        )

        $OutputFileFullPath = [System.IO.Path]::GetFullPath(
            $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFile)
        )

        if (Test-Path $OutputFileFullPath) {
            Write-Verbose "Removing existing file '$OutputFileFullPath'..."
            Remove-Item -Path $OutputFileFullPath -Force -ErrorAction Stop
        }

        # Create output directory if necessary.
        $OutputDirectory = Split-Path -Parent $OutputFileFullPath

        if (
            $OutputDirectory -and
            -not (Test-Path $OutputDirectory -PathType Container)
        ) {
            Write-Verbose "Creating output directory '$OutputDirectory'..."
            New-Item `
                -ItemType Directory `
                -Path $OutputDirectory `
                -Force `
                -ErrorAction Stop | Out-Null
        }

        # Validate regular expression.
        if ($RegexFilter) {
            try {
                $null = [regex]::New($RegexFilter)
            }
            catch {
                throw "Invalid regular expression '$RegexFilter': $($_.Exception.Message)"
            }
        }
    }
    catch {
        Write-Error "Initialization error: $($_.Exception.Message)"
        throw
    }
}

process {
    try {
        # Build Get-ChildItem parameters.
        $FilesQuery = @{
            Path        = $InputFolderFullPath
            File        = $true
            ErrorAction = 'Stop'
        }

        if ($Filter) {
            $FilesQuery['Filter'] = $Filter
        }

        if ($Recurse) {
            $FilesQuery['Recurse'] = $true
        }

        $Files = Get-ChildItem @FilesQuery |

            # Do not merge the output file into itself.
            Where-Object {
                $_.FullName -ne $OutputFileFullPath
            }

        # Apply regex to file name.
        if ($RegexFilter) {
            $Files = $Files |
                Where-Object {
                    $_.Name -match $RegexFilter
                }
        }

        # Sort for deterministic output.
        $Files = @(
            $Files |
            Sort-Object FullName
        )

        if ($Files.Count -eq 0) {
            $FilterInfo = ""

            if ($Filter) {
                $FilterInfo += " with filter '$Filter'"
            }

            if ($RegexFilter) {
                $FilterInfo += " with regex '$RegexFilter'"
            }

            if ($Recurse) {
                $FilterInfo += " recursively"
            }

            Write-Warning "No files found in folder '$InputFolder'$FilterInfo."
            return
        }

        foreach ($File in $Files) {
            try {
                # Get relative path from the root directory.
                $RelativePath = [System.IO.Path]::GetRelativePath(
                    $InputFolderFullPath,
                    $File.FullName
                )

                # Normalize separators for nicer output.
                $RelativePath = $RelativePath -replace '\\', '/'

                # Delimiter.
                "%%=============$RelativePath========%%" |
                    Out-File `
                        -FilePath $OutputFileFullPath `
                        -Encoding UTF8 `
                        -Append `
                        -ErrorAction Stop

                # File content.
                Get-Content `
                    -Path $File.FullName `
                    -ErrorAction Stop |
                    Out-File `
                        -FilePath $OutputFileFullPath `
                        -Encoding UTF8 `
                        -Append `
                        -ErrorAction Stop

                # Empty line between files.
                "" |
                    Out-File `
                        -FilePath $OutputFileFullPath `
                        -Encoding UTF8 `
                        -Append

                Write-Verbose "File '$RelativePath' added."
            }
            catch {
                Write-Warning "Error processing file '$($File.FullName)': $($_.Exception.Message)"
                continue
            }
        }

        Write-Output "Merged $($Files.Count) files from '$InputFolder' into '$OutputFile'."
    }
    catch {
        Write-Error "Processing error: $($_.Exception.Message)"
        throw
    }
}

end {
    Write-Verbose "Script execution completed."
}