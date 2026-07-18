<#
.SYNOPSIS
    Enhanced alternative to the DIR command for PowerShell.

.DESCRIPTION
    The script displays a list of files and folders in the specified directory with support for most
    keys from the original DIR command (Windows). Supports attribute filters,
    sorting, recursive search, owner display, lower case, output formatting,
    and size calculation.

.PARAMETER Path
    Directory whose contents to display.

.PARAMETER Unit
    Size unit (MB or GB). Default: MB.

.PARAMETER Recurse
    Equivalent of /S switch. Recursive traversal of all subdirectories.

.PARAMETER BareFormat
    Equivalent of /B switch. Output only file and folder names without additional data.

.PARAMETER LowerCase
    Equivalent of /L switch. Output file and folder names in lower case.

.PARAMETER Pause
    Equivalent of /P switch. Pause after each line waiting for key press.

.PARAMETER Sort
    Equivalent of /O switch. Sort order:
      - N: by name (alphabetically)
      - S: by size (smallest first)
      - E: by extension (alphabetically)
      - D: by date (oldest first)
      - G: folders first

.PARAMETER Owner
    Equivalent of /Q switch. Display owner of each file or directory.

.PARAMETER TimeField
    Equivalent of /T switch. Time field for sorting:
      - C: creation date
      - A: last access date
      - W: last write date (default)

.PARAMETER FourDigitYear
    Equivalent of /4 switch. Use 4-digit year format in output.

.PARAMETER Attributes
    Equivalent of /A switch. Filter by file attributes:
      - D: directories
      - R: read-only
      - H: hidden
      - A: archive
      - S: system

.EXAMPLE
    PS> .\Get-DirSize.ps1 -Path "C:\Temp"
    Displays list of files and folders in `C:\Temp` with sizes in megabytes.

.EXAMPLE
    PS> .\Get-DirSize.ps1 -Path "C:\Windows" -Unit GB -Recurse
    Displays all files and folders in `C:\Windows` and subdirectories, sizes in gigabytes.

.EXAMPLE
    PS> .\Get-DirSize.ps1 -Path "C:\Data" -BareFormat -LowerCase
    Displays list of files and folders in `C:\Data` with only names in lower case.

.EXAMPLE
    PS> .\Get-DirSize.ps1 -Path "C:\Projects" -Owner -Sort D
    Displays list of files and folders in `C:\Projects` with owner information
    and sorting by creation date.

.NOTES
    Version: 3.0
    Author: Anen
    License: MIT
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({Test-Path $_ -PathType Container})]
    [string]$Path,

    [ValidateSet("MB","GB")]
    [string]$Unit = "MB",

    [switch]$Recurse,           # /S
    [switch]$BareFormat,        # /B
    [switch]$LowerCase,         # /L
    [switch]$Pause,             # /P
    [ValidateSet("N","S","E","D","G")]
    [string]$Sort = "N",       # /O
    [switch]$Owner,             # /Q
    [ValidateSet("C","A","W")]
    [string]$TimeField = "W",  # /T
    [switch]$FourDigitYear,     # /4
    [string]$Attributes         # /A
)

begin {
    Write-Verbose "Initializing parameters..."
    $divider = if ($Unit -eq "GB") { 1GB } else { 1MB }
    $items = Get-ChildItem -Path $Path -Force -ErrorAction Stop

    if ($Attributes) {
        $items = $items | Where-Object {
            $match = $true
            foreach ($attr in $Attributes.ToCharArray()) {
                switch ($attr) {
                    'D' { if (-not $_.PSIsContainer) { $match = $false } }
                    'R' { if (-not $_.Attributes.ToString().Contains('ReadOnly')) { $match = $false } }
                    'H' { if (-not $_.Attributes.ToString().Contains('Hidden')) { $match = $false } }
                    'A' { if (-not $_.Attributes.ToString().Contains('Archive')) { $match = $false } }
                    'S' { if (-not $_.Attributes.ToString().Contains('System')) { $match = $false } }
                }
            }
            $match
        }
    }
}

process {
    foreach ($item in $items) {
        try {
            $size = 0
            if ($item.PSIsContainer) {
                if ($Recurse) {
                    $size = (Get-ChildItem -Path $item.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                }
            } else {
                $size = $item.Length
            }

            $name = if ($LowerCase) { $item.Name.ToLower() } else { $item.Name }

            $obj = [PSCustomObject]@{
                Name = $name
                Type = if ($item.PSIsContainer) { 'Folder' } else { 'File' }
                Size = "{0:N2}" -f ($size / $divider)
                Unit = $Unit
            }

            if ($Owner) {
                $obj | Add-Member -NotePropertyName Owner -NotePropertyValue (Get-Acl $item.FullName).Owner
            }

            if ($BareFormat) {
                Write-Output $obj.Name
            } else {
                Write-Output $obj
            }

            if ($Pause) { Read-Host "Press Enter to continue..." }
        }
        catch {
            Write-Warning "Error processing '$($item.FullName)': $($_.Exception.Message)"
        }
    }
}