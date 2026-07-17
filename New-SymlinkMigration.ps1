<#
.SYNOPSIS
    Moves a folder to a new location and replaces the original path with a
    symbolic link pointing to the new location.

.DESCRIPTION
    Workflow:
      1. Run security / sanity checks (permissions, admin/dev-mode rights,
         source exists, destination is writable, enough free space).
      2. Accept source and destination paths.
      3. Copy the source folder to the destination.
      4. Delete the original folder.
      5. Create a symbolic link at the original path pointing to the
         destination copy.

.PARAMETER SourcePath
    Full path to the folder you want to relocate.

.PARAMETER DestinationPath
    Full path to where the folder's contents should be copied. If this path
    already exists as a directory, a subfolder named like the source will be
    created inside it (similar to how `robocopy`/`xcopy` behave). Otherwise
    the destination path itself becomes the new folder.

.PARAMETER Force
    Skip the interactive confirmation prompt before deleting the source
    folder.

.PARAMETER WhatIf
    Show what would happen without making any changes.

.EXAMPLE
    .\New-SymlinkMigration.ps1 -SourcePath "C:\Data\Projects" -DestinationPath "D:\Archive"

.NOTES
    Creating a symbolic link on Windows requires either:
      - An elevated (Run as Administrator) PowerShell session, OR
      - Developer Mode enabled (Windows 10 1703+/Windows 11), which grants
        the SeCreateSymbolicLinkPrivilege to standard users.
    The script checks for this before doing anything destructive.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [Parameter(Mandatory = $true)]
    [string]$DestinationPath,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "    [OK] $Message" -ForegroundColor Green
}

