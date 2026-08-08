<#
.SYNOPSIS
    Interactive file selector with copy-to-current-directory functionality.

.DESCRIPTION
    Scans a directory (optionally recursive) and displays an interactive
    menu for selecting a file. The selected file is copied to the current
    working directory with automatic name conflict resolution.

.PARAMETER Path
    Directory to scan for files.

.PARAMETER Depth
    Maximum recursion depth.
    0 = unlimited depth.
    1 = files directly in the specified folder.
    2 = folder + one level of nested directories, etc.

.EXAMPLE
    .\Select-File.ps1 -Path "C:\Downloads"

    Scans C:\Downloads recursively and lets you pick a file to copy.

.EXAMPLE
    .\Select-File.ps1 -Path "C:\Projects" -Depth 2

    Scans C:\Projects and one level of subdirectories.

.NOTES
    Version: 1.1
    Author: Anen
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$Path,

    # 0 = unlimited depth, 1 = files directly in the folder, etc.
    [ValidateRange(0, 1000)]
    [int]$Depth = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-TargetFiles {
    param(
        [Parameter(Mandatory)]
        [string]$Root,

        [Parameter(Mandatory)]
        [int]$MaxDepth
    )

    Write-Verbose "Scanning directory: $Root"
    Write-Verbose "Maximum depth: $(if ($MaxDepth -eq 0) { 'unlimited' } else { $MaxDepth })"

    $options = @{
        LiteralPath = $Root
        File        = $true
        Force       = $true
        ErrorAction = 'SilentlyContinue'
    }

    if ($MaxDepth -gt 0) {
        $options.Depth = $MaxDepth - 1
    }

    Get-ChildItem @options |
        Sort-Object FullName
}

function Show-FileMenu {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo[]]$Files
    )

    Write-Verbose "Displaying file selection menu ($($Files.Count) files)"

    $index = 0

    try {
        [Console]::CursorVisible = $false

        while ($true) {
            Clear-Host

            Write-Host "Select a file" -ForegroundColor Cyan
            Write-Host "Up/Down - navigate    Enter - select    Esc - cancel"
            Write-Host ""

            for ($i = 0; $i -lt $Files.Count; $i++) {
                $file = $Files[$i]

                if ($i -eq $index) {
                    Write-Host (
                        " > {0}  [{1:N0} KB]" -f
                        $file.FullName,
                        ($file.Length / 1KB)
                    ) -ForegroundColor Black -BackgroundColor Gray
                }
                else {
                    Write-Host (
                        "   {0}  [{1:N0} KB]" -f
                        $file.FullName,
                        ($file.Length / 1KB)
                    )
                }
            }

            $key = [Console]::ReadKey($true)

            switch ($key.Key) {
                'UpArrow' {
                    if ($index -gt 0) {
                        $index--
                    }
                }

                'DownArrow' {
                    if ($index -lt ($Files.Count - 1)) {
                        $index++
                    }
                }

                'Enter' {
                    return $Files[$index]
                }

                'Escape' {
                    return $null
                }
            }
        }
    }
    finally {
        [Console]::CursorVisible = $true
    }
}

function Get-NonConflictingPath {
    param(
        [Parameter(Mandatory)]
        [string]$DestinationDirectory,

        [Parameter(Mandatory)]
        [string]$FileName
    )

    $candidate = Join-Path $DestinationDirectory $FileName

    if (-not (Test-Path -LiteralPath $candidate)) {
        Write-Verbose "No conflict, using: $candidate"
        return $candidate
    }

    Write-Verbose "Conflict detected for: $candidate"

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $extension = [System.IO.Path]::GetExtension($FileName)

    $counter = 1

    do {
        $newName = "{0} ({1}){2}" -f $baseName, $counter, $extension
        $candidate = Join-Path $DestinationDirectory $newName
        $counter++
    }
    while (Test-Path -LiteralPath $candidate)

    Write-Verbose "Resolved to: $candidate"
    return $candidate
}

try {
    Write-Verbose "Resolving path: $Path"
    $resolvedRoot = Resolve-Path -LiteralPath $Path -ErrorAction Stop

    $destinationDirectory = (Get-Location).ProviderPath
    Write-Verbose "Destination directory: $destinationDirectory"

    Write-Host "Scanning: $($resolvedRoot.Path)" -ForegroundColor Cyan

    if ($Depth -eq 0) {
        Write-Host "Depth: unlimited"
    }
    else {
        Write-Host "Maximum depth: $Depth"
    }

    Write-Host ""

    $files = @(Get-TargetFiles `
        -Root $resolvedRoot.Path `
        -MaxDepth $Depth)

    if ($files.Count -eq 0) {
        Write-Warning "No files found."
        return
    }

    Write-Host "Files found: $($files.Count)"
    Start-Sleep -Milliseconds 500

    $selectedFile = Show-FileMenu -Files $files

    if ($null -eq $selectedFile) {
        Clear-Host
        Write-Host "Operation cancelled." -ForegroundColor Yellow
        return
    }

    Clear-Host

    Write-Host "Selected file:" -ForegroundColor Cyan
    Write-Host "  $($selectedFile.FullName)"
    Write-Host ""

    $destinationPath = Get-NonConflictingPath `
        -DestinationDirectory $destinationDirectory `
        -FileName $selectedFile.Name

    Write-Verbose "Copying to: $destinationPath"

    Copy-Item `
        -LiteralPath $selectedFile.FullName `
        -Destination $destinationPath `
        -ErrorAction Stop

    Write-Host "File copied:" -ForegroundColor Green
    Write-Host "  $destinationPath"
}
catch {
    Write-Error "Error: $($_.Exception.Message)"
    throw
}