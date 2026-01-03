param (
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [Parameter(Mandatory = $true)]
    [string]$TargetPath,

    [switch]$DryRun,
    [switch]$Rollback
)

# ================= HELPERS =================
function Log { param($Message)
    if ($DryRun) { Write-Host "[DRY-RUN] $Message" -ForegroundColor Yellow } 
    else { Write-Host $Message }
}

function Normalize-Path { param($Path) ; return ([IO.Path]::GetFullPath($Path)).TrimEnd('\') }

$SourcePath = Normalize-Path $SourcePath
$TargetPath = Normalize-Path $TargetPath

# ================= ROLLBACK =================
if ($Rollback) {
    Log "Rollback started"

    if (-not (Test-Path $SourcePath)) { throw "Source path does not exist: $SourcePath" }
    if (-not (Test-Path $TargetPath)) { throw "Target path does not exist: $TargetPath" }

    $sourceItem = Get-Item $SourcePath
    if ($sourceItem.LinkType -ne 'SymbolicLink') { throw "Source path is not a symlink" }

    # Удаляем symlink
    Log "Removing symlink at SourcePath"
    if (-not $DryRun) { Remove-Item $SourcePath -Force }

    # Создаём обычную папку
    Log "Creating normal directory at SourcePath"
    if (-not $DryRun) { New-Item -ItemType Directory -Path $SourcePath | Out-Null }

    # Копируем файлы обратно
    Log "Copying files from TargetPath to SourcePath"
    $robocopyArgs = @(
        $TargetPath,
        $SourcePath,
        "/E",
        "/COPYALL",
        "/R:2",
        "/W:1",
        "/NFL",
        "/NDL",
        "/NP"
    )
    if (-not $DryRun) { robocopy @robocopyArgs | Out-Null }

    # Удаляем пустую Target
    if (-not $DryRun) {
        if ((Get-ChildItem $TargetPath -Force | Measure-Object).Count -eq 0) {
            Log "Target is empty, removing TargetPath"
            Remove-Item $TargetPath -Force
        }
    }

    Log "Rollback complete. SourcePath is restored as a normal folder."
    exit 0
}

# ================= NORMAL MODE =================
if (-not (Test-Path $SourcePath)) { throw "Source path does not exist" }

$Items = Get-ChildItem $SourcePath -Force -ErrorAction SilentlyContinue
if ($Items.Count -eq 0) {
    Log "Source folder is empty"

    if (-not $DryRun) {
        if (-not (Test-Path $TargetPath)) { New-Item -ItemType Directory -Path $TargetPath | Out-Null }
        Remove-Item $SourcePath -Force
        New-Item -ItemType SymbolicLink -Path $SourcePath -Target $TargetPath | Out-Null
    }
    Log "Done"
    exit 0
}

# ================= COPY DATA =================
Log "Copying data to target"

if (-not (Test-Path $TargetPath)) { if (-not $DryRun) { New-Item -ItemType Directory -Path $TargetPath | Out-Null } }

$robocopyArgs = @(
    $SourcePath,
    $TargetPath,
    "/E",
    "/COPYALL",
    "/R:2",
    "/W:1",
    "/NFL",
    "/NDL",
    "/NP"
)
Log "robocopy $($robocopyArgs -join ' ')"

if (-not $DryRun) { robocopy @robocopyArgs | Out-Null }

# ================= DELETE SOURCE AND CREATE SYMLINK =================
Log "Creating symlink"

if (-not $DryRun) {
    Remove-Item $SourcePath -Recurse -Force
    New-Item -ItemType SymbolicLink -Path $SourcePath -Target $TargetPath | Out-Null
}

Log "Done"
