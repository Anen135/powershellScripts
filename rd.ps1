<#
.SYNOPSIS
    Moves a folder to a new location and replaces the original with a symbolic link.

.DESCRIPTION
    Uses Robocopy to move all contents from a source folder to a destination,
    then replaces the original folder with a symbolic link pointing to the
    new location. Supports dry-run preview and rollback of a previous move
    operation. Requires Administrator privileges or Developer Mode for
    symlink creation.

.PARAMETER Source
    Full path to the source folder to relocate.

.PARAMETER Destination
    Full path to the destination where folder contents will be moved.

.PARAMETER DryRun
    Preview mode — shows what would happen without making any changes.

.PARAMETER Rollback
    Undo a previous move operation by removing the symlink, recreating the
    original folder, and moving data back from the destination.

.EXAMPLE
    .\rd.ps1 -Source "C:\Data\Projects" -Destination "D:\Archive"

.EXAMPLE
    .\rd.ps1 -Source "C:\Data\Projects" -Destination "D:\Archive" -DryRun

.EXAMPLE
    .\rd.ps1 -Source "C:\Data\Projects" -Destination "D:\Archive" -Rollback

.NOTES
    Version: 1.0
    Author: Anen
#>

param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$Source,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Destination,

    [switch]$DryRun,
    [switch]$Rollback
)

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    if ($DryRun) {
        Write-Host "[DRY-RUN] $Message" -ForegroundColor Yellow
    }
    else {
        Write-Host $Message -ForegroundColor $Color
    }
}

function Get-NormalizedPath {
    param([string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full.Length -gt 3) { $full = $full.TrimEnd('\') }
    $full
}

$Source = Get-NormalizedPath $Source
$Destination = Get-NormalizedPath $Destination

$LogFile = Join-Path $env:TEMP "robomove_$(Get-Date -Format yyyyMMdd_HHmmss).log"


if ($Rollback) {
    Write-Log "Rollback mode activated" -Color Cyan

    
    if (-not (Test-Path $Source)) { throw "Source path does not exist: $Source" }
    if (-not (Test-Path $Destination)) { throw "Destination path does not exist: $Destination" }

    $sourceItem = Get-Item $Source -Force
    if ($sourceItem.LinkType -ne "SymbolicLink") {
        throw "Source path is not a symbolic link: $Source"
    }

    Write-Log "Removing symbolic link at $Source"
    if (-not $DryRun) { Remove-Item $Source -Recurse -Force }

    Write-Log "Recreating directory at $Source"
    if (-not $DryRun) { New-Item -ItemType Directory -Path $Source -Force | Out-Null }

    Write-Log "Moving data back from $Destination to $Source (using /MOV)"
    $robocopyArgs = @(
    $Destination, $Source,
    "/MOV", "/E", "/MT:16", "/R:3", "/W:5"
    )
    if ($DryRun) { $robocopyArgs += "/L" }

    Write-Log "robocopy $($robocopyArgs -join ' ')"

    if (-not $DryRun) {

        $originalEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(866)

    try {
        $robocopyOutput = robocopy @robocopyArgs

        $robocopyOutput | Out-File $LogFile -Encoding utf8

        $exitCode = $LASTEXITCODE
    }
    finally {
        [Console]::OutputEncoding = $originalEncoding
    }

    if ($exitCode -ge 8) {
        throw "Robocopy failed during rollback (code $exitCode). Data may be incomplete. See log: $LogFile"
    }
    if ($exitCode -gt 1) {
        Write-Log "Robocopy completed rollback with warnings (code $exitCode). Check log." -Color Magenta
    }
        
        $remaining = Get-ChildItem -Path $Destination -Recurse -File -Force -ErrorAction SilentlyContinue
        if ($remaining) {
            Write-Log "Warning: $Destination is not empty after move ($($remaining.Count) files remain). Leaving it intact." -Color Yellow
        }
        else {
            Write-Log "Destination is now empty. Removing $Destination"
            Remove-Item $Destination -Recurse -Force
        }
    }

        Write-Log "Rollback completed successfully. Original location restored." -Color Green
        exit 0
}



Write-Log "Starting move operation: $Source -> $Destination" -Color Cyan


$items = Get-ChildItem $Source -Force -ErrorAction SilentlyContinue
if ($items.Count -eq 0) {
    Write-Log "Source folder is already empty"

    if (-not (Test-Path $Destination)) {
        Write-Log "Creating destination directory: $Destination"
        if (-not $DryRun) { New-Item -ItemType Directory -Path $Destination -Force | Out-Null }
    }

    Write-Log "Removing empty source and creating symlink"
    if (-not $DryRun) {
        Remove-Item $Source -Recurse -Force
        try {
            New-Item -ItemType SymbolicLink -Path $Source -Target $Destination -ErrorAction Stop | Out-Null
            Write-Log "Success: Empty folder replaced with symlink $Source -> $Destination" -Color Green
        }
        catch {
            throw "Failed to create symbolic link. Run as Administrator or enable Developer Mode. Error: $_"
        }
    }
    exit 0
}


if (-not (Test-Path $Destination)) {
    Write-Log "Creating destination directory: $Destination"
    if (-not $DryRun) { New-Item -ItemType Directory -Path $Destination -Force | Out-Null }
}


Write-Log "Copying and moving files (this may take a while for large directories)"


$robocopyArgs = @(
    $Source, $Destination,
    "/MOV", "/E", "/MT:16", "/R:3", "/W:5"
)
if ($DryRun) { $robocopyArgs += "/L" }

Write-Log "robocopy $($robocopyArgs -join ' ')"

if (-not $DryRun) {

    $originalEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(866)

    try {
        $robocopyOutput = robocopy @robocopyArgs

        
        $robocopyOutput | Out-File $LogFile -Encoding utf8

        $exitCode = $LASTEXITCODE
    }
    finally {
        
        [Console]::OutputEncoding = $originalEncoding
    }

    if ($exitCode -ge 8) {
        throw "Robocopy failed with serious errors (code $exitCode). Aborting to prevent data loss. See log: $LogFile"
    }
    if ($exitCode -gt 1) {
        Write-Log "Robocopy completed with some issues (code $exitCode). Check log: $LogFile" -Color Magenta
    }
}


if (-not $DryRun) {
    $remaining = Get-ChildItem -Path $Source -Recurse -File -Force -ErrorAction SilentlyContinue
    if ($remaining) {
        throw "Source directory is not empty after move ($($remaining.Count) files remain). Aborting symlink creation to prevent data loss. See log: $LogFile"
    }
}


Write-Log "Removing original directory and creating symbolic link"
if (-not $DryRun) {
    Remove-Item $Source -Recurse -Force

    try {
        New-Item -ItemType SymbolicLink -Path $Source -Target $Destination -ErrorAction Stop | Out-Null
        Write-Log "SUCCESS: Data moved and symbolic link created: $Source -> $Destination" -Color Green
        Write-Log "Robocopy log saved to: $LogFile" -Color Cyan
    }
    catch {
        throw "Failed to create symbolic link. Requires Administrator rights or Developer Mode enabled. Error: $_"
    }
}
else {
    Write-Log "Dry-run complete. No changes made." -Color Yellow
    Write-Log "Planned robocopy log would be: $LogFile" -Color Cyan
}