function Write-Fail {
    param([string]$Message)
    Write-Host "    [FAIL] $Message" -ForegroundColor Red
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-DeveloperModeEnabled {
    try {
        $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
        $val = Get-ItemProperty -Path $key -Name 'AllowDevelopmentWithoutDevLicense' -ErrorAction Stop
        return [bool]$val.AllowDevelopmentWithoutDevLicense
    } catch {
        return $false
    }
}

function Get-FolderSizeBytes {
    param([string]$Path)
    $size = (Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
             Measure-Object -Property Length -Sum).Sum
    if (-not $size) { $size = 0 }
    return $size
}

function Get-FreeSpaceBytes {
    param([string]$Path)
    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    $drive = (Get-Item -LiteralPath $resolved).PSDrive.Name
    $vol = Get-PSDrive -Name $drive
    return $vol.Free
}

function Format-Bytes {
    param([double]$Bytes)
    $units = 'B','KB','MB','GB','TB'
    $i = 0
    while ($Bytes -ge 1024 -and $i -lt $units.Length - 1) {
        $Bytes /= 1024
        $i++
    }
    return "{0:N2} {1}" -f $Bytes, $units[$i]
}

# -------------------------------------------------------------------------
# STEP 1: Security / pre-flight checks
# -------------------------------------------------------------------------
Write-Step "Running pre-flight security checks"

$checksPassed = $true

# 1a. Elevation / symlink privilege check
if (Test-IsAdmin) {
    Write-Ok "Running with Administrator privileges."
} elseif (Test-DeveloperModeEnabled) {
    Write-Ok "Developer Mode is enabled — symlink creation permitted without elevation."
} else {
    Write-Fail "Not elevated and Developer Mode is not enabled. Symbolic link creation will fail."
    Write-Host "    -> Re-run this script as Administrator, or enable Developer Mode." -ForegroundColor Yellow
    $checksPassed = $false
}

# 1b. Source exists and is a directory
if (-not (Test-Path -LiteralPath $SourcePath -PathType Container)) {
    Write-Fail "Source path does not exist or is not a folder: $SourcePath"
    $checksPassed = $false
} else {
    Write-Ok "Source folder exists: $SourcePath"
}

# 1c. Read access on source
if ($checksPassed -or (Test-Path -LiteralPath $SourcePath -PathType Container)) {
    try {
        Get-ChildItem -LiteralPath $SourcePath -Force -ErrorAction Stop | Out-Null
        Write-Ok "Read access confirmed on source folder."
    } catch {
        Write-Fail "No read access to source folder: $($_.Exception.Message)"
        $checksPassed = $false
    }
}

# 1d. Determine effective destination folder path
$sourceLeaf = Split-Path -Path $SourcePath -Leaf
if (Test-Path -LiteralPath $DestinationPath -PathType Container) {
    $effectiveDestination = Join-Path $DestinationPath $sourceLeaf
} else {
    $effectiveDestination = $DestinationPath
}

if (Test-Path -LiteralPath $effectiveDestination) {
    Write-Fail "Destination already exists, refusing to overwrite: $effectiveDestination"
    $checksPassed = $false
} else {
    Write-Ok "Destination target is free: $effectiveDestination"
}

# 1e. Write access on destination parent
$destinationParent = Split-Path -Path $effectiveDestination -Parent
if (-not (Test-Path -LiteralPath $destinationParent -PathType Container)) {
    try {
        New-Item -ItemType Directory -Path $destinationParent -Force -WhatIf:$WhatIfPreference | Out-Null
        Write-Ok "Created missing destination parent: $destinationParent"
    } catch {
        Write-Fail "Cannot create destination parent folder: $($_.Exception.Message)"
        $checksPassed = $false
    }
}

if (Test-Path -LiteralPath $destinationParent -PathType Container) {
    try {
        $testFile = Join-Path $destinationParent ".write_test_$([guid]::NewGuid().ToString('N')).tmp"
        [IO.File]::WriteAllText($testFile, 'test')
        Remove-Item -LiteralPath $testFile -Force
        Write-Ok "Write access confirmed on destination parent."
    } catch {
        Write-Fail "No write access to destination parent: $($_.Exception.Message)"
        $checksPassed = $false
    }
}

# 1f. Free space check
if ($checksPassed) {
    Write-Step "Checking free space"
    $sourceSize = Get-FolderSizeBytes -Path $SourcePath
    $freeSpace  = Get-FreeSpaceBytes -Path $destinationParent

    Write-Host "    Source size : $(Format-Bytes $sourceSize)"
    Write-Host "    Free space  : $(Format-Bytes $freeSpace)"

    # 5% safety margin
    $requiredWithMargin = $sourceSize * 1.05

    if ($freeSpace -lt $requiredWithMargin) {
        Write-Fail "Not enough free space at destination. Need at least $(Format-Bytes $requiredWithMargin), have $(Format-Bytes $freeSpace)."
        $checksPassed = $false
    } else {
        Write-Ok "Sufficient free space available."
    }
}

if (-not $checksPassed) {
    Write-Host "`nPre-flight checks failed. Aborting — no changes were made." -ForegroundColor Red
    exit 1
}

Write-Ok "All security checks passed."

# -------------------------------------------------------------------------
# STEP 2 (paths already captured via parameters) — summary
# -------------------------------------------------------------------------
Write-Step "Summary"
Write-Host "    Source              : $SourcePath"
Write-Host "    Destination copy    : $effectiveDestination"
Write-Host "    Symlink will replace: $SourcePath"

if (-not $Force -and -not $WhatIfPreference) {
    $confirmation = Read-Host "`nProceed with copy, delete, and symlink creation? (y/N)"
    if ($confirmation -notmatch '^[Yy]') {
        Write-Host "Aborted by user." -ForegroundColor Yellow
        exit 0
    }
}

# -------------------------------------------------------------------------
# STEP 3: Copy source folder to destination
# -------------------------------------------------------------------------
Write-Step "Copying folder to destination"
if ($PSCmdlet.ShouldProcess($effectiveDestination, "Copy from $SourcePath")) {
    try {
        Copy-Item -LiteralPath $SourcePath -Destination $effectiveDestination -Recurse -Force -ErrorAction Stop
        Write-Ok "Copy completed: $effectiveDestination"
    } catch {
        Write-Fail "Copy failed: $($_.Exception.Message)"
        exit 1
    }

    # Verify copy integrity by comparing file counts and total size
    $srcCount = (Get-ChildItem -LiteralPath $SourcePath -Recurse -Force -ErrorAction SilentlyContinue).Count
    $dstCount = (Get-ChildItem -LiteralPath $effectiveDestination -Recurse -Force -ErrorAction SilentlyContinue).Count
    $dstSize  = Get-FolderSizeBytes -Path $effectiveDestination

    if ($srcCount -ne $dstCount) {
        Write-Fail "Item count mismatch after copy (source: $srcCount, destination: $dstCount). Aborting before delete."
        exit 1
    }
    if ($dstSize -lt $sourceSize) {
        Write-Fail "Size mismatch after copy (source: $(Format-Bytes $sourceSize), destination: $(Format-Bytes $dstSize)). Aborting before delete."
        exit 1
    }
    Write-Ok "Copy verified (item count and size match)."
}

# -------------------------------------------------------------------------
# STEP 4: Delete the old folder
# -------------------------------------------------------------------------
Write-Step "Removing original folder"
if ($PSCmdlet.ShouldProcess($SourcePath, "Remove original folder")) {
    try {
        Remove-Item -LiteralPath $SourcePath -Recurse -Force -ErrorAction Stop
        Write-Ok "Original folder removed: $SourcePath"
    } catch {
        Write-Fail "Failed to remove original folder: $($_.Exception.Message)"
        Write-Host "    The copy at $effectiveDestination is intact; no symlink was created." -ForegroundColor Yellow
        exit 1
    }
}

# -------------------------------------------------------------------------
# STEP 5: Create symbolic link at the original path
# -------------------------------------------------------------------------
Write-Step "Creating symbolic link"
if ($PSCmdlet.ShouldProcess($SourcePath, "Create symbolic link -> $effectiveDestination")) {
    try {
        New-Item -ItemType SymbolicLink -Path $SourcePath -Target $effectiveDestination -ErrorAction Stop | Out-Null
        Write-Ok "Symbolic link created: $SourcePath -> $effectiveDestination"
    } catch {
        Write-Fail "Failed to create symbolic link: $($_.Exception.Message)"
        Write-Host "    WARNING: original folder was already deleted. Data is safe at $effectiveDestination" -ForegroundColor Yellow
        Write-Host "    Re-run manually: New-Item -ItemType SymbolicLink -Path '$SourcePath' -Target '$effectiveDestination'" -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "`nDone. '$SourcePath' is now a symbolic link pointing to '$effectiveDestination'." -ForegroundColor Green
