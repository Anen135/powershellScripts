<#
.SYNOPSIS
    Merges all text files from a specified folder into a single file.

.DESCRIPTION
    The script reads all text files from the specified folder,
    adds a delimiter with the filename before the content of each file,
    and writes everything to a single output file.
    Works only with text files (UTF-8 encoding).
    
    Supports filtering:
    -Filter     : wildcard patterns (*.txt, log_??.csv)
    -RegexFilter: regular expressions (^report_.*\.txt$)

.PARAMETER InputFolder
    Path to the folder containing files to merge.

.PARAMETER OutputFile
    Path to the output file where the result will be written.

.PARAMETER Filter
    Wildcard pattern for filtering filenames (similar to dir -Filter).
    Example: "*.txt", "log_??.csv"

.PARAMETER RegexFilter
    Regular expression for filtering filenames.
    Example: "^report_.*\.txt$", "^\d{4}-\d{2}-\d{2}_.*\.log$"

.EXAMPLE
    PS> .\Merge-Files.ps1 -InputFolder ".\merger" -OutputFile ".\main.txt"

.EXAMPLE
    PS> .\Merge-Files.ps1 -InputFolder ".\logs" -Filter "*.log" -OutputFile ".\all_logs.txt"

.EXAMPLE
    PS> .\Merge-Files.ps1 -InputFolder ".\data" -RegexFilter "^2024-.*\.txt$" -OutputFile ".\2024_data.txt"

.NOTES
    Version: 2.1
    Author: Anen
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateScript({Test-Path $_ -PathType Container})]
    [string]$InputFolder = ".\merger",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputFile = ".\main.txt",
    
    [Parameter(Mandatory = $false)]
    [string]$Filter,
    
    [Parameter(Mandatory = $false)]
    [string]$RegexFilter
)

begin {
    Write-Verbose "Initializing parameters..."
    try {
        if (-not (Test-Path $InputFolder -PathType Container)) {
            throw "Folder '$InputFolder' does not exist."
        }

        if (Test-Path $OutputFile) {
            Write-Verbose "Removing existing file '$OutputFile'..."
            Remove-Item -Path $OutputFile -Force -ErrorAction Stop
        }
        
        # Validate regular expression if provided
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
        # Base file query
        $FilesQuery = @{
            Path = $InputFolder
            File = $true
            ErrorAction = 'Stop'
        }
        
        # Add -Filter if specified (wildcard patterns only)
        if ($Filter) {
            $FilesQuery['Filter'] = $Filter
        }
        
        $Files = Get-ChildItem @FilesQuery |
                 Where-Object { $_.Name -ne [System.IO.Path]::GetFileName($OutputFile) }
        
        # Apply regular expression filter if specified
        if ($RegexFilter) {
            $Files = $Files | Where-Object { $_.Name -match $RegexFilter }
        }

        if (-not $Files) {
            Write-Warning "No files found in folder '$InputFolder' to merge$(
                if($Filter){" with filter '$Filter'"}
                if($RegexFilter){" with regex '$RegexFilter'"}
            )."
            return
        }

        foreach ($File in $Files) {
            try {
                # Delimiter
                "%%=============$($File.Name)========%%" | Out-File -FilePath $OutputFile -Encoding UTF8 -Append -ErrorAction Stop

                # File content
                Get-Content -Path $File.FullName -ErrorAction Stop | 
                    Out-File -FilePath $OutputFile -Encoding UTF8 -Append -ErrorAction Stop

                Write-Verbose "File '$($File.Name)' added."
            }
            catch {
                Write-Warning "Error processing file '$($File.FullName)': $($_.Exception.Message)"
                continue
            }
        }

        Write-Output "All files from '$InputFolder' have been merged into '$OutputFile'."
    }
    catch {
        Write-Error "Processing error: $($_.Exception.Message)"
        throw
    }
}

end {
    Write-Verbose "Script execution completed."
}